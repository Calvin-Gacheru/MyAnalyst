# type: ignore
"""
Cash-flow snapshot, cash-gap projection and financing fit.

Everything here is deterministic pandas arithmetic: the numbers a business
owner (or a lender) will act on never come from an LLM. The LLM only gets
these figures as facts to write about.

Entry point: `analyse_cashflow(df, cash_on_hand=None)`. It returns a
JSON-serialisable dict, or {"detected": False, "reason": ...} when the data
isn't transaction-shaped.
"""
from __future__ import annotations

import math
import re
from typing import Any

import numpy as np
import pandas as pd

_AMOUNT_NAMES = re.compile(r"(?:amount|amt|value|money|total|sum|revenue|sales|price|金额|收入|支出)", re.I)
_BALANCE_NAMES = re.compile(r"(?:balance|余额)", re.I)
_DEBIT_NAMES = re.compile(r"(?:debit|withdraw|outflow|paid out|expense|支出|借方)", re.I)
_CREDIT_NAMES = re.compile(r"(?:credit|deposit|inflow|paid in|income|收入|贷方)", re.I)
_TYPE_NAMES = re.compile(r"(?:type|direction|flow|收支|类型|in_out)", re.I)
_CATEGORY_NAMES = re.compile(r"(?:category|categ|type|class|科目|类别|分类|item|product|name)", re.I)
_OUT_WORDS = re.compile(r"(?:debit|expense|out|payment|withdraw|支出|付款|借)", re.I)
_IN_WORDS = re.compile(r"(?:credit|income|in\b|deposit|receipt|收入|收款|贷)", re.I)

_SUPPLIER_WORDS = re.compile(r"(?:supplier|ingredient|inventory|stock|purchase|material|goods|采购|原料|货款|进货)", re.I)
_INVOICE_WORDS = re.compile(r"(?:invoice|wholesale|receivable|b2b|contract|发票|应收|批发)", re.I)
_PLATFORM_WORDS = re.compile(r"(?:wechat|alipay|tenpay|meituan|pos|card|qr|unionpay|微信|支付宝|美团)", re.I)

HORIZON_WEEKS = 13  # ~90 days
Z80 = 1.2816  # 80% interval (10th-90th percentile)


def _pick(columns: list[str], pattern: re.Pattern[str], exclude: set[str] = frozenset()) -> str | None:
    for c in columns:
        if c not in exclude and pattern.search(str(c)):
            return c
    return None


def detect_columns(df: pd.DataFrame, flagged_ids: set[str] = frozenset()) -> dict[str, Any] | None:
    cols = [c for c in df.columns if c not in flagged_ids]
    dates = [c for c in cols if pd.api.types.is_datetime64_any_dtype(df[c])]
    if not dates:
        return None
    date_col = next((c for c in dates if str(c).lower() == "date"), dates[0])
    numeric = [c for c in cols if pd.api.types.is_numeric_dtype(df[c]) and not pd.api.types.is_bool_dtype(df[c])]
    balance_col = _pick(numeric, _BALANCE_NAMES)
    textual = [c for c in cols if c not in numeric and c not in dates]

    debit_col = _pick(numeric, _DEBIT_NAMES, {balance_col})
    credit_col = _pick(numeric, _CREDIT_NAMES, {balance_col, debit_col})
    if debit_col and credit_col:
        mode, amount_col, type_col = "debit_credit", None, None
    else:
        amount_col = _pick(numeric, _AMOUNT_NAMES, {balance_col}) or next(
            (c for c in numeric if c != balance_col), None)
        if amount_col is None:
            return None
        neg_share = float((df[amount_col] < 0).mean())
        type_col = None
        if neg_share >= 0.02:
            mode = "signed"
        else:
            type_col = _pick(textual, _TYPE_NAMES)
            if type_col is not None:
                vals = df[type_col].astype(str)
                mode = "typed" if vals.str.contains(_OUT_WORDS).any() and vals.str.contains(_IN_WORDS).any() else "inflow_only"
            else:
                mode = "inflow_only"
            if mode == "inflow_only":
                type_col = None

    category_col = next((c for c in textual if c != type_col and _CATEGORY_NAMES.search(str(c))
                         and 1 < df[c].nunique() <= 60), None)
    return {
        "date": date_col, "amount": amount_col, "debit": debit_col if mode == "debit_credit" else None,
        "credit": credit_col if mode == "debit_credit" else None, "type": type_col, "balance": balance_col,
        "category": category_col, "mode": mode,
    }


def _signed_frame(df: pd.DataFrame, cols: dict[str, Any]) -> pd.DataFrame:
    d = pd.DataFrame({"date": pd.to_datetime(df[cols["date"]], errors="coerce")})
    if cols["mode"] == "debit_credit":
        d["amount"] = df[cols["credit"]].fillna(0).astype(float) - df[cols["debit"]].fillna(0).abs().astype(float)
    elif cols["mode"] == "typed":
        out = df[cols["type"]].astype(str).str.contains(_OUT_WORDS)
        d["amount"] = np.where(out, -df[cols["amount"]].abs(), df[cols["amount"]].abs()).astype(float)
    else:
        d["amount"] = df[cols["amount"]].astype(float)
    d["category"] = df[cols["category"]].astype(str) if cols["category"] else "All"
    text_cols = [c for c in df.columns if df[c].dtype == object or isinstance(df[c].dtype, pd.CategoricalDtype)]
    d["text"] = df[text_cols].astype(str).agg(" ".join, axis=1) if text_cols else ""
    if cols["balance"]:
        d["balance"] = df[cols["balance"]].astype(float)
    return d.dropna(subset=["date", "amount"]).sort_values("date", kind="stable")


def _r(x: float | None, nd: int = 2) -> float | None:
    return None if x is None or (isinstance(x, float) and not math.isfinite(x)) else round(float(x), nd)


def analyse_cashflow(
    df: pd.DataFrame, flagged_ids: set[str] = frozenset(), cash_on_hand: float | None = None
) -> dict[str, Any]:
    cols = detect_columns(df, flagged_ids)
    if cols is None:
        return {"detected": False, "reason": "no_date_or_amount"}
    tx = _signed_frame(df, cols)
    if len(tx) < 10 or tx["date"].nunique() < 7:
        return {"detected": False, "reason": "too_little_history"}

    inflow_only = cols["mode"] == "inflow_only"
    tx["month"] = tx["date"].dt.to_period("M")
    monthly = tx.groupby("month")["amount"].agg(
        inflow=lambda s: s[s > 0].sum(), outflow=lambda s: -s[s < 0].sum(), net="sum")
    first, last = tx["date"].min(), tx["date"].max()
    # Partial first/last months distort averages; use full months where we can.
    full = monthly.copy()
    if first.day > 3 and len(full) > 2:
        full = full.iloc[1:]
    if last.day < last.days_in_month - 3 and len(full) > 2:
        full = full.iloc[:-1]
    recent = full.tail(3)

    avg_in, avg_out = float(recent["inflow"].mean()), float(recent["outflow"].mean())
    avg_net = float(recent["net"].mean())
    burn = -avg_net if (avg_net < 0 and not inflow_only) else 0.0

    balance_source = "unknown"
    if cash_on_hand is not None:
        balance_source = "user"
    elif cols["balance"]:
        cash_on_hand = float(tx["balance"].iloc[-1])
        balance_source = "statement"

    runway = None
    if cash_on_hand is not None and burn > 0:
        runway = max(cash_on_hand, 0) / burn

    # --- Projection: recent average net, weekly steps, with an 80% range ---
    projection, gap = [], None
    if not inflow_only and cash_on_hand is not None:
        # Uncertainty from month-to-month swings, not week-to-week: payroll
        # and rent land in single weeks, which would exaggerate the range.
        sigma_m = float(full["net"].tail(6).std(ddof=1)) if len(full) >= 3 else abs(avg_net) * 0.25
        if not math.isfinite(sigma_m):
            sigma_m = abs(avg_net) * 0.25
        mu_w = avg_net / 4.345
        for w in range(1, HORIZON_WEEKS + 1):
            mid = cash_on_hand + mu_w * w
            spread = Z80 * sigma_m * math.sqrt(w / 4.345)
            projection.append({"date": (last + pd.Timedelta(weeks=w)).date().isoformat(),
                               "low": _r(mid - spread, 0), "mid": _r(mid, 0), "high": _r(mid + spread, 0)})
        first_low = next((p for p in projection if p["low"] < 0), None)
        if first_low is not None:
            first_mid = next((p for p in projection if p["mid"] < 0), None)
            worst = min(p["low"] for p in projection)
            gap = {
                "likelihood": "likely" if first_mid else "possible",
                "date": (first_mid or first_low)["date"],
                "weeks_away": projection.index(first_mid or first_low) + 1,
                "shortfall": _r(-worst, 0),
                # Round up to a lender-friendly figure.
                "suggested_amount": float(math.ceil(-worst / 10000.0) * 10000),
            }

    def top(kind: str) -> list[dict[str, Any]]:
        sel = tx[tx["date"] >= (last - pd.Timedelta(days=90))]
        sel = sel[sel["amount"] < 0] if kind == "out" else sel[sel["amount"] > 0]
        if sel.empty:
            return []
        g = sel.groupby("category")["amount"].sum().abs().sort_values(ascending=False)
        total = float(g.sum())
        return [{"category": k, "amount": _r(v, 0), "share": _r(v / total, 3)} for k, v in g.head(8).items()]

    top_out, top_in = top("out"), top("in")
    trend = None
    if len(full) >= 4:
        early, late = full["net"].iloc[: len(full) // 2].mean(), full["net"].iloc[len(full) // 2:].mean()
        trend = "improving" if late > early + abs(early) * 0.1 else "worsening" if late < early - abs(early) * 0.1 else "steady"

    result: dict[str, Any] = {
        "detected": True,
        "mode": "inflow_only" if inflow_only else "in_and_out",
        "columns": {k: v for k, v in cols.items() if k != "mode"},
        "period": {"start": first.date().isoformat(), "end": last.date().isoformat(), "months": int(len(monthly))},
        "monthly": [{"month": str(m), "inflow": _r(r.inflow, 0), "outflow": _r(r.outflow, 0), "net": _r(r.net, 0)}
                    for m, r in monthly.iterrows()],
        "recent_months": int(len(recent)),
        "avg_monthly_inflow": _r(avg_in, 0),
        "avg_monthly_outflow": _r(avg_out, 0),
        "avg_monthly_net": _r(avg_net, 0),
        "monthly_burn": _r(burn, 0),
        "trend": trend,
        "cash_on_hand": _r(cash_on_hand, 0),
        "balance_source": balance_source,
        "runway_months": _r(runway, 1),
        "projection": projection,
        "cash_gap": gap,
        "top_outflows": top_out,
        "top_inflows": top_in,
    }
    result["financing"] = financing_fit(result, tx) if not inflow_only else []
    return result


# --------------------------------------------------------------------------
# Financing fit. Returns keys and reasons only; the app holds the wording
# (in English and Chinese) and indicative costs. This is educational
# matching, not a product recommendation.
# --------------------------------------------------------------------------

def financing_fit(cf: dict[str, Any], tx: pd.DataFrame) -> list[dict[str, Any]]:
    gap = cf.get("cash_gap")
    need = gap["suggested_amount"] if gap else max(cf.get("monthly_burn") or 0, 0) * 3
    avg_in = cf.get("avg_monthly_inflow") or 0
    months_history = cf["period"]["months"]
    burn = cf.get("monthly_burn") or 0
    text = " ".join(tx["text"].astype(str).str.lower().head(5000).tolist()) + " " + " ".join(
        c["category"].lower() for c in cf.get("top_outflows", []) + cf.get("top_inflows", []))
    supplier_share = sum(c["share"] or 0 for c in cf.get("top_outflows", []) if _SUPPLIER_WORDS.search(c["category"]))
    invoice_income = bool(_INVOICE_WORDS.search(text))
    # Invoice financing can only advance what customers owe: roughly one
    # month of invoice income. If that's well short of the need, it can only
    # be part of the answer.
    invoice_share = sum(c["share"] or 0 for c in cf.get("top_inflows", []) if _INVOICE_WORDS.search(c["category"]))
    invoice_monthly = invoice_share * avg_in if invoice_share else (avg_in * 0.2 if invoice_income else 0)
    platform_income = bool(_PLATFORM_WORDS.search(text))
    # A worsening trend means the gap is a structural loss, not a timing
    # problem: revolving credit would only defer it.
    ongoing_losses = burn > 0 and cf.get("trend") == "worsening"
    term = int(min(12, max(3, math.ceil(need / burn)))) if burn > 0 else 6

    def item(key: str, fit: str, reasons: list[str]) -> dict[str, Any]:
        return {"key": key, "fit": fit, "reasons": reasons, "amount": need, "months": term}

    out = [
        item("cost_actions", "good" if burn > 0 else "possible", ["burn"] if burn > 0 else []),
        item("supplier_credit", "good" if supplier_share >= 0.2 else "possible" if supplier_share > 0 else "unlikely",
             ["supplier_share"] if supplier_share >= 0.2 else []),
        item("invoice_finance",
             "unlikely" if not invoice_income else "good" if invoice_monthly >= 0.5 * need else "possible",
             ["no_invoices"] if not invoice_income else
             ["invoice_income"] + ([] if invoice_monthly >= 0.5 * need else ["invoice_small"])),
        item("bank_loan",
             "good" if months_history >= 6 and need <= 1.5 * avg_in else "possible" if months_history >= 3 else "unlikely",
             (["history_ok"] if months_history >= 6 else ["short_history"])
             + (["size_ok"] if need <= 1.5 * avg_in else ["large_need"])),
        item("credit_line",
             "possible" if ongoing_losses else
             "good" if gap and gap["weeks_away"] <= 8 and need <= 1.5 * avg_in else "possible",
             ["ongoing_losses"] if ongoing_losses else (["short_term_gap"] if gap and gap["weeks_away"] <= 8 else [])),
        item("platform_loan", "possible" if platform_income else "unlikely",
             ["platform_income", "high_cost"] if platform_income else ["no_platform_income"]),
    ]
    order = {"good": 0, "possible": 1, "unlikely": 2}
    return sorted(out, key=lambda x: order[x["fit"]])


def insights_for_summary(cf: dict[str, Any]) -> list[str]:
    """Plain facts for the executive-summary prompt."""
    if not cf.get("detected"):
        return []
    lines = [f"- Cash flow: average monthly money in {cf['avg_monthly_inflow']:,.0f}, money out "
             f"{cf['avg_monthly_outflow']:,.0f}, net {cf['avg_monthly_net']:,.0f} over the last {cf['recent_months']} full months."]
    if cf.get("cash_on_hand") is not None:
        lines.append(f"- Cash in the bank at the end of the data: {cf['cash_on_hand']:,.0f}.")
    if cf.get("runway_months") is not None:
        lines.append(f"- At the recent burn rate of {cf['monthly_burn']:,.0f} a month, cash lasts about {cf['runway_months']} months.")
    if cf.get("cash_gap"):
        g = cf["cash_gap"]
        lines.append(f"- Cash-gap warning ({g['likelihood']}): balance may fall below zero around {g['date']} "
                     f"(about {g['weeks_away']} weeks away); a buffer of about {g['suggested_amount']:,.0f} would cover the worst case.")
    if cf.get("top_outflows"):
        t = cf["top_outflows"][0]
        lines.append(f"- Largest cost in the last 90 days: {t['category']} ({t['share']:.0%} of spending).")
    return lines
