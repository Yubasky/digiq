-- ==============================================================================
-- DigiQ Migration 014 Rollback
-- File: supabase/014_hardening_registration_and_profiles_rollback.sql
-- ==============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.resolve_login_email(TEXT);

COMMIT;

