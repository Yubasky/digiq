-- ==============================================================================
-- DigiQ Migration 016 ROLLBACK:
-- Kembalikan resolve_login_email ke versi 014 & Hapus ensure_my_profile
-- File: supabase/016_rollback.sql
-- ==============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.ensure_my_profile();

CREATE OR REPLACE FUNCTION public.resolve_login_email(p_identifier TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean TEXT;
  v_email TEXT;
BEGIN
  v_clean := LOWER(TRIM(COALESCE(p_identifier, '')));

  IF v_clean = '' THEN
    RETURN NULL;
  END IF;

  IF v_clean LIKE '%@%' THEN
    RETURN v_clean;
  END IF;

  SELECT u.email INTO v_email
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE LOWER(p.username) = v_clean
  LIMIT 1;

  RETURN v_email;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_login_email(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_login_email(TEXT) TO anon, authenticated, service_role;

DROP TABLE IF EXISTS public.login_resolve_rate_limits;

COMMIT;

