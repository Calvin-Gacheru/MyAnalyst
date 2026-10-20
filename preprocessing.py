"""
Deterministic, rule-based data preparation.

Everything in this module runs BEFORE any LLM is involved (Workflow step 1)
or purely mechanically as remediation (Workflow step 2). No network calls,
no non-determinism: given the same input CSV, the output is always
identical, which is what makes it safe to run unattended ahead of the
agent.
"""
from __future__ import annotations

import re
from typing import Any

import numpy as np
import pandas as pd

from config import settings

_CURRENCY_PATTERN = re.compile(r"[$€£¥,%]")
_DATE_NAME_PATTERN = re.compile(r"(date|time|timestamp)", re.IGNORECASE)


# --------------------------------------------------------------------------
# Workflow step 1: ingestion heuristics
# --------------------------------------------------------------------------

def _try_currency_to_float(series: pd.Series) -> pd.Series | None:
    """Returns a float series if stripping currency/percent/comma chars yields
    a fully-numeric column; otherwise returns None (leave column untouched)."""
    if not (pd.api.types.is_object_dtype(series) or pd.api.types.is_string_dtype(series)):
        return None
    stripped = series.astype(str).str.strip()
    # Only attempt if a meaningful fraction of non-null values actually contain
    # currency-ish characters; otherwise this is probably free text.
    non_null = stripped[stripped.str.lower() != "nan"]
    if non_null.empty:
        return None
    has_symbol = non_null.str.contains(_CURRENCY_PATTERN)
    if has_symbol.mean() < 0.5:
        return None
    cleaned = stripped.str.replace(_CURRENCY_PATTERN, "", regex=True).str.strip()
    cleaned = cleaned.replace({"": np.nan, "nan": np.nan, "None": np.nan})
    numeric = pd.to_numeric(cleaned, errors="coerce")
    # Require that we didn't just turn everything into NaN.
    if numeric.notna().sum() == 0:
        return None
    return numeric.astype(float)


def _coerce_datetime_columns(df: pd.DataFrame, log: list[dict[str, str]]) -> None:
    for col in df.columns:
        is_textual = pd.api.types.is_object_dtype(df[col]) or pd.api.types.is_string_dtype(df[col])
        if _DATE_NAME_PATTERN.search(col) and is_textual:
            parsed = pd.to_datetime(df[col], errors="coerce", utc=False)
            # Only commit the conversion if most values actually parsed.
            if parsed.notna().mean() >= 0.5:
                df[col] = parsed
                log.append(
                    {
                        "column": col,
                        "action": "coerce_datetime",
                        "detail": "Column name matched date/time/timestamp; parsed with pd.to_datetime.",
                    }
                )


def _strip_currency_columns(df: pd.DataFrame, log: list[dict[str, str]]) -> None:
    for col in df.columns:
        if not (pd.api.types.is_object_dtype(df[col]) or pd.api.types.is_string_dtype(df[col])):
            continue
        converted = _try_currency_to_float(df[col])
        if converted is not None:
            df[col] = converted
            log.append(
                {
                    "column": col,
                    "action": "strip_currency_and_cast_float",
                    "detail": "Stripped currency symbols/commas/percent signs and cast to float.",
                }
            )


def _drop_zero_variance_columns(df: pd.DataFrame, log: list[dict[str, str]]) -> list[str]:
    dropped: list[str] = []
    for col in df.columns:
        non_null = df[col].dropna()
        if non_null.empty or non_null.nunique() <= 1:
            dropped.append(col)
    if dropped:
        df.drop(columns=dropped, inplace=True)
        for col in dropped:
            log.append(
                {
                    "column": col,
                    "action": "drop_zero_variance",
                    "detail": "Column had zero (or undefined) variance and carries no analytical signal.",
                }
            )
    return dropped


# "id", "customer_id", "order id", "uuid", "guid" in any case, plus CamelCase "CustomerID" /
# "OrderId". The CamelCase branch is case-sensitive so words like "Paid" don't match.
_ID_NAME_PATTERN = re.compile(r"(?i:^id$|[_\s-]id$|^uuid$|guid)|(?<=[a-z])I[dD]$")


def _is_sequential_integer(series: pd.Series) -> bool:
    """True for a row counter: every value unique and together they fill a consecutive range."""
    non_null = series.dropna()
    if non_null.empty or not non_null.is_unique:
        return False
    return int(non_null.max()) - int(non_null.min()) + 1 == len(non_null)


def _flag_high_cardinality_ids(df: pd.DataFrame, log: list[dict[str, str]]) -> set[str]:
    n_rows = max(len(df), 1)
    flagged: set[str] = set()
    for col in df.columns:
        is_text = pd.api.types.is_object_dtype(df[col]) or pd.api.types.is_string_dtype(df[col])
        is_integer = pd.api.types.is_integer_dtype(df[col]) and not pd.api.types.is_bool_dtype(df[col])
        if not (is_text or is_integer):
            continue
        uniqueness_ratio = df[col].nunique(dropna=True) / n_rows
        looks_like_id_name = bool(_ID_NAME_PATTERN.search(str(col)))
        # Highly unique integers are often genuine measures (e.g. revenue in cents), so a
        # numeric column needs an ID-like name or to be a plain row counter.
        if is_text:
            is_id = uniqueness_ratio >= settings.HIGH_CARDINALITY_RATIO
        else:
            is_id = _is_sequential_integer(df[col])
        if is_id or (looks_like_id_name and uniqueness_ratio >= 0.5):
            flagged.add(col)
            log.append(
                {
                    "column": col,
                    "action": "flag_high_cardinality_id",
                    "detail": (
                        f"Uniqueness ratio {uniqueness_ratio:.2f} suggests an identifier "
                        "column (e.g. UUID); excluded from analytical/statistical steps."
                    ),
                }
            )
    return flagged


def _downcast_and_categorize(
    df: pd.DataFrame, excluded: set[str], log: list[dict[str, str]]
) -> None:
    n_rows = max(len(df), 1)
    for col in df.columns:
        if col in excluded:
            continue
        dtype = df[col].dtype
        if pd.api.types.is_float_dtype(dtype) and dtype == np.float64:
            df[col] = pd.to_numeric(df[col], downcast="float")
            log.append({"column": col, "action": "downcast_float64", "detail": "Downcast float64 to a smaller float subtype."})
        elif pd.api.types.is_integer_dtype(dtype) and dtype == np.int64:
            df[col] = pd.to_numeric(df[col], downcast="integer")
            log.append({"column": col, "action": "downcast_int64", "detail": "Downcast int64 to a smaller integer subtype."})
        elif pd.api.types.is_object_dtype(dtype) or pd.api.types.is_string_dtype(dtype):
            uniqueness_ratio = df[col].nunique(dropna=True) / n_rows
            if (
                uniqueness_ratio <= settings.LOW_CARDINALITY_RATIO
                or df[col].nunique(dropna=True) <= settings.LOW_CARDINALITY_MAX_UNIQUE
            ):
                df[col] = df[col].astype("category")
                log.append(
                    {
                        "column": col,
                        "action": "convert_to_category",
                        "detail": f"Low cardinality ({df[col].nunique()} unique values); converted to category dtype.",
                    }
                )


def apply_ingestion_heuristics(
    df: pd.DataFrame,
) -> tuple[pd.DataFrame, list[dict[str, str]], set[str]]:
    """
    Runs every hardcoded heuristic from Workflow step 1, in order:
      1. currency/percent/comma stripping -> float
      2. date/time/timestamp column coercion
      3. zero-variance column removal
      4. high-cardinality ID flagging
      5. downcasting + categorical conversion (skipping flagged ID columns)

    Returns (cleaned_df, ingestion_log, flagged_id_columns).
    """
    df = df.copy()
    log: list[dict[str, str]] = []

    _strip_currency_columns(df, log)
    _coerce_datetime_columns(df, log)
    _drop_zero_variance_columns(df, log)
    flagged_ids = _flag_high_cardinality_ids(df, log)
    _downcast_and_categorize(df, flagged_ids, log)

    return df, log, flagged_ids


def extract_metadata(df: pd.DataFrame, flagged_ids: set[str], n_sample: int = 5) -> dict[str, Any]:
    """Builds the JSON-serializable metadata payload used both for the LLM
    data-dictionary call and for the API response."""
    columns = []
    for col in df.columns:
        series = df[col]
        columns.append(
            {
                "name": col,
                "dtype": str(series.dtype),
                "n_missing": int(series.isna().sum()),
                "n_unique": int(series.nunique(dropna=True)),
                "is_flagged_id": col in flagged_ids,
                "sample_values": series.dropna().head(3).astype(str).tolist(),
            }
        )
    sample_rows = df.head(n_sample).astype(object).where(pd.notnull(df.head(n_sample)), None).to_dict(orient="records")
    return {
        "n_rows": int(len(df)),
        "n_columns": int(len(df.columns)),
        "columns": columns,
        "sample_rows": sample_rows,
    }


# --------------------------------------------------------------------------
# Workflow step 2: automated remediation
# --------------------------------------------------------------------------

def _is_skewed(series: pd.Series) -> bool:
    non_null = series.dropna()
    if len(non_null) < 3:
        return False
    skew = non_null.skew()
    return bool(pd.notna(skew) and abs(skew) > settings.SKEW_THRESHOLD)


def _cap_outliers_iqr(series: pd.Series) -> tuple[pd.Series, float, float]:
    q1, q3 = series.quantile(0.25), series.quantile(0.75)
    iqr = q3 - q1
    lower = q1 - settings.IQR_MULTIPLIER * iqr
    upper = q3 + settings.IQR_MULTIPLIER * iqr
    return series.clip(lower=lower, upper=upper), lower, upper


def remediate_data(
    df: pd.DataFrame, flagged_ids: set[str]
) -> tuple[pd.DataFrame, list[dict[str, str]]]:
    """
    Applies Workflow step 2's deterministic cleaning rules and returns the
    cleaned dataframe plus a modification log. Flagged ID columns are left
    untouched (imputing or capping an identifier would corrupt it).
    """
    df = df.copy()
    log: list[dict[str, str]] = []

    for col in df.columns:
        if col in flagged_ids:
            continue
        series = df[col]

        if pd.api.types.is_numeric_dtype(series):
            n_missing = int(series.isna().sum())
            if n_missing > 0:
                if _is_skewed(series):
                    fill_value = series.median()
                    strategy = "median (skewed distribution)"
                else:
                    fill_value = series.mean()
                    strategy = "mean (approximately normal distribution)"
                df[col] = series.fillna(fill_value)
                log.append(
                    {
                        "column": col,
                        "action": "impute_missing_numeric",
                        "detail": f"Filled {n_missing} missing value(s) using {strategy} = {fill_value:.4g}.",
                    }
                )

            capped, lower, upper = _cap_outliers_iqr(df[col].astype(float))
            n_capped = int((df[col].astype(float) != capped).sum())
            if n_capped > 0:
                df[col] = capped
                log.append(
                    {
                        "column": col,
                        "action": "cap_outliers_iqr",
                        "detail": f"Capped {n_capped} outlier value(s) to IQR bounds [{lower:.4g}, {upper:.4g}].",
                    }
                )

        elif (
            isinstance(series.dtype, pd.CategoricalDtype)
            or pd.api.types.is_object_dtype(series)
            or pd.api.types.is_string_dtype(series)
        ):
            n_missing = int(series.isna().sum())
            if n_missing > 0 and series.dropna().shape[0] > 0:
                mode_value = series.mode(dropna=True)
                if not mode_value.empty:
                    fill_value = mode_value.iloc[0]
                    df[col] = series.fillna(fill_value)
                    log.append(
                        {
                            "column": col,
                            "action": "impute_missing_categorical",
                            "detail": f"Filled {n_missing} missing value(s) with mode = {fill_value!r}.",
                        }
                    )

    return df, log
