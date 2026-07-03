-- ============================================================================
-- SQL Script: Generate Descriptive Analytics Layer & Threshold Benchmarking
-- Classification: Descriptive Analytics (LRT Train & Operations Management System)
-- ============================================================================

-- 1. Create Analytics schema
CREATE SCHEMA IF NOT EXISTS "Analytics";

-- 2. Create optimized, reusable hourly actuals view to prevent multiple expensive unions
CREATE OR REPLACE VIEW "Analytics".vw_hourly_actuals AS
WITH combined_hourly AS (
  SELECT date, time_period as hour_period, station_name, flow_type, volume FROM (
    SELECT date, time_period, anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit FROM "AFCS".ridership_2021 WHERE time_period NOT IN ('DAILY_TOTAL', 'MONTHLY_TOTAL', 'PEAK_TOTAL')
    UNION ALL
    SELECT date, time_period, anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit FROM "AFCS".ridership_2022 WHERE time_period NOT IN ('DAILY_TOTAL', 'MONTHLY_TOTAL', 'PEAK_TOTAL')
    UNION ALL
    SELECT date, time_period, anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit FROM "AFCS".ridership_2023 WHERE time_period NOT IN ('DAILY_TOTAL', 'MONTHLY_TOTAL', 'PEAK_TOTAL')
    UNION ALL
    SELECT date, time_period, anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit FROM "AFCS".ridership_2024 WHERE time_period NOT IN ('DAILY_TOTAL', 'MONTHLY_TOTAL', 'PEAK_TOTAL')
    UNION ALL
    SELECT date, time_period, anonas_entry, anonas_exit, antipolo_entry, antipolo_exit, araneta_center_cubao_entry, araneta_center_cubao_exit, betty_go_belmonte_entry, betty_go_belmonte_exit, gilmore_entry, gilmore_exit, j_ruiz_entry, j_ruiz_exit, katipunan_entry, katipunan_exit, legarda_entry, legarda_exit, marikina_pasig_entry, marikina_pasig_exit, pureza_entry, pureza_exit, recto_entry, recto_exit, santolan_entry, santolan_exit, v_mapa_entry, v_mapa_exit FROM "AFCS".ridership_2025 WHERE time_period NOT IN ('DAILY_TOTAL', 'MONTHLY_TOTAL', 'PEAK_TOTAL')
  ) raw_union
  CROSS JOIN LATERAL (
    VALUES
      ('Anonas', 'entry', anonas_entry),
      ('Anonas', 'exit', anonas_exit),
      ('Antipolo', 'entry', antipolo_entry),
      ('Antipolo', 'exit', antipolo_exit),
      ('Araneta Center Cubao', 'entry', araneta_center_cubao_entry),
      ('Araneta Center Cubao', 'exit', araneta_center_cubao_exit),
      ('Betty Go-Belmonte', 'entry', betty_go_belmonte_entry),
      ('Betty Go-Belmonte', 'exit', betty_go_belmonte_exit),
      ('Gilmore', 'entry', gilmore_entry),
      ('Gilmore', 'exit', gilmore_exit),
      ('J. Ruiz', 'entry', j_ruiz_entry),
      ('J. Ruiz', 'exit', j_ruiz_exit),
      ('Katipunan', 'entry', katipunan_entry),
      ('Katipunan', 'exit', katipunan_exit),
      ('Legarda', 'entry', legarda_entry),
      ('Legarda', 'exit', legarda_exit),
      ('Marikina-Pasig', 'entry', marikina_pasig_entry),
      ('Marikina-Pasig', 'exit', marikina_pasig_exit),
      ('Pureza', 'entry', pureza_entry),
      ('Pureza', 'exit', pureza_exit),
      ('Recto', 'entry', recto_entry),
      ('Recto', 'exit', recto_exit),
      ('Santolan', 'entry', santolan_entry),
      ('Santolan', 'exit', santolan_exit),
      ('V. Mapa', 'entry', v_mapa_entry),
      ('V. Mapa', 'exit', v_mapa_exit)
  ) AS unpivoted(station_name, flow_type, volume)
)
SELECT date, hour_period, station_name, flow_type, volume FROM combined_hourly;

-- 3. Create hourly threshold baselines table (P50, P80 and P90 benchmarks)
DROP TABLE IF EXISTS "Analytics".hourly_threshold_baselines CASCADE;
CREATE TABLE "Analytics".hourly_threshold_baselines (
    station_name text NOT NULL,
    day_of_week integer NOT NULL, -- 1 = Monday, ..., 7 = Sunday
    hour_period text NOT NULL,    -- e.g. '07:00'
    flow_type text NOT NULL,      -- 'entry' or 'exit'
    median_volume integer NOT NULL, -- P50 (Historical Average/Median)
    warning_threshold integer NOT NULL, -- W_t = P80
    critical_threshold integer NOT NULL, -- C_t = P90
    PRIMARY KEY (station_name, day_of_week, hour_period, flow_type)
);

-- Compute and populate percentiles from the 5-year historical baseline
INSERT INTO "Analytics".hourly_threshold_baselines (station_name, day_of_week, hour_period, flow_type, median_volume, warning_threshold, critical_threshold)
SELECT 
  station_name,
  EXTRACT(ISODOW FROM date)::integer as day_of_week,
  hour_period,
  flow_type,
  COALESCE(ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY COALESCE(volume, 0)))::integer, 0) as median_volume,
  COALESCE(ROUND(percentile_cont(0.8) WITHIN GROUP (ORDER BY COALESCE(volume, 0)))::integer, 0) as warning_threshold,
  COALESCE(ROUND(percentile_cont(0.9) WITHIN GROUP (ORDER BY COALESCE(volume, 0)))::integer, 0) as critical_threshold
FROM "Analytics".vw_hourly_actuals
GROUP BY station_name, EXTRACT(ISODOW FROM date), hour_period, flow_type;

-- 4. Create the core Analytics View with dynamic CFI calculations (Real-time Auto-Updates)
CREATE OR REPLACE VIEW "Analytics".vw_descriptive_metrics AS
WITH hourly_weather AS (
  SELECT 
    weather_date,
    EXTRACT(HOUR FROM (observed_or_forecasted_at AT TIME ZONE 'Asia/Manila'))::integer as weather_hour,
    COALESCE(MAX(normalized_score), 0.0) as weather_score
  FROM external.weather_consolidated
  GROUP BY weather_date, EXTRACT(HOUR FROM (observed_or_forecasted_at AT TIME ZONE 'Asia/Manila'))::integer
),
hourly_events AS (
  SELECT 
    s.station_name,
    d.event_date,
    h.hour_val,
    COALESCE(MAX(CASE WHEN ec.event_category = 'major_event' THEN ec.normalized_score END), 0.0) as academic_surge_score,
    COALESCE(
      MAX(
        CASE 
          WHEN ec.event_category IN ('class_suspension', 'school_break') THEN
            CASE
              WHEN ec.event_category = 'school_break' OR ec.announcement_time IS NULL THEN 1.0
              WHEN ec.announcement_time::date < ec.event_date 
                OR EXTRACT(HOUR FROM (ec.announcement_time AT TIME ZONE 'Asia/Manila')) < 8 THEN 1.0
              ELSE
                CASE
                  WHEN h.hour_val < EXTRACT(HOUR FROM (ec.announcement_time AT TIME ZONE 'Asia/Manila'))::integer THEN 0.0
                  WHEN h.hour_val >= EXTRACT(HOUR FROM (ec.announcement_time AT TIME ZONE 'Asia/Manila'))::integer 
                   AND h.hour_val <= EXTRACT(HOUR FROM (ec.announcement_time AT TIME ZONE 'Asia/Manila'))::integer + 1 THEN -0.4444
                  ELSE 1.0
                END
            END
          ELSE 0.0
        END
      ), 0.0
    ) as civic_mandate_score,
    COALESCE(MAX(CASE WHEN ec.friction_domain = 'operational' THEN ec.normalized_score END), 0.0) as operational_score
  FROM (
    SELECT DISTINCT event_date FROM external.events_consolidated
  ) d
  CROSS JOIN (
    SELECT generate_series(0, 23) as hour_val
  ) h
  CROSS JOIN (
    VALUES 
      ('Anonas'), ('Antipolo'), ('Araneta Center Cubao'), ('Betty Go-Belmonte'), 
      ('Gilmore'), ('J. Ruiz'), ('Katipunan'), ('Legarda'), 
      ('Marikina-Pasig'), ('Pureza'), ('Recto'), ('Santolan'), ('V. Mapa')
  ) s(station_name)
  LEFT JOIN external.events_consolidated ec 
    ON ec.event_date = d.event_date 
    AND (ec.station = s.station_name OR ec.station IS NULL OR ec.station = 'All' OR ec.station = 'All Stations')
  GROUP BY s.station_name, d.event_date, h.hour_val
)
SELECT 
  ch.date,
  ch.hour_period as time_period,
  ch.station_name,
  ch.flow_type,
  ch.volume as actual_volume,
  tb.median_volume as historical_median,
  tb.warning_threshold,
  tb.critical_threshold,
  COALESCE(w.weather_score, 0.0) as weather_score,
  COALESCE(e.academic_surge_score, 0.0) as academic_surge_score,
  COALESCE(e.civic_mandate_score, 0.0) as civic_mandate_score,
  COALESCE(e.operational_score, 0.0) as operational_score,
  ROUND(
    (0.25 * COALESCE(w.weather_score, 0.0)) + 
    (0.15 * COALESCE(e.academic_surge_score, 0.0)) + 
    (0.35 * COALESCE(e.civic_mandate_score, 0.0)) +
    (0.25 * COALESCE(e.operational_score, 0.0)),
    4
  ) as cfi,
  CASE 
    WHEN ch.volume >= tb.critical_threshold THEN 'Critical'
    WHEN ch.volume >= tb.warning_threshold THEN 'Warning'
    ELSE 'Normal'
  END as congestion_level
FROM "Analytics".vw_hourly_actuals ch
LEFT JOIN "Analytics".hourly_threshold_baselines tb 
  ON tb.station_name = ch.station_name 
  AND tb.day_of_week = EXTRACT(ISODOW FROM ch.date)::integer
  AND tb.hour_period = ch.hour_period
  AND tb.flow_type = ch.flow_type
LEFT JOIN hourly_weather w 
  ON w.weather_date = ch.date 
  AND w.weather_hour = EXTRACT(HOUR FROM (ch.hour_period || ':00')::time)::integer
LEFT JOIN hourly_events e 
  ON e.event_date = ch.date 
  AND e.station_name = ch.station_name
  AND e.hour_val = EXTRACT(HOUR FROM (ch.hour_period || ':00')::time)::integer;

-- 5. Create backward-compatible proxy view under Analytics schema for Frontend compatibility
CREATE OR REPLACE VIEW "Analytics".descriptive_historical_capacity_benchmarking AS
SELECT * FROM "Analytics".vw_descriptive_metrics;

-- 6. Expose threshold baselines view for Analytics schema / REST API accessibility
DROP VIEW IF EXISTS "Analytics".descriptive_historical_threshold_baselines CASCADE;
CREATE OR REPLACE VIEW "Analytics".descriptive_historical_threshold_baselines AS
SELECT 
  station_name,
  day_of_week,
  hour_period,
  flow_type,
  median_volume,
  warning_threshold,
  critical_threshold
FROM "Analytics".hourly_threshold_baselines;

-- 7. Create Simulation Run Archival Table (Persists Stress Test Parameters)
CREATE SEQUENCE IF NOT EXISTS "Analytics".seq_simulation_history START WITH 1;

DROP TABLE IF EXISTS "Analytics".simulation_history CASCADE;
CREATE TABLE "Analytics".simulation_history (
    simulation_id text PRIMARY KEY DEFAULT ('SIM' || LPAD(nextval('"Analytics".seq_simulation_history')::text, 6, '0')),
    run_number integer NOT NULL,
    station_name text NOT NULL,
    trigger_type text NOT NULL,
    severity text NOT NULL,
    weather_score numeric NOT NULL,
    academic_score numeric NOT NULL,
    civic_score numeric NOT NULL,
    simulated_peak_volume integer NOT NULL,
    variance_percentage numeric NOT NULL,
    simulated_threat_level text NOT NULL,
    executed_at timestamp with time zone DEFAULT now(),
    is_archived boolean DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_sim_history_station ON "Analytics".simulation_history (station_name);
CREATE INDEX IF NOT EXISTS idx_sim_history_executed ON "Analytics".simulation_history (executed_at);

-- 8. Create Live trigger Feed view for dashboard monitoring feed
CREATE OR REPLACE VIEW "Analytics".descriptive_live_event_feed AS
SELECT 
  id as trigger_id,
  'pagasa'::text as source_type,
  'PAGASA Weather Alert'::text as source,
  'Station: ' || station || ' - ' || trigger_category || ' (Rain: ' || rainfall_mm || 'mm, Temp: ' || temperature_temp_max || '°C)' as message,
  observed_or_forecasted_at AT TIME ZONE 'Asia/Manila' as time,
  CASE 
    WHEN normalized_score >= 0.8 THEN 'critical'::text
    WHEN normalized_score >= 0.45 THEN 'warning'::text
    ELSE 'informational'::text
  END as urgency,
  station as station_name
FROM external.weather_consolidated
WHERE weather_date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
  AND normalized_score > 0.0
UNION ALL
SELECT 
  id as trigger_id,
  CASE 
    WHEN event_category IN ('class_suspension', 'school_break') THEN 'lgu'::text
    ELSE 'institution'::text
  END as source_type,
  source_name as source,
  'Station: ' || station || ' - ' || event_name || ' (' || trigger_category || ')' as message,
  (event_date + time '08:00:00') AT TIME ZONE 'Asia/Manila' as time,
  CASE 
    WHEN normalized_score >= 0.8 THEN 'critical'::text
    WHEN normalized_score >= 0.45 THEN 'warning'::text
    ELSE 'informational'::text
  END as urgency,
  station as station_name
FROM external.events_consolidated
WHERE event_date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
  AND normalized_score > 0.0;
