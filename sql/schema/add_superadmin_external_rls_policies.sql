-- ============================================================================
-- Migration: Add Superadmin Permissive RLS Policies on external Schema Tables
-- ============================================================================
-- Ensures Superadmin accounts can read and audit all data feeds:
-- 1. external.academic_lgu_events (Scraped events feed monitor)
-- 2. external.processed_calendar_tables (Institutional academic schedules monitor)
-- 3. external.friction_weight (Weight factors for transit modeling)
-- ============================================================================

DO $$
BEGIN
    -- 1. external.academic_lgu_events
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'external' 
          AND tablename = 'academic_lgu_events' 
          AND policyname = 'superadmin_all_academic_lgu_events'
    ) THEN
        CREATE POLICY superadmin_all_academic_lgu_events 
        ON external.academic_lgu_events 
        FOR ALL TO authenticated
        USING (iam.is_superadmin() OR iam.current_user_role() = 'Superadmin')
        WITH CHECK (iam.is_superadmin() OR iam.current_user_role() = 'Superadmin');
    END IF;

    -- 2. external.processed_calendar_tables
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'external' 
          AND tablename = 'processed_calendar_tables' 
          AND policyname = 'superadmin_all_processed_calendar_tables'
    ) THEN
        CREATE POLICY superadmin_all_processed_calendar_tables 
        ON external.processed_calendar_tables 
        FOR ALL TO authenticated
        USING (iam.is_superadmin() OR iam.current_user_role() = 'Superadmin')
        WITH CHECK (iam.is_superadmin() OR iam.current_user_role() = 'Superadmin');
    END IF;

    -- 3. external.friction_weight
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'external' 
          AND tablename = 'friction_weight' 
          AND policyname = 'superadmin_all_friction_weight'
    ) THEN
        CREATE POLICY superadmin_all_friction_weight 
        ON external.friction_weight 
        FOR ALL TO authenticated
        USING (iam.is_superadmin() OR iam.current_user_role() = 'Superadmin')
        WITH CHECK (iam.is_superadmin() OR iam.current_user_role() = 'Superadmin');
    END IF;
END $$;
