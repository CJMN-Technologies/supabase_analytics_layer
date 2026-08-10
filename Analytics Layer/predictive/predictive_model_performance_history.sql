-- ============================================================================
-- Immutable Historical Metric Logging for Model Validation & Auditability
-- Table: Analytics.predictive_model_performance_history
-- ============================================================================

CREATE TABLE IF NOT EXISTS "Analytics".predictive_model_performance_history (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_name TEXT NOT NULL,
    mape NUMERIC NOT NULL,
    rmse NUMERIC NOT NULL,
    classification_accuracy NUMERIC NOT NULL,
    recall_score NUMERIC NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Permissions
GRANT SELECT ON "Analytics".predictive_model_performance_history TO authenticated;
GRANT ALL ON "Analytics".predictive_model_performance_history TO service_role, postgres;
