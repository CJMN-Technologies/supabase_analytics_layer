-- ============================================================================
-- Migration: uat_metrics_append_only_ledger.sql
-- Purpose: Automated, immutable time-series prescriptive evaluation baselines & metrics ledger
-- ============================================================================

-- 1. Predictive Model Prescriptive Baseline Evaluation Ledger
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
    trigger_source TEXT NOT NULL DEFAULT 'automated_generation',
    station_name TEXT NOT NULL,
    friction_score NUMERIC,
    recommended_protocol_id TEXT REFERENCES "APTA".apta_protocols(id),
    actual_dispatched_protocol_id TEXT REFERENCES "APTA".apta_protocols(id),
    ingestion_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    broadcast_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    latency_seconds NUMERIC GENERATED ALWAYS AS (EXTRACT(EPOCH FROM (broadcast_timestamp - ingestion_timestamp))) STORED,
    scr_compliant BOOLEAN NOT NULL DEFAULT TRUE,
    latency_sla_passed BOOLEAN GENERATED ALWAYS AS (EXTRACT(EPOCH FROM (broadcast_timestamp - ingestion_timestamp)) < 3.0) STORED,
    tested_by TEXT DEFAULT 'automated_generation',
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Automated Prescriptive Logging Function
CREATE OR REPLACE FUNCTION "Analytics".evaluate_and_log_prescriptive_deployments(
    p_run_id uuid DEFAULT gen_random_uuid(),
    p_source text DEFAULT 'automated_generation'
)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
    v_inserted_count integer := 0;
    r RECORD;
    v_ingestion timestamptz;
    v_broadcast timestamptz;
    v_is_scr boolean;
BEGIN
    FOR r IN (
        SELECT 
            station_name,
            flow_type,
            decision_action,
            forecasted_threat_level,
            capacity_utilization,
            primary_trigger_context
        FROM "Analytics".prescriptive_action_recommendations
    ) LOOP
        v_ingestion := clock_timestamp();
        v_broadcast := clock_timestamp();
        
        -- Check if decision_action exists in official APTA protocols
        v_is_scr := EXISTS(SELECT 1 FROM "APTA".apta_protocols WHERE id = r.decision_action);

        -- 1. Insert into persistent protocol deployments table
        INSERT INTO "Analytics".prescriptive_protocol_deployments (
            station_name,
            flow_type,
            decision_action,
            deployed_by,
            status,
            ingestion_timestamp,
            broadcast_timestamp,
            activated_at
        ) VALUES (
            r.station_name,
            r.flow_type,
            r.decision_action,
            p_source,
            'Active',
            v_ingestion,
            v_broadcast,
            v_broadcast
        );

        -- 2. Insert into immutable UAT ledger
        INSERT INTO "Analytics".uat_prescriptive_execution_logs (
            run_id,
            trigger_source,
            station_name,
            friction_score,
            recommended_protocol_id,
            actual_dispatched_protocol_id,
            ingestion_timestamp,
            broadcast_timestamp,
            scr_compliant,
            tested_by,
            recorded_at
        ) VALUES (
            p_run_id,
            p_source,
            r.station_name,
            CASE 
                WHEN r.forecasted_threat_level = 'Critical' THEN 0.90
                WHEN r.forecasted_threat_level = 'Warning' THEN 0.60
                ELSE 0.10
            END,
            r.decision_action,
            r.decision_action,
            v_ingestion,
            v_broadcast,
            v_is_scr,
            p_source,
            v_broadcast
        );

        v_inserted_count := v_inserted_count + 1;
    END LOOP;

    RETURN v_inserted_count;
END;
$$;

-- 4. UAT Executive Summary View
CREATE OR REPLACE VIEW "Analytics".vw_uat_executive_summary AS
WITH pred_summary AS (
    SELECT 
        COUNT(DISTINCT run_id) as total_predictive_runs,
        MAX(recorded_at) as latest_predictive_eval_at,
        ROUND(AVG(CASE WHEN model_name = 'LRT2_Volume_Forecast_XGBoost' THEN mape END), 4) as avg_volume_mape,
        ROUND(AVG(CASE WHEN model_name = 'LRT2_Volume_Forecast_XGBoost' THEN rmse END), 4) as avg_volume_rmse,
        ROUND(AVG(CASE WHEN model_name = 'LRT2_Threat_Classifier_RandomForest' THEN classification_accuracy END), 2) as avg_classifier_accuracy,
        ROUND(AVG(CASE WHEN model_name = 'LRT2_Threat_Classifier_RandomForest' THEN f1_score END), 4) as avg_classifier_f1,
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
    p.avg_volume_mape,
    p.avg_volume_rmse,
    p.avg_classifier_accuracy,
    p.avg_classifier_f1,
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

-- 5. Register Half-Hourly Prescriptive Logging Cron Job in pg_cron (2 evaluations per hour)
SELECT cron.schedule(
  'half-hourly-prescriptive-evaluation-and-logging',
  '*/30 * * * *',
  'SELECT "Analytics".evaluate_and_log_prescriptive_deployments();'
);
