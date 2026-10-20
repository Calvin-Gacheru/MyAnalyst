# type: ignore
"""
Automated Predictive Modeling Engine.

Ingests tabular data and a user-selected target column, automatically determines
whether to run Classification or Regression, fits a robust Gradient Boosting model, 
and extracts evaluation metrics and key business drivers (Feature Importance).
"""
from __future__ import annotations

import json
from typing import Any

import numpy as np
import pandas as pd
import plotly.express as px
from sklearn.compose import make_column_selector, make_column_transformer
from sklearn.ensemble import HistGradientBoostingClassifier, HistGradientBoostingRegressor
from sklearn.inspection import permutation_importance
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, mean_absolute_error, r2_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder, OrdinalEncoder


# A numeric target is only treated as class labels when it looks like a code:
# few distinct whole numbers in a small range (0/1 flags, 1-5 ratings, 0-9
# categories). A low unique count alone isn't enough, since a menu of prices
# like 19, 25, 33 also has few distinct values but is a quantity.
MAX_CLASS_CODES = 10
MAX_CLASS_CODE_VALUE = 10


def _is_classification_target(y: pd.Series) -> bool:
    if pd.api.types.is_bool_dtype(y) or not pd.api.types.is_numeric_dtype(y):
        return True

    values = y.dropna()
    if values.nunique() == 2:
        return True  # any binary flag, whatever its encoding

    is_whole = bool((values % 1 == 0).all())
    return (
        is_whole
        and values.nunique() <= MAX_CLASS_CODES
        and values.min() >= 0
        and values.max() <= MAX_CLASS_CODE_VALUE
    )


def run_predictive_model(
    df: pd.DataFrame, 
    target_column: str, 
    flagged_ids: set[str] | None = None
) -> dict[str, Any]:
    """
    Fits an AutoML pipeline for the given target and returns metrics, 
    top drivers, and serialized Plotly charts for the UI.
    """
    if target_column not in df.columns:
        raise ValueError(f"Target column '{target_column}' not found in the dataset.")

    # 1. Prepare Data
    df_clean = df.dropna(subset=[target_column]).copy()
    if len(df_clean) < 50:
        raise ValueError("Insufficient data: Need at least 50 valid rows to train a predictive model.")

    # Cap rows to respect sandbox constraints and ensure execution under 10 seconds
    if len(df_clean) > 50000:
        df_clean = df_clean.sample(50000, random_state=42)

    flagged = flagged_ids or set()
    features = [c for c in df_clean.columns if c != target_column and c not in flagged]
    
    if not features:
        raise ValueError("No valid feature columns remain to train the model.")

    if pd.api.types.is_datetime64_any_dtype(df_clean[target_column]):
        raise ValueError(f"Target column '{target_column}' is a date; choose a numeric or categorical outcome.")

    X = df_clean[features].copy()
    y = df_clean[target_column].copy()

    # Raw timestamps are meaningless to the model (and would otherwise fall
    # through the numeric passthrough), so expand them into calendar parts.
    datetime_features = [c for c in features if pd.api.types.is_datetime64_any_dtype(X[c])]
    for col in datetime_features:
        X[f"{col}_year"] = X[col].dt.year
        X[f"{col}_month"] = X[col].dt.month
        X[f"{col}_dayofweek"] = X[col].dt.dayofweek
    X = X.drop(columns=datetime_features)

    # 2. Detect Problem Type
    is_classification = _is_classification_target(y)

    # 3. Encode Features
    # HistGradientBoosting natively handles NaNs, but requires categorical strings to be ordinal-encoded.
    categorical_selector = make_column_selector(dtype_include=['object', 'category', 'bool'])
    numeric_selector = make_column_selector(dtype_exclude=['object', 'category', 'bool'])
    
    preprocessor = make_column_transformer(
        (OrdinalEncoder(handle_unknown='use_encoded_value', unknown_value=-1), categorical_selector),
        ('passthrough', numeric_selector)
    )

    X_processed = preprocessor.fit_transform(X)
    # Recover column names after transformation
    cat_cols = categorical_selector(X)
    num_cols = numeric_selector(X)
    feature_names = cat_cols + num_cols

    X_train, X_test, y_train, y_test = train_test_split(X_processed, y, test_size=0.2, random_state=42)

    results: dict[str, Any] = {}

    """
    HistGradientBoosting is utilized because it natively handles missing values and runs significantly faster on
    tabular data than standard Random Forest."""

    # 4. Fit Model & Evaluate
    if is_classification:
        # Fit on the full target so a class that only lands in the test split
        # doesn't raise on transform.
        le = LabelEncoder().fit(y)
        y_train_enc = le.transform(y_train)
        y_test_enc = le.transform(y_test)

        model = HistGradientBoostingClassifier(random_state=42, max_iter=100)
        model.fit(X_train, y_train_enc)
        preds = model.predict(X_test)

        results["problem_type"] = "Classification"
        results["metrics"] = {
            "Accuracy": f"{accuracy_score(y_test_enc, preds) * 100:.1f}%",
            "F1-Score": f"{f1_score(y_test_enc, preds, average='weighted'):.3f}"
        }

        # Confusion Matrix
        # Pin the labels so the matrix always matches le.classes_, even when a
        # class is absent from both the test split and the predictions.
        cm = confusion_matrix(y_test_enc, preds, labels=np.arange(len(le.classes_)))
        fig_perf = px.imshow(
            cm, text_auto=True, 
            x=le.classes_.astype(str), y=le.classes_.astype(str),
            labels={"x": "Predicted Outcome", "y": "Actual Outcome"}, 
            title="Model Accuracy (Confusion Matrix)"
        )
        test_target = y_test_enc

    else:
        model = HistGradientBoostingRegressor(random_state=42, max_iter=100)
        model.fit(X_train, y_train)
        preds = model.predict(X_test)

        results["problem_type"] = "Regression"
        results["metrics"] = {
            "R-Squared (R2)": f"{r2_score(y_test, preds):.3f}",
            "Mean Absolute Error": f"{mean_absolute_error(y_test, preds):.2f}"
        }

        # Actual vs Predicted Scatter
        fig_perf = px.scatter(
            x=y_test, y=preds, 
            labels={"x": "Actual Value", "y": "Predicted Value"},
            title="Prediction Accuracy (Actual vs. Predicted)", 
            opacity=0.6
        )
        fig_perf.add_shape(
            type="line", x0=y_test.min(), y0=y_test.min(), x1=y_test.max(), y1=y_test.max(),
            line=dict(color="Red", dash="dash")
        )
        test_target = y_test

    # 5. Extract Feature Importance (Drivers)
    # HistGradientBoosting does not expose native feature_importances_, so we use permutation importance.
    perm_importance = permutation_importance(model, X_test, test_target, n_repeats=5, random_state=42)
    sorted_idx = perm_importance.importances_mean.argsort()
    
    # Take top 10 features maximum
    top_indices = sorted_idx[-10:]
    top_features = np.array(feature_names)[top_indices]
    top_importances = perm_importance.importances_mean[top_indices]

    fig_imp = px.bar(
        x=top_importances, y=top_features, orientation='h',
        title=f"Key Drivers of {target_column}",
        labels={"x": "Influence Score", "y": "Feature Lever"}
    )
    fig_imp.update_layout(yaxis={'categoryorder': 'total ascending'})

    # Isolate top 3 for the LLM to write the summary
    top_3_drivers = {
        feat: round(imp, 3) 
        for feat, imp in zip(reversed(top_features[-3:]), reversed(top_importances[-3:]))
    }

    results["top_drivers"] = top_3_drivers
    results["performance_plot"] = fig_perf.to_json()
    results["importance_plot"] = fig_imp.to_json()

    return results