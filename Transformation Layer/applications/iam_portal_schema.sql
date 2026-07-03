-- ============================================================================
-- SQL Script: IAM Portal Schema, Directory, and RBAC Policies
-- Classification: Application Layer (I.A.M Portal)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS iam;

-- Sequences for user ID generation
CREATE SEQUENCE IF NOT EXISTS iam.seq_users_po START WITH 1;
CREATE SEQUENCE IF NOT EXISTS iam.seq_users_cco START WITH 1;
CREATE SEQUENCE IF NOT EXISTS iam.seq_users_gcs START WITH 1;
CREATE SEQUENCE IF NOT EXISTS iam.seq_audit_logs START WITH 1;

-- 1. Create Users Table
DROP TABLE IF EXISTS iam.users CASCADE;
CREATE TABLE iam.users (
    id text PRIMARY KEY,
    auth_user_id uuid UNIQUE,
    username text UNIQUE NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    role text NOT NULL CHECK (role IN ('Command Center Officer', 'Ground Control Staff', 'Provision Officer')),
    email text,
    mobile text CHECK (mobile IS NULL OR mobile ~ '^[0-9]{11}$'),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    station text,
    photo_url text,
    security_key text UNIQUE NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

-- Trigger function to automatically generate human-readable user IDs based on role
CREATE OR REPLACE FUNCTION iam.tg_generate_user_id()
RETURNS trigger AS $$
DECLARE
    v_seq_val integer;
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        IF NEW.role = 'Provision Officer' THEN
            v_seq_val := nextval('iam.seq_users_po');
            NEW.id := 'PO' || LPAD(v_seq_val::text, 4, '0');
        ELSIF NEW.role = 'Command Center Officer' THEN
            v_seq_val := nextval('iam.seq_users_cco');
            NEW.id := 'CCO' || LPAD(v_seq_val::text, 4, '0');
        ELSIF NEW.role = 'Ground Control Staff' THEN
            v_seq_val := nextval('iam.seq_users_gcs');
            NEW.id := 'GCS' || LPAD(v_seq_val::text, 4, '0');
        ELSE
            NEW.id := 'USR' || LPAD(nextval('iam.seq_users_cco')::text, 4, '0');
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tg_generate_user_id ON iam.users;
CREATE TRIGGER tg_generate_user_id
BEFORE INSERT ON iam.users
FOR EACH ROW
EXECUTE FUNCTION iam.tg_generate_user_id();

CREATE INDEX IF NOT EXISTS idx_iam_users_username ON iam.users (username);

-- 2. Create Audit Logs Table
DROP TABLE IF EXISTS iam.audit_logs CASCADE;
CREATE TABLE iam.audit_logs (
    id text PRIMARY KEY DEFAULT ('AUD' || LPAD(nextval('iam.seq_audit_logs')::text, 6, '0')),
    actor_id text REFERENCES iam.users(id) ON DELETE SET NULL,
    actor_username text NOT NULL,
    action text NOT NULL,
    target text NOT NULL,
    result text NOT NULL CHECK (result IN ('success', 'warning', 'error')),
    created_at timestamp with time zone DEFAULT now()
);

-- ============================================================================
-- ROLE-BASED ACCESS CONTROL (RBAC) & ROW LEVEL SECURITY (RLS)
-- ============================================================================

ALTER TABLE iam.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.audit_logs ENABLE ROW LEVEL SECURITY;

-- Helper function to check role of current user
CREATE OR REPLACE FUNCTION iam.current_user_role()
RETURNS text AS $$
BEGIN
    RETURN (SELECT role FROM iam.users WHERE auth_user_id = auth.uid() AND status = 'active');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS Policies for iam.users
DROP POLICY IF EXISTS po_full_access ON iam.users;
CREATE POLICY po_full_access ON iam.users
    FOR ALL
    TO authenticated
    USING (iam.current_user_role() = 'Provision Officer')
    WITH CHECK (iam.current_user_role() = 'Provision Officer');

DROP POLICY IF EXISTS cco_read_directory ON iam.users;
CREATE POLICY cco_read_directory ON iam.users
    FOR SELECT
    TO authenticated
    USING (iam.current_user_role() = 'Command Center Officer');

DROP POLICY IF EXISTS user_read_own ON iam.users;
CREATE POLICY user_read_own ON iam.users
    FOR SELECT
    TO authenticated
    USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS anon_register_key ON iam.users;
CREATE POLICY anon_register_key ON iam.users
    FOR SELECT
    TO anon, authenticated
    USING (auth_user_id IS NULL OR auth_user_id = auth.uid());

DROP POLICY IF EXISTS user_update_profile ON iam.users;
CREATE POLICY user_update_profile ON iam.users
    FOR UPDATE
    TO authenticated
    USING (auth_user_id IS NULL OR auth_user_id = auth.uid())
    WITH CHECK (auth_user_id = auth.uid());

-- RLS Policies for iam.audit_logs
DROP POLICY IF EXISTS po_write_read_audit ON iam.audit_logs;
CREATE POLICY po_write_read_audit ON iam.audit_logs
    FOR ALL
    TO authenticated
    USING (iam.current_user_role() = 'Provision Officer')
    WITH CHECK (iam.current_user_role() = 'Provision Officer');

DROP POLICY IF EXISTS cco_read_audit ON iam.audit_logs;
CREATE POLICY cco_read_audit ON iam.audit_logs
    FOR SELECT
    TO authenticated
    USING (iam.current_user_role() = 'Command Center Officer');

-- Seed Initial Bootstrap Provision Officer User (First User Bootstrap Problem)
INSERT INTO iam.users (username, first_name, last_name, role, email, status, security_key)
VALUES (
    'PO-ADMIN',
    'System',
    'Administrator',
    'Provision Officer',
    'admin@iamportal.local',
    'active',
    'PO-ADMIN-BOOTSTRAP-2026'
)
ON CONFLICT (security_key) DO UPDATE SET
    username = EXCLUDED.username,
    role = EXCLUDED.role,
    status = EXCLUDED.status;
