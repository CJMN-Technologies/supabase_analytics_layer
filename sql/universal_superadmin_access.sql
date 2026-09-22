-- ============================================================================
-- LRT-2 Decision Support System: Universal Superadmin Access & Auth Gatekeeper
-- ============================================================================

-- 1. Create Sequence for Superadmin IDs (SA0001, SA0002, ...)
CREATE SEQUENCE IF NOT EXISTS iam.seq_users_sa START WITH 1 INCREMENT BY 1;

-- 2. Enhance ID Generation Trigger to support SAxxxx identifiers
CREATE OR REPLACE FUNCTION iam.tg_generate_user_id()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_seq_val integer;
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        IF NEW.role IN ('Superadmin', 'Super Administrator') THEN
            v_seq_val := nextval('iam.seq_users_sa');
            NEW.id := 'SA' || LPAD(v_seq_val::text, 4, '0');
        ELSIF NEW.role = 'Provision Officer' THEN
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
$function$;

-- 3. Canonical Superadmin Verification Function
CREATE OR REPLACE FUNCTION iam.is_superadmin(p_auth_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = iam, public, auth
AS $function$
DECLARE
    v_role text;
    v_username text;
    v_email text;
BEGIN
    IF p_auth_uid IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT role, username, email
    INTO v_role, v_username, v_email
    FROM iam.users
    WHERE auth_user_id = p_auth_uid
    LIMIT 1;

    IF v_role IN ('Superadmin', 'Super Administrator') 
       OR v_username IN ('PO-ADMIN', 'SA-ADMIN', 'superadmin')
       OR LOWER(v_email) IN ('rhnatividad.sa@gmail.com', 'superadmin@lrta.gov.ph') THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$function$;

-- 4. Exemption of Superadmin from Single-Device Concurrency Lock
CREATE OR REPLACE FUNCTION iam.can_account_login(p_user_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = iam, public, auth
AS $function$
DECLARE
  v_user_rec RECORD;
BEGIN
  SELECT id, role, username, email, active_session_id, last_heartbeat_at
  INTO v_user_rec
  FROM iam.users
  WHERE LOWER(email) = LOWER(TRIM(p_user_id))
     OR LOWER(username) = LOWER(TRIM(p_user_id))
     OR id = TRIM(p_user_id)
     OR auth_user_id::text = TRIM(p_user_id)
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', true);
  END IF;

  -- UNCONDITIONAL BYPASS: Superadmin accounts can log in across all desktop, mobile, and web apps simultaneously
  IF v_user_rec.role IN ('Superadmin', 'Super Administrator')
     OR v_user_rec.username IN ('PO-ADMIN', 'SA-ADMIN', 'superadmin')
     OR LOWER(v_user_rec.email) IN ('rhnatividad.sa@gmail.com', 'superadmin@lrta.gov.ph') THEN
    RETURN jsonb_build_object(
      'allowed', true,
      'is_superadmin', true,
      'message', 'Superadmin multi-application concurrency active.'
    );
  END IF;

  -- Standard single-active-device check for operational field personnel
  IF v_user_rec.active_session_id IS NULL 
     OR v_user_rec.active_session_id = '' 
     OR (v_user_rec.last_heartbeat_at IS NULL OR v_user_rec.last_heartbeat_at < NOW() - INTERVAL '20 seconds') THEN
    RETURN jsonb_build_object('allowed', true);
  ELSE
    RETURN jsonb_build_object(
      'allowed', false, 
      'message', 'Account is currently active on another device. Please log out from the active device before signing in here.'
    );
  END IF;
END;
$function$;

-- 5. Universal Auth Gatekeeper for Present and Future Applications
CREATE OR REPLACE FUNCTION iam.verify_app_access(
    p_app_name text,
    p_auth_user_id uuid DEFAULT auth.uid()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = iam, public, auth
AS $function$
DECLARE
    v_user RECORD;
    v_is_super boolean;
    v_normalized_app text;
BEGIN
    IF p_auth_user_id IS NULL THEN
        RETURN jsonb_build_object('allowed', false, 'error', 'Unauthenticated');
    END IF;

    SELECT id, auth_user_id, username, first_name, last_name, role, email, status, station
    INTO v_user
    FROM iam.users
    WHERE auth_user_id = p_auth_user_id
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('allowed', false, 'error', 'User profile not found in IAM directory.');
    END IF;

    IF v_user.status = 'suspended' THEN
        RETURN jsonb_build_object('allowed', false, 'error', 'Account has been suspended.');
    END IF;

    v_is_super := (
        v_user.role IN ('Superadmin', 'Super Administrator') 
        OR v_user.username IN ('PO-ADMIN', 'SA-ADMIN', 'superadmin')
        OR LOWER(v_user.email) IN ('rhnatividad.sa@gmail.com', 'superadmin@lrta.gov.ph')
    );

    -- RULE 1: Superadmin has unconditional root access to ALL applications (existing or future)
    IF v_is_super THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'is_superadmin', true,
            'role', 'Superadmin',
            'actual_role', v_user.role,
            'user_id', v_user.id,
            'username', v_user.username,
            'station', COALESCE(v_user.station, 'All Stations'),
            'message', 'Superadmin universal root authorization granted.'
        );
    END IF;

    v_normalized_app := LOWER(TRIM(p_app_name));

    -- RULE 2: Standard application-specific role checks
    IF v_normalized_app IN ('command_center', 'command center', 'command_center_dashboard') THEN
        IF v_user.role = 'Command Center Officer' THEN
            RETURN jsonb_build_object('allowed', true, 'is_superadmin', false, 'role', v_user.role, 'user_id', v_user.id, 'username', v_user.username);
        END IF;
    ELSIF v_normalized_app IN ('ground_control_mobile', 'ground control mobile', 'ground_control') THEN
        IF v_user.role = 'Ground Control Staff' THEN
            RETURN jsonb_build_object('allowed', true, 'is_superadmin', false, 'role', v_user.role, 'user_id', v_user.id, 'username', v_user.username, 'station', v_user.station);
        END IF;
    ELSIF v_normalized_app IN ('iam_portal', 'iam portal', 'identity_management') THEN
        IF v_user.role IN ('Provision Officer', 'Superadmin', 'Super Administrator') THEN
            RETURN jsonb_build_object('allowed', true, 'is_superadmin', false, 'role', v_user.role, 'user_id', v_user.id, 'username', v_user.username);
        END IF;
    ELSE
        -- Future applications can define specific requirements or rely on general active staff status
        RETURN jsonb_build_object('allowed', false, 'error', 'No role authorization mapping found for requested application.');
    END IF;

    RETURN jsonb_build_object('allowed', false, 'error', 'Unauthorized role for requested application.');
END;
$function$;

-- 6. Grant Superadmin Permissive RLS Policies Across All Schemas
DO $$
BEGIN
    -- iam.users
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'iam' AND tablename = 'users' AND policyname = 'superadmin_all_on_users') THEN
        CREATE POLICY superadmin_all_on_users ON iam.users FOR ALL TO authenticated
        USING (iam.is_superadmin()) WITH CHECK (iam.is_superadmin());
    END IF;

    -- iam.audit_logs
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'iam' AND tablename = 'audit_logs' AND policyname = 'superadmin_all_on_audit_logs') THEN
        CREATE POLICY superadmin_all_on_audit_logs ON iam.audit_logs FOR ALL TO authenticated
        USING (iam.is_superadmin()) WITH CHECK (iam.is_superadmin());
    END IF;

    -- gcs.shifts
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'gcs' AND tablename = 'shifts' AND policyname = 'superadmin_all_on_shifts') THEN
        CREATE POLICY superadmin_all_on_shifts ON gcs.shifts FOR ALL TO authenticated
        USING (iam.is_superadmin()) WITH CHECK (iam.is_superadmin());
    END IF;

    -- gcs.incidents
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'gcs' AND tablename = 'incidents' AND policyname = 'superadmin_all_on_incidents') THEN
        CREATE POLICY superadmin_all_on_incidents ON gcs.incidents FOR ALL TO authenticated
        USING (iam.is_superadmin()) WITH CHECK (iam.is_superadmin());
    END IF;

    -- gcs.emergency_contacts
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'gcs' AND tablename = 'emergency_contacts' AND policyname = 'superadmin_all_on_emergency_contacts') THEN
        CREATE POLICY superadmin_all_on_emergency_contacts ON gcs.emergency_contacts FOR ALL TO authenticated
        USING (iam.is_superadmin()) WITH CHECK (iam.is_superadmin());
    END IF;

    -- Analytics.prescriptive_protocol_deployments
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'Analytics' AND tablename = 'prescriptive_protocol_deployments' AND policyname = 'superadmin_all_on_protocol_deployments') THEN
        CREATE POLICY superadmin_all_on_protocol_deployments ON "Analytics".prescriptive_protocol_deployments FOR ALL TO authenticated
        USING (iam.is_superadmin()) WITH CHECK (iam.is_superadmin());
    END IF;

    -- Analytics.simulation_history
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'Analytics' AND tablename = 'simulation_history' AND policyname = 'superadmin_all_on_simulation_history') THEN
        CREATE POLICY superadmin_all_on_simulation_history ON "Analytics".simulation_history FOR ALL TO authenticated
        USING (iam.is_superadmin()) WITH CHECK (iam.is_superadmin());
    END IF;

    -- Analytics.hourly_threshold_baselines
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'Analytics' AND tablename = 'hourly_threshold_baselines' AND policyname = 'superadmin_all_on_threshold_baselines') THEN
        CREATE POLICY superadmin_all_on_threshold_baselines ON "Analytics".hourly_threshold_baselines FOR ALL TO authenticated
        USING (iam.is_superadmin()) WITH CHECK (iam.is_superadmin());
    END IF;

    -- Analytics.prescriptive_task_checklist
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'Analytics' AND tablename = 'prescriptive_task_checklist' AND policyname = 'superadmin_all_on_task_checklist') THEN
        CREATE POLICY superadmin_all_on_task_checklist ON "Analytics".prescriptive_task_checklist FOR ALL TO authenticated
        USING (iam.is_superadmin()) WITH CHECK (iam.is_superadmin());
    END IF;
END $$;

-- 7. Ensure PO0001 (rhnatividad.sa@gmail.com) has role 'Superadmin'
UPDATE iam.users
SET role = 'Superadmin',
    updated_at = NOW()
WHERE id = 'PO0001' OR email = 'rhnatividad.sa@gmail.com';
