import pandas as pd
import numpy as np
import uuid

def generate_prophet_test_data():
    """ Generates high-frequency daily data designed for Prophet and pipeline testing. """
    dates = pd.date_range(start='2021-01-01', end='2023-12-31', freq='D')
    days = np.arange(len(dates))
    
    # 1. Base time-series data
    trend = days * 0.05
    seasonality = 20 * np.sin(2 * np.pi * days / 365.25)
    noise = np.random.normal(0, 5, len(dates))
    active_users = 100 + trend + seasonality + noise
    
    df = pd.DataFrame({
        'Date': dates,  # Triggers _coerce_datetime_columns
        'Daily_Active_Users': active_users
    })
    
    # 2. Trigger Outlier Capping (IQR bounds)
    # Inject massive spikes into 5 random rows to test _cap_outliers_iqr
    outlier_indices = np.random.choice(df.index, 5, replace=False)
    df.loc[outlier_indices, 'Daily_Active_Users'] *= 10
    
    # 3. Trigger High-Cardinality ID Flagging
    # Generates unique UUIDs to test _flag_high_cardinality_ids
    df['Session_UUID'] = [str(uuid.uuid4()) for _ in range(len(df))]
    
    # 4. Trigger Zero-Variance Removal
    # A column with identical values to test _drop_zero_variance_columns
    df['App_Version'] = "v2.1.0"
    
    # 5. Prophet Routing Trigger
    # Drop 5% of rows to break standard frequency inference
    drop_indices = np.random.choice(df.index, size=int(len(df) * 0.05), replace=False)
    df = df.drop(drop_indices).sort_values('Date')
    
    df.to_csv('data/test_prophet_pipeline.csv', index=False)
    print(f"Generated test_prophet_pipeline.csv ({len(df)} rows)")

def generate_arima_test_data():
    """ Generates regular monthly data designed for Auto-ARIMA and pipeline testing. """
    dates = pd.date_range(start='2014-01-01', end='2023-12-31', freq='MS')
    months = np.arange(len(dates))
    
    trend = months * 1.5
    seasonality = 50 * np.sin(2 * np.pi * months / 12)
    noise = np.random.normal(0, 10, len(dates))
    revenue = 500 + trend + seasonality + noise
    
    df = pd.DataFrame({
        'timestamp': dates, # Triggers _coerce_datetime_columns
        'Monthly_Revenue': revenue
    })
    
    # 1. Trigger Currency Stripping
    # Format as strings with '$' and ',' to test _try_currency_to_float
    df['Monthly_Revenue'] = df['Monthly_Revenue'].apply(lambda x: f"${x:,.2f}")
    
    # 2. Trigger Missing Imputation (Normal Distribution -> Mean)
    df['Ad_Spend'] = np.random.normal(1000, 100, len(df))
    nan_indices_normal = np.random.choice(df.index, 10, replace=False)
    df.loc[nan_indices_normal, 'Ad_Spend'] = np.nan
    
    # 3. Trigger Missing Imputation (Skewed Distribution -> Median)
    # Generate an exponentially skewed distribution
    df['Support_Tickets'] = np.random.exponential(scale=50, size=len(df))
    nan_indices_skewed = np.random.choice(df.index, 10, replace=False)
    df.loc[nan_indices_skewed, 'Support_Tickets'] = np.nan
    
    # 4. Trigger Categorical Conversion
    # Low cardinality column to test _downcast_and_categorize
    df['Region'] = np.random.choice(['North America', 'EMEA', 'APAC'], size=len(df))
    
    df.to_csv('data/test_arima_pipeline.csv', index=False)
    print(f"Generated test_arima_pipeline.csv ({len(df)} rows)")

if __name__ == "__main__":
    np.random.seed(42)
    generate_prophet_test_data()
    generate_arima_test_data()