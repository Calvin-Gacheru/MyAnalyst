# type: ignore
"""
Central configuration for MyAnalyst.

All environment-driven settings live here so other modules never read
`os.environ` directly. Import the module-level `settings` singleton.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent
load_dotenv(PROJECT_ROOT / ".env")


class Settings:
    """Runtime configuration, populated from environment variables."""

    # --- Storage ---
    DATA_DIR: Path = Path(os.environ.get("MYANALYST_DATA_DIR", "./data"))
    UPLOAD_DIR: Path = DATA_DIR / "uploads"
    # SQLAlchemy maps a bare "postgresql://" to psycopg2, which isn't installed;
    # force the psycopg (v3) driver so a plain URL in .env still works.
    DATABASE_URL: str = re.sub(
        r"^postgres(ql)?://",
        "postgresql+psycopg://",
        os.environ.get("DATABASE_URL", "postgresql+psycopg://postgres:postgres@localhost:5432/myanalyst"),
    )


    # --- LLM ---
    # NOTE: point this at whichever current DeepSeek model string your
    # account has access to (e.g., "deepseek-flash" or "deepseek-v4-pro").
    DEEPSEEK_API_KEY: str = os.environ.get("DEEPSEEK_API_KEY", "")
    LLM_MODEL: str = os.environ.get("MYANALYST_LLM_MODEL", "deepseek-flash")
    LLM_MAX_TOKENS: int = int(os.environ.get("MYANALYST_LLM_MAX_TOKENS", "2048"))

    # --- Agent loop guards ---
    MAX_CODER_RETRIES: int = int(os.environ.get("MYANALYST_MAX_CODER_RETRIES", "3"))

    # --- Preprocessing heuristics ---
    HIGH_CARDINALITY_RATIO: float = 0.9    # >90% unique values -> treat as ID column
    LOW_CARDINALITY_RATIO: float = 0.05    # <5% unique values -> candidate for category dtype
    LOW_CARDINALITY_MAX_UNIQUE: int = 50   # hard cap regardless of ratio
    SKEW_THRESHOLD: float = 1.0            # |skew| above this -> median imputation
    IQR_MULTIPLIER: float = 1.5            # standard Tukey fence multiplier

    # --- Sandbox ---
    SANDBOX_DOCKER_IMAGE: str = os.environ.get("MYANALYST_DOCKER_IMAGE", "myanalyst-sandbox:latest")
    SANDBOX_MEM_LIMIT: str = os.environ.get("MYANALYST_SANDBOX_MEM_LIMIT", "1g") # 1 GB
    SANDBOX_NANO_CPUS: int = int(os.environ.get("MYANALYST_SANDBOX_NANO_CPUS", "2000000000"))  # 2 CPUs

    def ensure_dirs(self) -> None:
        self.UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        self.DATA_DIR.mkdir(parents=True, exist_ok=True)


settings = Settings()
