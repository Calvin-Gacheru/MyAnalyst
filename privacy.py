# type: ignore
"""
Personal-data protection for everything sent to the LLM provider.

The analysis itself (pandas in the sandbox) always runs on the real data.
Only text that leaves the server for DeepSeek passes through a
`PrivacyFilter`:

  * values from name-like columns (customer, counterparty, contact, ...)
    are replaced with stable placeholders such as [P3] and swapped back in
    the answer the user sees, so the LLM never sees a real name;
  * phone numbers, emails, Chinese ID numbers and bank-card numbers are
    removed outright ([phone], [email], [id], [card]); they are never needed
    to reason about a business's finances.
"""
from __future__ import annotations

import json
import re
from typing import Any

import pandas as pd

# Columns that hold people (or the businesses they trade with). Deliberately
# not every "*name" column: product_name / coffee_name must stay readable or
# the LLM can't say which product sells best.
_NAME_COLUMNS = re.compile(
    r"(^(full_?|first_?|last_?|sur)?name$|customer|client|counterpart|payee|payer|contact|employee|staff|"
    r"person|姓名|客户|联系人|收款人|付款人|员工|对方)", re.I)

_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("email", re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")),
    ("id", re.compile(r"(?<!\d)\d{17}[\dXx](?!\d)")),          # PRC resident ID
    ("card", re.compile(r"(?<![\d.])\d{16,19}(?![\d.])")),     # bank card
    ("phone", re.compile(r"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)")),  # CN mobile
    ("phone", re.compile(r"\+\d{1,3}[- ]?\d{3,4}[- ]?\d{3,4}[- ]?\d{3,4}")),  # intl
]

_MAX_NAMES = 5000


class PrivacyFilter:
    def __init__(self, df: pd.DataFrame | None = None, name_columns: list[str] | None = None) -> None:
        self.name_columns: list[str] = []
        self._forward: dict[str, str] = {}
        self._hits: dict[str, int] = {}
        if df is not None:
            cols = name_columns if name_columns is not None else [
                c for c in df.columns
                if _NAME_COLUMNS.search(str(c))
                and not pd.api.types.is_numeric_dtype(df[c])
                and not pd.api.types.is_datetime64_any_dtype(df[c])
            ]
            self.name_columns = [c for c in cols if c in df.columns]
            values: list[str] = []
            for c in self.name_columns:
                values.extend(str(v) for v in df[c].dropna().unique()[:_MAX_NAMES])
            # Longest first so "Li Na Wang" is replaced before "Li Na".
            for i, v in enumerate(sorted({v.strip() for v in values if len(v.strip()) >= 2}, key=len, reverse=True), 1):
                self._forward[v] = f"[P{i}]"
            self._name_re = (re.compile("|".join(re.escape(v) for v in self._forward))
                             if self._forward else None)
            # What sensitive data the file contains, so the app can tell the
            # owner what is being protected (whether or not it gets sent).
            self._found: dict[str, int] = {}
            text_cols = [c for c in df.columns
                         if df[c].dtype == object or isinstance(df[c].dtype, pd.CategoricalDtype)]
            if text_cols:
                cells = df[text_cols].head(20000).astype(str).to_numpy().ravel()
                for kind, pat in _PATTERNS:
                    n = sum(1 for cell in cells if pat.search(cell))
                    if n:
                        self._found[kind] = self._found.get(kind, 0) + n
        else:
            self._name_re = None
            self._found = {}
        self._reverse = {v: k for k, v in self._forward.items()}

    # ------------------------------------------------------------------ text
    def mask(self, text: str) -> str:
        if not text:
            return text
        for kind, pat in _PATTERNS:
            text, n = pat.subn(f"[{kind}]", text)
            if n:
                self._hits[kind] = self._hits.get(kind, 0) + n
        if self._name_re is not None:
            text, n = self._name_re.subn(lambda m: self._forward[m.group(0)], text)
            if n:
                self._hits["name"] = self._hits.get("name", 0) + n
        return text

    def unmask(self, text: str) -> str:
        """Restores name placeholders in LLM output for the user's eyes."""
        if not text or not self._reverse:
            return text
        return re.sub(r"\[P\d+\]", lambda m: self._reverse.get(m.group(0), m.group(0)), text)

    def unmask_obj(self, obj: Any) -> Any:
        if isinstance(obj, str):
            return self.unmask(obj)
        if isinstance(obj, dict):
            return {k: self.unmask_obj(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [self.unmask_obj(v) for v in obj]
        return obj

    def mask_obj(self, obj: Any) -> Any:
        """Masks every string in a JSON-like structure (dict keys included)."""
        if isinstance(obj, str):
            return self.mask(obj)
        if isinstance(obj, dict):
            return {self.mask(str(k)): self.mask_obj(v) for k, v in obj.items()}
        if isinstance(obj, (list, tuple)):
            return [self.mask_obj(v) for v in obj]
        return obj

    def mask_json(self, obj: Any) -> Any:
        """Round-trips through JSON first so numpy/pandas values become plain."""
        return self.mask_obj(json.loads(json.dumps(obj, default=str)))

    # --------------------------------------------------------------- report
    def report(self) -> dict[str, Any]:
        return {
            "name_columns": self.name_columns,
            "names_protected": len(self._forward),
            "found_in_data": dict(sorted(self._found.items())),  # cells containing each kind
            "masked": dict(sorted(self._hits.items())),          # replacements made in LLM-bound text
        }
