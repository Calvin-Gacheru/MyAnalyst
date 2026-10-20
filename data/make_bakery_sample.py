"""Generates data/bakery_transactions.csv: 12 months of bank-statement-style
transactions for a fictional Shenzhen bakery whose cash is slowly running
down. Used as the main cash-flow demo. Deterministic (fixed seed).

    python data/make_bakery_sample.py
"""
from pathlib import Path

import numpy as np
import pandas as pd

rng = np.random.default_rng(20261019)
start, end = pd.Timestamp("2025-11-01"), pd.Timestamp("2026-10-31")
days = pd.date_range(start, end, freq="D")
rows = []


def add(date, description, category, counterparty, amount):
    rows.append({"date": date.date().isoformat(), "description": description, "category": category,
                 "counterparty": counterparty, "amount": round(float(amount), 2)})


for i, d in enumerate(days):
    month_idx = (d.year - 2025) * 12 + d.month - 11  # 0..11
    weekend = d.dayofweek >= 5
    # Sales soften from mid-year as a competitor opens nearby.
    trend = 1.0 if month_idx < 6 else 1.0 - 0.035 * (month_idx - 5)
    festive = 1.35 if d.month == 2 and d.day <= 20 else 1.0  # Spring Festival
    base = (11800 if weekend else 8700) * trend * festive
    add(d, "Daily sales settlement - WeChat Pay", "Sales", "Tenpay", base * 0.62 * rng.normal(1, 0.08))
    add(d, "Daily sales settlement - Alipay", "Sales", "Alipay", base * 0.30 * rng.normal(1, 0.1))
    if not weekend or rng.random() < 0.5:
        add(d, "Daily sales - cash deposit", "Sales", "Cash", base * 0.08 * rng.normal(1, 0.15))

    if d.dayofweek == 4:  # Fridays: wholesale customers pay invoices
        for name in ("Futian Coffee Co.", "Nanshan Office Catering"):
            if rng.random() < 0.85:
                add(d, f"Invoice payment - {name}", "Wholesale", name, rng.normal(6200, 900) * trend)
    if d.dayofweek == 1:  # Tuesdays: ingredient suppliers
        add(d, "Flour, butter and dairy", "Ingredients", "Pearl River Foods Ltd.", -rng.normal(24500, 2500) * (1 + 0.012 * month_idx))
        add(d, "Packaging", "Packaging", "Shenzhen Pack Supply", -rng.normal(3100, 400))

    if d.day == 1:
        add(d, "Shop rent - Futian", "Rent", "Futian Property Mgmt", -38000)
        add(d, "Equipment loan repayment", "Loan repayment", "China Merchants Bank", -8600)
    if d.day == 10:
        add(d, "Payroll - 14 staff", "Payroll", "Payroll", -(118000 if month_idx < 7 else 126000))
        add(d, "Social insurance", "Payroll", "Shenzhen Social Insurance", -21500)
    if d.day == 15:
        add(d, "Electricity and gas", "Utilities", "Shenzhen Power", -rng.normal(9800, 900) * (1.25 if d.month in (7, 8) else 1))
    if d.day == 20 and month_idx % 2 == 0:
        add(d, "Meituan and Dianping ads", "Marketing", "Meituan", -rng.normal(6500, 800))
    if d.day == 18 and d.month in (1, 4, 7, 10):
        add(d, "VAT and surcharges", "Tax", "Shenzhen Tax Bureau", -rng.normal(27000, 3000))

# A few customer refunds whose notes contain personal details, as real
# statements do. These exercise the privacy masking before any LLM call.
for date, who, phone in [("2026-01-14", "Li Na", "13812345678"), ("2026-05-03", "Zhang Wei", "13987654321"),
                         ("2026-08-22", "Chen Jing", "15011112222")]:
    add(pd.Timestamp(date), f"Refund to {who} tel {phone}", "Refunds", who, -rng.normal(380, 60))
add(pd.Timestamp("2026-03-08"), "Oven repair", "Equipment", "Bao'an Kitchen Service", -14600)

df = pd.DataFrame(rows).sort_values("date", kind="stable").reset_index(drop=True)
opening = 360000.0
df["balance"] = (opening + df["amount"].cumsum()).round(2)

out = Path(__file__).resolve().parent / "bakery_transactions.csv"
df.to_csv(out, index=False)
monthly = df.assign(m=df["date"].str[:7]).groupby("m")["amount"].sum().round(0)
print(f"{len(df)} rows -> {out}\nclosing balance {df['balance'].iloc[-1]:,.0f}\nmonthly net:\n{monthly.to_string()}")
