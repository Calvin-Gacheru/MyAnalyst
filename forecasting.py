# type: ignore
"""
Autonomous time-series forecasting.

Analyzes dataset characteristics (frequency, regularity) to route to the
optimal statistical model (Prophet for high-frequency/irregular, Auto-ARIMA
for standard structured periods) and generates Plotly JSON outputs.
"""
import pandas as pd
import pmdarima as pm
import plotly.graph_objects as go
from prophet import Prophet
from threadpoolctl import threadpool_limits

MIN_HISTORY = 8  # periods; fewer than this and any "forecast" is a guess

# Pandas offset alias -> (human label, ARIMA seasonal period or None, default horizon)
_PERIODS = {"D": ("day", None, 30), "W": ("week", None, 12), "MS": ("month", 12, 12), "QS": ("quarter", 4, 8)}


def _bucket_series(
    df: pd.DataFrame, datetime_col: str, value_col: str, stamp_agg: str, period_agg: str,
) -> tuple[pd.Series, str]:
    """Collapses rows into one value per regular period, so the model forecasts e.g. daily
    revenue rather than individual sales. `stamp_agg` combines rows sharing a timestamp
    (transactions, regions); `period_agg` combines timestamps within a period."""
    ts = df[[datetime_col, value_col]].dropna().copy()
    ts[datetime_col] = pd.to_datetime(ts[datetime_col])
    per_stamp = ts.groupby(datetime_col)[value_col].agg(stamp_agg).sort_index()

    native = pd.infer_freq(per_stamp.index) if len(per_stamp) >= 3 else None
    native_base = (native or "").split("-")[0]
    if native_base in ("D", "B"):
        alias = "D"
    elif native_base == "W":
        alias = "W"
    elif native_base in ("MS", "M", "ME"):
        alias = "MS"
    elif native_base in ("QS", "Q", "QE"):
        alias = "QS"
    else:
        # Irregular, gappy or intra-day stamps: bucket by the typical gap between observations.
        gap_days = per_stamp.index.to_series().diff().median() / pd.Timedelta(days=1) if len(per_stamp) > 1 else 1
        alias = "D" if gap_days <= 1.5 else "W" if gap_days <= 8 else "MS" if gap_days <= 35 else "QS"

    resampled = per_stamp.resample(alias)
    # A period with no rows is genuinely zero for totals, but unknown for averages.
    series = resampled.sum() if period_agg == "sum" else resampled.mean().interpolate(limit_direction="both")
    return series.astype(float), alias


def _run_prophet_forecast(y: pd.Series, alias: str, periods: int) -> pd.DataFrame:
    span_days = (y.index.max() - y.index.min()).days
    model = Prophet(
        yearly_seasonality=span_days >= 730,
        weekly_seasonality=alias == "D" and span_days >= 21,
        daily_seasonality=False,
    )
    model.fit(pd.DataFrame({"ds": y.index, "y": y.values}))
    future = model.make_future_dataframe(periods=periods, freq=alias, include_history=False)
    forecast = model.predict(future)
    return pd.DataFrame(
        {"yhat": forecast["yhat"].values, "lower": forecast["yhat_lower"].values, "upper": forecast["yhat_upper"].values},
        index=forecast["ds"],
    )


def _seasonal_strength(y: pd.Series, m: int) -> float:
    """Share of detrended variance explained by the position in the cycle (0 = none, 1 = all)."""
    detrended = y - y.rolling(m, center=True, min_periods=m // 2).mean()
    position = pd.Series(range(len(y)), index=y.index) % m
    remainder = detrended - detrended.groupby(position).transform("mean")
    return float(1 - remainder.var() / detrended.var()) if detrended.var() else 0.0


def _run_arima_forecast(y: pd.Series, alias: str, periods: int) -> pd.DataFrame:
    # Seasonal SARIMA needs at least two full cycles of history to estimate the seasonal terms.
    m = _PERIODS[alias][1]
    seasonal = bool(m) and len(y) >= 2 * m
    # pmdarima's seasonal-differencing tests (OCSB / CH) miss clear yearly patterns on short
    # business series, and the D=0 search that follows is ~3x slower and fits worse. Strong
    # seasonality (>= 0.64, Hyndman's rule of thumb) fixes D=1; otherwise let it decide.
    D = 1 if seasonal and _seasonal_strength(y, m) >= 0.64 else None
    # The search is bounded because each seasonal SARIMAX fit costs seconds: pmdarima's
    # defaults (p/q up to 5, P/Q up to 2) took minutes and blocked the upload request.
    # BLAS is pinned to one thread because these tiny matrices run slower multithreaded.
    with threadpool_limits(limits=1, user_api="blas"):
        model = pm.auto_arima(
            y.values, seasonal=seasonal, m=m if seasonal else 1, D=D, stepwise=True, suppress_warnings=True,
            error_action="ignore", start_p=0, start_q=0, max_p=2, max_q=2, start_P=0, start_Q=0,
            max_P=1, max_Q=1, maxiter=30,
        )
    forecast, conf_int = model.predict(n_periods=periods, return_conf_int=True)
    future_dates = pd.date_range(start=y.index[-1], periods=periods + 1, freq=alias)[1:]
    return pd.DataFrame({"yhat": forecast, "lower": conf_int[:, 0], "upper": conf_int[:, 1]}, index=future_dates)


def generate_autonomous_forecast(
    df: pd.DataFrame, datetime_col: str, value_col: str,
    stamp_agg: str = "sum", period_agg: str = "sum", periods: int | None = None,
) -> tuple[go.Figure, str] | None:
    """Buckets the metric into regular periods, then routes to Prophet (daily / weekly) or
    Auto-ARIMA (monthly / quarterly). Returns (figure, one-line rationale), or None when
    there is too little history to forecast honestly."""
    y, alias = _bucket_series(df, datetime_col, value_col, stamp_agg, period_agg)
    if len(y) < MIN_HISTORY:
        return None
    label, _, default_horizon = _PERIODS[alias]
    periods = min(periods or default_horizon, max(3, len(y) // 3))  # don't project further than the data supports

    if alias in ("D", "W"):
        forecast, method = _run_prophet_forecast(y, alias, periods), "Prophet"
    else:
        forecast, method = _run_arima_forecast(y, alias, periods), "Auto-ARIMA"
    if (y >= 0).all():
        # Revenue, units, users... can't go negative, whatever the interval says.
        forecast = forecast.clip(lower=0)

    measure = f"{'Total' if period_agg == 'sum' else 'Average'} {value_col} per {label}"
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=y.index, y=y.values, mode="lines", name="Observed"))
    # Start the forecast line at the last observation so the two lines join up.
    fig.add_trace(go.Scatter(
        x=[y.index[-1], *forecast.index], y=[y.iloc[-1], *forecast["yhat"]],
        mode="lines", name="Forecast", line={"dash": "dash"},
    ))
    fig.add_trace(go.Scatter(x=forecast.index, y=forecast["upper"], mode="lines", line={"width": 0}, showlegend=False))
    fig.add_trace(go.Scatter(
        x=forecast.index, y=forecast["lower"], mode="lines", fill="tonexty",
        fillcolor="rgba(0,176,246,0.2)", line={"width": 0}, name="Confidence interval",
    ))
    fig.update_layout(title=f"{measure}: next {periods} {label}s ({method})", yaxis_title=measure)
    rationale = f"Projects {measure.lower()} {periods} {label}s ahead from {len(y)} {label}s of history."
    return fig, rationale
