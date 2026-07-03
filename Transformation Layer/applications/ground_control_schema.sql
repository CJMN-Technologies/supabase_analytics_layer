-- ============================================================================
-- SQL Script: Ground Control System Schema, Incidents, Shifts, Emergency Contacts
-- Classification: Application Layer (Ground Control Mobile App)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS gcs;

-- Drop tables first to allow clean type recreation
DROP TABLE IF EXISTS gcs.shifts CASCADE;
DROP TABLE IF EXISTS gcs.incidents CASCADE;

-- Drop and recreate the incident category enum type
DROP TYPE IF EXISTS gcs.incident_category CASCADE;
CREATE TYPE gcs.incident_category AS ENUM (
    'Facility Order',
    'Platform Safety',
    'Property Crime',
    'Fare Collection',
    'Concourse Security',
    'Boarding Order',
    'Sanitation',
    'Contraband',
    'Public Order / Terrorism',
    'Gender-Based Offenses',
    'Physical Safety',
    'Other'
);

-- Sequences for shift, incident, and contact ID generation
CREATE SEQUENCE IF NOT EXISTS gcs.seq_shifts START WITH 1;
CREATE SEQUENCE IF NOT EXISTS gcs.seq_incidents START WITH 1;
CREATE SEQUENCE IF NOT EXISTS gcs.seq_emergency_contacts START WITH 1;

-- 1. Create Shifts Table
CREATE TABLE IF NOT EXISTS gcs.shifts (
    id text PRIMARY KEY DEFAULT ('SHF' || LPAD(nextval('gcs.seq_shifts')::text, 6, '0')),
    user_id text NOT NULL REFERENCES iam.users(id) ON DELETE CASCADE,
    username text NOT NULL,
    station_name text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    started_at timestamp with time zone DEFAULT now(),
    ended_at timestamp with time zone
);

-- 2. Create Incidents Table
CREATE TABLE IF NOT EXISTS gcs.incidents (
    id text PRIMARY KEY DEFAULT ('INC' || LPAD(nextval('gcs.seq_incidents')::text, 6, '0')),
    reporter_id text REFERENCES iam.users(id) ON DELETE SET NULL,
    reporter_username text NOT NULL,
    station_name text NOT NULL,
    incident_type gcs.incident_category NOT NULL,
    description text,
    severity text NOT NULL CHECK (severity IN ('Critical', 'Warning')),
    photo_url text,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'acknowledged', 'resolved')),
    created_at timestamp with time zone DEFAULT now(),
    resolved_at timestamp with time zone
);

-- 3. Create Emergency Contacts Table
CREATE TABLE IF NOT EXISTS gcs.emergency_contacts (
    id text PRIMARY KEY DEFAULT ('CON' || LPAD(nextval('gcs.seq_emergency_contacts')::text, 4, '0')),
    label text NOT NULL,
    number text NOT NULL,
    color text NOT NULL DEFAULT 'gray' CHECK (color IN ('purple', 'red', 'gray')),
    is_global boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);

-- Seed Emergency Contacts
INSERT INTO gcs.emergency_contacts (label, number, color, is_global)
VALUES 
  ('Call Santolan Office', '+63 2 852-1540', 'purple', true),
  ('LRT-2 Emergency Hotline', '+63 2 852-1541', 'red', true),
  ('Disaster (Earthquake/Fire)', '911', 'red', true),
  ('Public Safety (Crime/Hold-ups)', '117', 'red', true),
  ('Medical (Hospital/Ambulance)', '1555', 'red', true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- ROLE-BASED ACCESS CONTROL (RBAC) & ROW LEVEL SECURITY (RLS)
-- ============================================================================

ALTER TABLE gcs.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE gcs.incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE gcs.emergency_contacts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for gcs.shifts
DROP POLICY IF EXISTS cco_read_shifts ON gcs.shifts;
CREATE POLICY cco_read_shifts ON gcs.shifts
    FOR SELECT
    TO authenticated
    USING (iam.current_user_role() = 'Command Center Officer');

DROP POLICY IF EXISTS gcs_manage_shifts ON gcs.shifts;
CREATE POLICY gcs_manage_shifts ON gcs.shifts
    FOR ALL
    TO authenticated
    USING (
        user_id IN (SELECT id FROM iam.users WHERE auth_user_id = auth.uid() AND role = 'Ground Control Staff')
    )
    WITH CHECK (
        user_id IN (SELECT id FROM iam.users WHERE auth_user_id = auth.uid() AND role = 'Ground Control Staff')
    );

-- RLS Policies for gcs.incidents
DROP POLICY IF EXISTS cco_manage_incidents ON gcs.incidents;
CREATE POLICY cco_manage_incidents ON gcs.incidents
    FOR ALL
    TO authenticated
    USING (iam.current_user_role() = 'Command Center Officer')
    WITH CHECK (iam.current_user_role() = 'Command Center Officer');

DROP POLICY IF EXISTS gcs_log_incidents ON gcs.incidents;
CREATE POLICY gcs_log_incidents ON gcs.incidents
    FOR ALL
    TO authenticated
    USING (
        reporter_id IN (SELECT id FROM iam.users WHERE auth_user_id = auth.uid() AND role = 'Ground Control Staff')
    )
    WITH CHECK (
        reporter_id IN (SELECT id FROM iam.users WHERE auth_user_id = auth.uid() AND role = 'Ground Control Staff')
    );

-- RLS Policies for gcs.emergency_contacts
DROP POLICY IF EXISTS authenticated_read_contacts ON gcs.emergency_contacts;
CREATE POLICY authenticated_read_contacts ON gcs.emergency_contacts
    FOR SELECT
    TO authenticated
    USING (true);

-- ============================================================================
-- TRIGGER: SYNC INCIDENTS TO EVENTS_CONSOLIDATED (REAL-TIME METRICS)
-- ============================================================================

CREATE OR REPLACE FUNCTION gcs.sync_incidents_to_events_consolidated()
RETURNS trigger AS $$
DECLARE
    v_trig_cat text;
    v_weight numeric;
    v_event_date date;
    v_scrape_id text;
BEGIN
    -- If deleted or resolved, clear the consolidated event row
    IF TG_OP = 'DELETE' OR NEW.status = 'resolved' THEN
        DELETE FROM external.events_consolidated 
        WHERE source_table = 'incidents' AND source_id = COALESCE(NEW.id, OLD.id)::text;
        RETURN COALESCE(NEW, OLD);
    END IF;

    -- Map GCS incident severity to operational friction trigger categories
    IF NEW.severity = 'Critical' THEN
        v_trig_cat := 'Code Red / Standstill';
    ELSIF NEW.severity = 'Warning' THEN
        v_trig_cat := 'Degraded Headway';
    ELSE
        v_trig_cat := 'Code Green';
    END IF;

    -- Look up the friction weight
    SELECT friction_weight INTO v_weight
    FROM external.friction_weight
    WHERE friction_domain = 'operational' AND trigger_category = v_trig_cat
    LIMIT 1;
    v_weight := COALESCE(v_weight, 0.0);

    v_event_date := NEW.created_at::date;
    v_scrape_id := 'INC-' || TO_CHAR(v_event_date, 'MMDD') || '-' || NEW.id::text;

    -- Upsert into consolidated events
    INSERT INTO external.events_consolidated (
        id, station, event_date, source_table, source_id, source_name,
        event_name, event_category, friction_domain, trigger_category,
        normalized_score, friction_weight_ref, announcement_time, updated_at
    )
    VALUES (
        v_scrape_id,
        external.normalize_station_name(NEW.station_name),
        v_event_date,
        'incidents',
        NEW.id::text,
        'Ground Control System',
        CASE 
            WHEN NEW.incident_type::text = 'Other' AND NEW.description IS NOT NULL AND NEW.description != '' 
            THEN 'Other: ' || NEW.description 
            ELSE NEW.incident_type::text 
        END || ' (' || NEW.severity || ')',
        'incident',
        'operational',
        v_trig_cat,
        v_weight,
        v_weight,
        NEW.created_at,
        now()
    )
    ON CONFLICT (id) DO UPDATE SET
        station = EXCLUDED.station,
        event_date = EXCLUDED.event_date,
        event_name = EXCLUDED.event_name,
        trigger_category = EXCLUDED.trigger_category,
        normalized_score = EXCLUDED.normalized_score,
        friction_weight_ref = EXCLUDED.friction_weight_ref,
        announcement_time = EXCLUDED.announcement_time,
        updated_at = now();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger
DROP TRIGGER IF EXISTS tg_sync_gcs_incidents ON gcs.incidents;
CREATE TRIGGER tg_sync_gcs_incidents
AFTER INSERT OR UPDATE OR DELETE ON gcs.incidents
FOR EACH ROW EXECUTE FUNCTION gcs.sync_incidents_to_events_consolidated();

-- Trigger to automatically set resolved_at timestamp when status is set to resolved
CREATE OR REPLACE FUNCTION gcs.set_incident_resolved_timestamp()
RETURNS trigger AS $$
BEGIN
    IF NEW.status = 'resolved' AND (OLD.status IS NULL OR OLD.status != 'resolved') THEN
        NEW.resolved_at := now();
    ELSIF NEW.status != 'resolved' THEN
        NEW.resolved_at := NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tg_set_resolved_timestamp ON gcs.incidents;
CREATE TRIGGER tg_set_resolved_timestamp
BEFORE UPDATE ON gcs.incidents
FOR EACH ROW EXECUTE FUNCTION gcs.set_incident_resolved_timestamp();
