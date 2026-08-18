-- ============================================================================
-- Migration: uat_metrics_append_only_ledger.sql
-- Purpose: Immutable time-series UAT metrics for Predictive & Prescriptive validation
-- ============================================================================

-- 1. Predictive Model UAT Evaluation Ledger
CREATE TABLE IF NOT EXISTS "Analytics".uat_predictive_evaluation_logs (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL DEFAULT gen_random_uuid(),
    evaluation_type TEXT NOT NULL DEFAULT 'model_validation' CHECK (evaluation_type IN ('model_validation', 'training_split', 'uat_trial', 'synthetic_stress_test')),
    model_name TEXT NOT NULL,
    dataset_split_date DATE,
    sample_count INTEGER,
    rmse NUMERIC NOT NULL,
    mean_volume NUMERIC,
    rmse_percentage NUMERIC,
    mape NUMERIC NOT NULL,
    classification_accuracy NUMERIC,
    recall_score NUMERIC,
    f1_score NUMERIC,
    target_rmse_passed BOOLEAN NOT NULL DEFAULT FALSE,
    target_f1_passed BOOLEAN NOT NULL DEFAULT FALSE,
    all_targets_passed BOOLEAN NOT NULL DEFAULT FALSE,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Prescriptive Model UAT Execution Ledger
CREATE TABLE IF NOT EXISTS "Analytics".uat_prescriptive_execution_logs (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL DEFAULT gen_random_uuid(),
    trigger_source TEXT NOT NULL DEFAULT 'uat_evaluator',
    station_name TEXT NOT NULL,
    friction_score NUMERIC,
    recommended_protocol_id TEXT REFERENCES "APTA".apta_protocols(id),
    actual_dispatched_protocol_id TEXT REFERENCES "APTA".apta_protocols(id),
    ingestion_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    broadcast_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    latency_seconds NUMERIC GENERATED ALWAYS AS (EXTRACT(EPOCH FROM (broadcast_timestamp - ingestion_timestamp))) STORED,
    scr_compliant BOOLEAN NOT NULL DEFAULT TRUE,
    latency_sla_passed BOOLEAN GENERATED ALWAYS AS (EXTRACT(EPOCH FROM (broadcast_timestamp - ingestion_timestamp)) < 3.0) STORED,
    tested_by TEXT DEFAULT 'automated_uat_pipeline',
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. UAT Executive Summary View
CREATE OR REPLACE VIEW "Analytics".vw_uat_executive_summary AS
WITH pred_summary AS (
    SELECT 
        COUNT(DISTINCT run_id) as total_predictive_runs,
        MAX(recorded_at) as latest_predictive_eval_at,
        ROUND(AVG(mape), 4) as avg_historical_mape,
        ROUND(AVG(rmse), 4) as avg_historical_rmse,
        ROUND(AVG(classification_accuracy), 2) as avg_historical_accuracy,
        COUNT(CASE WHEN all_targets_passed THEN 1 END) as passed_predictive_runs
    FROM "Analytics".uat_predictive_evaluation_logs
),
presc_summary AS (
    SELECT 
        COUNT(*) as total_prescriptive_executions,
        MAX(recorded_at) as latest_prescriptive_eval_at,
        COUNT(CASE WHEN scr_compliant THEN 1 END) as scr_compliant_executions,
        ROUND(AVG(latency_seconds), 4) as avg_pipeline_latency_seconds,
        COUNT(CASE WHEN latency_sla_passed THEN 1 END) as sla_compliant_executions
    FROM "Analytics".uat_prescriptive_execution_logs
)
SELECT 
    p.total_predictive_runs,
    p.latest_predictive_eval_at,
    p.avg_historical_mape,
    p.avg_historical_rmse,
    p.avg_historical_accuracy,
    p.passed_predictive_runs,
    pr.total_prescriptive_executions,
    pr.latest_prescriptive_eval_at,
    pr.scr_compliant_executions,
    CASE 
        WHEN pr.total_prescriptive_executions = 0 THEN 100.0
        ELSE ROUND((pr.scr_compliant_executions::numeric / pr.total_prescriptive_executions) * 100.0, 2)
    END as overall_scr_compliance_pct,
    pr.avg_pipeline_latency_seconds,
    CASE 
        WHEN pr.total_prescriptive_executions = 0 THEN 100.0
        ELSE ROUND((pr.sla_compliant_executions::numeric / pr.total_prescriptive_executions) * 100.0, 2)
    END as overall_latency_sla_compliance_pct
FROM pred_summary p
CROSS JOIN presc_summary pr;
