# type: ignore
"""
Accounts, short-lived access tokens and rotating refresh tokens.

  * Passwords: scrypt (stdlib hashlib), per-user random salt.
  * Access token: a JWT (HS256, MYANALYST_JWT_SECRET) valid for 15 minutes.
    Verified by signature alone (no database lookup). Algorithm, issuer and
    token type are pinned when decoding.
  * Refresh token: an opaque 256-bit random string valid for 30 days,
    sliding. Only its SHA-256 hash is stored. Every use rotates it; a token
    presented a second time means it was copied, so that whole sign-in
    ("family") is revoked and the device must sign in again.
  * Logout revokes the family of the presented refresh token: this device
    only. Other devices stay signed in.
  * Failed logins are rate-limited per username.

Tables live on memory.Base, so memory.init_db() creates them. They are
named `accounts` / `refresh_tokens` to stay clear of the legacy `users`
table in models.py.

Set MYANALYST_AUTH_DISABLED=1 for local development without logins; all
requests then act as a single "local" user.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.exc import IntegrityError

import memory
from config import settings

MAX_FAILED = 5
LOCKOUT_SECONDS = 15 * 60
ISSUER = "myanalyst"
ALGORITHM = "HS256"
AUTH_DISABLED = os.environ.get("MYANALYST_AUTH_DISABLED", "").lower() in ("1", "true", "yes")

_bearer = HTTPBearer(auto_error=False)
_failures: dict[str, list[float]] = {}
_failures_lock = threading.Lock()


# --------------------------------------------------------------------------
# Tables
# --------------------------------------------------------------------------

def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Account(memory.Base):
    __tablename__ = "accounts"
    id = Column(Integer, primary_key=True, autoincrement=True)
    username = Column(String(64), unique=True, nullable=False, index=True)
    password_hash = Column(String(64), nullable=False)
    salt = Column(String(32), nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow)


class RefreshToken(memory.Base):
    __tablename__ = "refresh_tokens"
    token_hash = Column(String(64), primary_key=True)  # sha256 hex; the token itself is never stored
    family_id = Column(String(32), nullable=False, index=True)  # one per sign-in on one device
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow)
    used_at = Column(DateTime(timezone=True))  # set when rotated; presenting it again = reuse
    revoked_at = Column(DateTime(timezone=True))  # logout or detected reuse


# --------------------------------------------------------------------------
# API models
# --------------------------------------------------------------------------

class Credentials(BaseModel):
    username: str = Field(..., min_length=3, max_length=64, pattern=r"^[A-Za-z0-9_.@-]+$")
    password: str = Field(..., min_length=8, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(..., min_length=20, max_length=200)


class TokenResponse(BaseModel):
    """Send `access_token` as `Authorization: Bearer`. Keep `refresh_token` in
    secure storage and swap it at POST /auth/refresh; each one works once."""
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    refresh_token: str
    username: str


@dataclass(frozen=True)
class User:
    id: int
    username: str


def check_configuration() -> None:
    """Called at startup: refuse to run with a missing or weak signing key."""
    if AUTH_DISABLED:
        return
    if len(settings.JWT_SECRET) < 32:
        raise RuntimeError(
            "MYANALYST_JWT_SECRET must be set to a random string of at least 32 characters. Generate one with: "
            'python -c "import secrets; print(secrets.token_urlsafe(48))"'
        )


# --------------------------------------------------------------------------
# Passwords and tokens
# --------------------------------------------------------------------------

def _hash_password(password: str, salt: bytes) -> str:
    return hashlib.scrypt(password.encode("utf-8"), salt=salt, n=2**14, r=8, p=1, dklen=32).hex()


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def _access_token(user: User) -> tuple[str, int]:
    now = _utcnow()
    ttl = settings.ACCESS_TOKEN_MINUTES * 60
    claims = {
        "iss": ISSUER, "sub": str(user.id), "name": user.username, "typ": "access",
        "iat": now, "exp": now + timedelta(seconds=ttl), "jti": uuid.uuid4().hex,
    }
    return jwt.encode(claims, settings.JWT_SECRET, algorithm=ALGORITHM), ttl


def _refresh_expiry() -> datetime:
    return _utcnow() + timedelta(days=settings.REFRESH_TOKEN_DAYS)


def _issue(db, user: User, family_id: str | None = None) -> TokenResponse:
    access, ttl = _access_token(user)
    refresh = secrets.token_urlsafe(32)
    db.add(RefreshToken(token_hash=_hash_token(refresh), family_id=family_id or uuid.uuid4().hex,
                        account_id=user.id, expires_at=_refresh_expiry()))
    db.commit()
    return TokenResponse(access_token=access, expires_in=ttl, refresh_token=refresh, username=user.username)


def _normalise(username: str) -> str:
    return username.strip().lower()


# --------------------------------------------------------------------------
# Routes
# --------------------------------------------------------------------------

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse)
def register(payload: Credentials) -> TokenResponse:
    username = _normalise(payload.username)
    salt = secrets.token_bytes(16)
    with memory.SessionLocal() as db:
        account = Account(username=username, password_hash=_hash_password(payload.password, salt), salt=salt.hex())
        db.add(account)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(status.HTTP_409_CONFLICT, "That username is taken.") from None
        return _issue(db, User(account.id, username))


@router.post("/login", response_model=TokenResponse)
def login(payload: Credentials) -> TokenResponse:
    username = _normalise(payload.username)
    now = time.monotonic()
    with _failures_lock:
        recent = [t for t in _failures.get(username, []) if now - t < LOCKOUT_SECONDS]
        _failures[username] = recent
        if len(recent) >= MAX_FAILED:
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Too many attempts. Try again in 15 minutes.")
    with memory.SessionLocal() as db:
        account = db.query(Account).filter_by(username=username).first()
        # Hash even for unknown users so response time doesn't reveal which exist.
        salt = bytes.fromhex(account.salt) if account else b"\x00" * 16
        candidate = _hash_password(payload.password, salt)
        if account is None or not hmac.compare_digest(candidate, account.password_hash):
            with _failures_lock:
                _failures.setdefault(username, []).append(now)
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Wrong username or password.")
        with _failures_lock:
            _failures.pop(username, None)
        return _issue(db, User(account.id, account.username))


@router.post("/refresh", response_model=TokenResponse)
def refresh(payload: RefreshRequest) -> TokenResponse:
    """Swaps a refresh token for a new pair. No access token needed: this is
    how an expired one gets replaced."""
    ended = HTTPException(status.HTTP_401_UNAUTHORIZED, "Session ended. Sign in again.")
    with memory.SessionLocal() as db:
        # Row lock: two concurrent refreshes with the same token can't both win.
        row = (db.query(RefreshToken).filter_by(token_hash=_hash_token(payload.refresh_token))
               .with_for_update().first())
        if row is None:
            raise ended
        now = _utcnow()
        if row.used_at is not None or row.revoked_at is not None:
            # Reuse of a spent token: assume theft, revoke that whole sign-in.
            (db.query(RefreshToken).filter_by(family_id=row.family_id)
             .filter(RefreshToken.revoked_at.is_(None)).update({"revoked_at": now}))
            db.commit()
            raise ended
        expires = row.expires_at if row.expires_at.tzinfo else row.expires_at.replace(tzinfo=timezone.utc)
        if expires < now:
            raise ended
        account = db.get(Account, row.account_id)
        if account is None:
            raise ended
        row.used_at = now
        return _issue(db, User(account.id, account.username), family_id=row.family_id)


@router.post("/logout", status_code=204)
def logout(payload: RefreshRequest) -> None:
    """Signs out this device only. Works with an expired access token."""
    with memory.SessionLocal() as db:
        row = db.query(RefreshToken).filter_by(token_hash=_hash_token(payload.refresh_token)).first()
        if row is not None:
            (db.query(RefreshToken).filter_by(family_id=row.family_id)
             .filter(RefreshToken.revoked_at.is_(None)).update({"revoked_at": _utcnow()}))
            db.commit()


# --------------------------------------------------------------------------
# Dependency
# --------------------------------------------------------------------------

def _local_user() -> User:
    with memory.SessionLocal() as db:
        account = db.query(Account).filter_by(username="local").first()
        if account is None:
            account = Account(username="local", password_hash="!", salt="00")
            db.add(account)
            db.commit()
        return User(account.id, "local")


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> User:
    if AUTH_DISABLED:
        return _local_user()
    unauthorized = HTTPException(status.HTTP_401_UNAUTHORIZED, "Sign in required.",
                                 headers={"WWW-Authenticate": "Bearer"})
    if creds is None or creds.scheme.lower() != "bearer":
        raise unauthorized
    try:
        claims = jwt.decode(
            creds.credentials, settings.JWT_SECRET,
            algorithms=[ALGORITHM],  # pinned: rejects "none" and algorithm-swap tokens
            issuer=ISSUER, options={"require": ["exp", "iat", "sub", "iss"]}, leeway=10,
        )
    except jwt.PyJWTError:
        raise unauthorized from None
    if claims.get("typ") != "access":
        raise unauthorized
    try:
        return User(int(claims["sub"]), str(claims.get("name", "")))
    except (TypeError, ValueError):
        raise unauthorized from None


@router.get("/me")
def me(user: User = Depends(current_user)) -> dict[str, str]:
    return {"username": user.username}
