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

def _run_prophet_forecast(ts: pd.DataFrame, datetime_col: str, value_col: str, periods: int) -> go.Figure:
    # Prophet requires strict column naming conventions: 'ds' for datetimes, 'y' for values
    prophet_df = ts[[datetime_col, value_col]].rename(columns={datetime_col: "ds", value_col: "y"})
    
    # Prophet natively handles structural trend shifts and missing values
    model = Prophet(yearly_seasonality=True, daily_seasonality=False)
    model.fit(prophet_df)
    
    freq = pd.infer_freq(prophet_df["ds"]) or "D"
    future = model.make_future_dataframe(periods=periods, freq=freq)
    forecast = model.predict(future)
    
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=prophet_df["ds"], y=prophet_df["y"], mode="lines", name="Observed"))
    fig.add_trace(go.Scatter(
        x=forecast["ds"], y=forecast["yhat"], mode="lines", name="Forecast", line={"dash": "dash"}
    ))
    
    # Add confidence intervals
    fig.add_trace(go.Scatter(
        x=forecast["ds"], y=forecast["yhat_upper"], mode="lines", line={"width": 0}, showlegend=False
    ))
    fig.add_trace(go.Scatter(
        x=forecast["ds"], y=forecast["yhat_lower"], mode="lines", fill="tonexty", 
        fillcolor="rgba(0,176,246,0.2)", line={"width": 0}, name="Confidence Interval"
    ))
    
    fig.update_layout(title=f"{value_col} Forecast (Prophet Model)")
    return fig

def _run_arima_forecast(ts: pd.DataFrame, datetime_col: str, value_col: str, periods: int) -> go.Figure:
    y = ts.set_index(datetime_col)[value_col]
    
    # Auto-ARIMA performs an AIC grid search to find optimal p, d, q parameters.
    # m=12 forces the engine to search for yearly SARIMA configurations for monthly data.
    model = pm.auto_arima(
        y, seasonal=True, m=12, stepwise=True, suppress_warnings=True, error_action="ignore"
    )
    
    forecast, conf_int = model.predict(n_periods=periods, return_conf_int=True)
    
    freq = pd.infer_freq(y.index) or "M"
    future_dates = pd.date_range(start=y.index[-1], periods=periods + 1, freq=freq)[1:]
    
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=y.index, y=y.values, mode="lines", name="Observed"))
    fig.add_trace(go.Scatter(
        x=future_dates, y=forecast, mode="lines", name="Forecast", line={"dash": "dash"}
    ))
    
    # Add confidence intervals
    fig.add_trace(go.Scatter(
        x=future_dates, y=conf_int[:, 1], mode="lines", line={"width": 0}, showlegend=False
    ))
    fig.add_trace(go.Scatter(
        x=future_dates, y=conf_int[:, 0], mode="lines", fill="tonexty", 
        fillcolor="rgba(0,176,246,0.2)", line={"width": 0}, name="Confidence Interval"
    ))
    
    # Expose the optimal hyperparameters found by the grid search in the title
    fig.update_layout(title=f"{value_col} Forecast (Auto-ARIMA: {model.order})")
    return fig

def generate_autonomous_forecast(df: pd.DataFrame, datetime_col: str, value_col: str, periods: int = 12) -> go.Figure:
    """ Evaluates time-series data and routes to the optimal model based on frequency. """
    ts = df[[datetime_col, value_col]].dropna().sort_values(datetime_col).copy()
    ts[datetime_col] = pd.to_datetime(ts[datetime_col])
    
    freq = pd.infer_freq(ts[datetime_col])
    
    # Prophet handles irregular (None) and high-frequency data much better than ARIMA
    is_high_freq = freq and any(freq.startswith(prefix) for prefix in ("D", "B", "H", "T", "S"))
    if freq is None or is_high_freq:
        return _run_prophet_forecast(ts, datetime_col, value_col, periods)
    
    # Auto-ARIMA is optimal for structured monthly/quarterly patterns
    return _run_arima_forecast(ts, datetime_col, value_col, periods)