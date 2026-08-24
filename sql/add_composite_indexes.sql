-- =============================================================================
-- LRT-2 Decision Support System — Database Composite Index Migration
-- Target Engine: PostgreSQL 15+ / Supabase
-- Purpose: Accelerate multi-horizon time-series queries, urban trigger feeds,
--          and real-time prescriptive protocol synchronization.
-- =============================================================================

-- 1. External Events & Weather Ingestion
CREATE INDEX IF NOT EXISTS idx_events_consolidated_date_station 
  ON external.events_consolidated (event_date, station);

CREATE INDEX IF NOT EXISTS idx_academic_lgu_events_station_scraped 
  ON external.academic_lgu_events (station, scraped_at DESC);

CREATE INDEX IF NOT EXISTS idx_weather_current_station_observed 
  ON external.weather_current (station, observed_at DESC);

-- 2. Ground Control Mobile Incidents & Active Triggers
CREATE INDEX IF NOT EXISTS idx_incidents_station_status_created 
  ON gcs.incidents (station_name, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_incidents_active_alerts 
  ON gcs.incidents (status, created_at DESC) 
  WHERE status != 'resolved';

-- 3. Prescriptive Analytics & APTA Task Completion Real-Time Sync
CREATE INDEX IF NOT EXISTS idx_protocol_task_status_lookup 
  ON "Analytics".protocol_task_status (station_name, task_name, active_action);

CREATE INDEX IF NOT EXISTS idx_prescriptive_task_checklist_decision 
  ON "Analytics".prescriptive_task_checklist (decision_action, task_order);

CREATE INDEX IF NOT EXISTS idx_apta_tactics_protocol 
  ON "APTA".apta_protocols_tactics (protocol_id, tactic_name);

-- 4. IAM Portal Audit Trail Lookups
CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp_actor 
  ON iam.audit_logs (created_at DESC, actor_id);
