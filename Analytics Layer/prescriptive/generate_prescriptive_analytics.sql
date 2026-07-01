-- ============================================================================
-- SQL Script: Generate Prescriptive Analytics Layer & Tactical Interventions
-- Classification: Prescriptive Analytics (LRT Train & Operations Management System)
-- ============================================================================

-- Drop views in correct order
DROP VIEW IF EXISTS "Analytics".prescriptive_active_checklists CASCADE;
DROP VIEW IF EXISTS "Analytics".prescriptive_action_recommendations CASCADE;
DROP VIEW IF EXISTS "Analytics".prescriptive_tactical_interventions CASCADE;
DROP VIEW IF EXISTS "Analytics".prescriptive_compliance_audit CASCADE;
DROP VIEW IF EXISTS "Analytics".prescriptive_latency_summary CASCADE;

-- Drop tables in correct order
DROP TABLE IF EXISTS "Analytics".prescriptive_protocol_deployments CASCADE;
DROP TABLE IF EXISTS "Analytics".prescriptive_station_capacities CASCADE;

-- 1. Create Physical Capacity Constants Table
CREATE TABLE "Analytics".prescriptive_station_capacities (
    station_name text PRIMARY KEY,
    max_safe_platform_capacity integer NOT NULL CHECK (max_safe_platform_capacity > 0)
);

-- Seed physical capacities based on station sizes
INSERT INTO "Analytics".prescriptive_station_capacities (station_name, max_safe_platform_capacity)
VALUES
  ('Recto', 2500),
  ('Legarda', 1800),
  ('Pureza', 1800),
  ('V. Mapa', 1800),
  ('J. Ruiz', 1200),
  ('Betty Go-Belmonte', 1200),
  ('Araneta Center Cubao', 2500),
  ('Anonas', 1500),
  ('Katipunan', 2000),
  ('Santolan', 1800),
  ('Marikina-Pasig', 1800),
  ('Antipolo', 2200),
  ('Gilmore', 1500);

-- 2. Create Protocol Deployment Auditing Table (UAT Metrics Input)
-- References the official APTA schema table directly for validation
CREATE TABLE "Analytics".prescriptive_protocol_deployments (
    deployment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    station_name text NOT NULL,
    flow_type text NOT NULL,
    decision_action text NOT NULL REFERENCES "APTA".apta_protocols(id),
    deployed_by text NOT NULL DEFAULT 'System_Automated',
    status text NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Completed', 'Cancelled')),
    ingestion_timestamp timestamp with time zone NOT NULL DEFAULT now(),
    broadcast_timestamp timestamp with time zone,
    activated_at timestamp with time zone DEFAULT now(),
    completed_at timestamp with time zone
);

CREATE INDEX idx_prescriptive_deploy_station ON "Analytics".prescriptive_protocol_deployments (station_name);

-- ============================================================================
-- VIEWS: EXPOSING DECISION TREE & ACTION CHECKLISTS
-- ============================================================================

-- 3. Create Decision Tree Evaluation View
CREATE OR REPLACE VIEW "Analytics".prescriptive_action_recommendations AS
SELECT 
  fc.prediction_date as date,
  fc.hour_period as time,
  fc.station_name,
  fc.flow_type,
  fc.baseline_mean_forecast as predicted_volume,
  cap.max_safe_platform_capacity as platform_capacity,
  ROUND((fc.adjusted_forecast_volume::numeric / cap.max_safe_platform_capacity) * 100.0, 2) as capacity_utilization,
  GREATEST(0, fc.adjusted_forecast_volume - cap.max_safe_platform_capacity) as passenger_surplus,
  fc.predicted_threat_level as forecasted_threat_level,
  -- Primary Trigger Context Identification
  CASE 
    WHEN fc.weather_score > 0.0 AND fc.weather_score >= fc.academic_surge_score AND fc.weather_score >= fc.civic_mandate_score THEN 'Weather'
    WHEN fc.academic_surge_score > 0.0 AND fc.academic_surge_score >= fc.weather_score AND fc.academic_surge_score >= fc.civic_mandate_score THEN 'Academic'
    WHEN fc.civic_mandate_score > 0.0 AND fc.civic_mandate_score >= fc.weather_score AND fc.civic_mandate_score >= fc.academic_surge_score THEN 'Civic'
    ELSE 'General'
  END as primary_trigger_context,
  -- Heuristic Decision Tree Terminal Nodes mapped to APTA Protocol IDs
  CASE 
    WHEN fc.predicted_threat_level = 'Normal' THEN 'APTA-03' -- Recommended Practice for Station Operations (Standard Operations)
    WHEN fc.predicted_threat_level = 'Warning' AND (fc.adjusted_forecast_volume::numeric / cap.max_safe_platform_capacity) < 0.80 THEN 'APTA-02' -- Security Considerations (Platform Queue Preparation)
    WHEN fc.predicted_threat_level = 'Warning' AND (fc.adjusted_forecast_volume::numeric / cap.max_safe_platform_capacity) >= 0.80 THEN 'APTA-05' -- Escalator Guidelines (Concourse Crowd Holding)
    WHEN fc.predicted_threat_level = 'Critical' AND (fc.adjusted_forecast_volume::numeric / cap.max_safe_platform_capacity) < 0.90 THEN 'APTA-04' -- Emergency Operations (Manual Entrance Metering)
    WHEN fc.predicted_threat_level = 'Critical' AND (fc.adjusted_forecast_volume::numeric / cap.max_safe_platform_capacity) >= 0.90 THEN 'APTA-02' -- Security/Barricades (Pulse Boarding / Human Barricades)
    WHEN fc.predicted_threat_level = 'Emergency' THEN 'APTA-01' -- Emergency Egress (Evacuation & Shutdown)
    ELSE 'APTA-03'
  END::text as decision_action
FROM "Analytics".vw_predictive_metrics fc
JOIN "Analytics".prescriptive_station_capacities cap
  ON cap.station_name = fc.station_name;

-- 4. Create Active Directives View for Mobile/Dashboard Checklist
-- Aliased specifically to match original dashboard naming expectations (task_name, action_details, target_role)
CREATE OR REPLACE VIEW "Analytics".prescriptive_active_checklists AS
WITH current_station_state AS (
  SELECT 
    station_name,
    flow_type,
    predicted_volume,
    platform_capacity,
    capacity_utilization,
    decision_action as active_protocol_id,
    primary_trigger_context as active_context,
    (date + (time || ':00')::time) AT TIME ZONE 'Asia/Manila' as ingestion_timestamp
  FROM "Analytics".prescriptive_action_recommendations
  WHERE date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
    AND time = to_char((CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'), 'HH24') || ':00'
)
SELECT 
  cs.station_name,
  cs.flow_type,
  cs.predicted_volume,
  cs.platform_capacity,
  cs.capacity_utilization,
  p.apta_standard_code as active_action, -- Maps standard code as active action (e.g. 'APTA SS-ISS-RP-004-23')
  cs.active_context,
  -- Map tactic ID sequence to numeric task_order
  (CASE 
    WHEN t.id LIKE '%-T01' THEN 1
    WHEN t.id LIKE '%-T02' THEN 2
    WHEN t.id LIKE '%-T03' THEN 3
    ELSE 4
  END)::integer as task_order,
  t.tactic_name as task_name, -- Maps tactic_name to dashboard's task_name
  -- Dynamically map target_role based on Ground Control Mobile App and Command Center Desktop App users
  (CASE 
    WHEN t.id IN ('APTA-04-T02', 'APTA-06-T02', 'APTA-06-T03') THEN 'Command Center Officer'
    ELSE 'Ground Control Staff'
  END)::text as target_role,
  -- Dynamically map priority
  (CASE 
    WHEN t.id IN ('APTA-01-T01', 'APTA-01-T02', 'APTA-02-T03', 'APTA-04-T03', 'APTA-05-T01', 'APTA-05-T02') THEN 'Critical'
    WHEN t.id IN ('APTA-02-T02', 'APTA-03-T01', 'APTA-04-T02', 'APTA-06-T02', 'APTA-06-T03') THEN 'High'
    ELSE 'Medium'
  END)::text as priority,
  t.tactic_description as action_details, -- Maps tactic_description to action_details
  cs.ingestion_timestamp
FROM current_station_state cs
JOIN "APTA".apta_protocols p ON p.id = cs.active_protocol_id
JOIN "APTA".apta_protocols_tactics t ON t.protocol_id = cs.active_protocol_id
ORDER BY cs.station_name, cs.flow_type, task_order;

-- 5. Re-expose Tactical Guidelines View in Analytics Schema using APTA reference
CREATE OR REPLACE VIEW "Analytics".prescriptive_tactical_interventions AS
SELECT 
  'Normal'::text as threat_level,
  'Volume < Warning (P80)'::text as threshold_indicator,
  p.apta_standard_code || ' - ' || p.official_document_title as prescribed_standard,
  p.scope_relevance_to_surge_management as operational_guideline
FROM "APTA".apta_protocols p
WHERE p.id = 'APTA-03'
UNION ALL
SELECT 
  'Warning'::text as threat_level,
  'Volume >= Warning (P80) and Volume < Critical (P90)'::text as threshold_indicator,
  p.apta_standard_code || ' - ' || p.official_document_title as prescribed_standard,
  p.scope_relevance_to_surge_management as operational_guideline
FROM "APTA".apta_protocols p
WHERE p.id = 'APTA-02'
UNION ALL
SELECT 
  'Critical'::text as threat_level,
  'Volume >= Critical (P90)'::text as threshold_indicator,
  p.apta_standard_code || ' - ' || p.official_document_title as prescribed_standard,
  p.scope_relevance_to_surge_management as operational_guideline
FROM "APTA".apta_protocols p
WHERE p.id = 'APTA-04'
UNION ALL
SELECT 
  'Emergency'::text as threat_level,
  'CFI > 0.85 and Storm Warning Active'::text as threshold_indicator,
  p.apta_standard_code || ' - ' || p.official_document_title as prescribed_standard,
  p.scope_relevance_to_surge_management as operational_guideline
FROM "APTA".apta_protocols p
WHERE p.id = 'APTA-01';

-- ============================================================================
-- UAT AUTO-COMPUTATION VIEWS
-- ============================================================================

-- 6. Compliance Rate (SCR) Auto-Computation View
CREATE OR REPLACE VIEW "Analytics".prescriptive_compliance_audit AS
WITH stats AS (
  SELECT 
    COUNT(*)::numeric as T_p,
    COUNT(CASE WHEN d.decision_action IN (SELECT id FROM "APTA".apta_protocols) THEN 1 END)::numeric as V_p
  FROM "Analytics".prescriptive_protocol_deployments d
)
SELECT 
  T_p::integer as total_prescriptive_generations,
  V_p::integer as valid_protocol_generations,
  CASE 
    WHEN T_p = 0 THEN 100.0
    ELSE ROUND((V_p / T_p) * 100.0, 2)
  END as symbolic_heuristic_compliance_rate_scr
FROM stats;

-- 7. Ingestion-to-Broadcast Latency (Lib) Auto-Computation View
CREATE OR REPLACE VIEW "Analytics".prescriptive_latency_summary AS
SELECT 
  COUNT(*)::integer as total_audited_runs,
  COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (broadcast_timestamp - ingestion_timestamp)))::numeric, 4), 0.0) as average_latency_seconds,
  COALESCE(ROUND(MAX(EXTRACT(EPOCH FROM (broadcast_timestamp - ingestion_timestamp)))::numeric, 4), 0.0) as max_latency_seconds,
  COUNT(CASE WHEN EXTRACT(EPOCH FROM (broadcast_timestamp - ingestion_timestamp)) < 3.0 THEN 1 END)::integer as passed_runs,
  CASE 
    WHEN COUNT(*) = 0 THEN 100.0
    ELSE ROUND((COUNT(CASE WHEN EXTRACT(EPOCH FROM (broadcast_timestamp - ingestion_timestamp)) < 3.0 THEN 1 END)::numeric / COUNT(*)) * 100.0, 2)
  END as latency_compliance_rate_pct
FROM "Analytics".prescriptive_protocol_deployments
WHERE broadcast_timestamp IS NOT NULL AND ingestion_timestamp IS NOT NULL;
