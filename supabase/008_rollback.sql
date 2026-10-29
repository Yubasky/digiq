-- ==============================================================================
-- DigiQ Rollback 008: Rollback Migration 008 (In-Database Rate Limiting)
-- File: supabase/008_rollback.sql
-- ==============================================================================

BEGIN;

-- 1. Kembalikan RPC check_email_available ke versi migrasi 007 (tanpa pembatasan laju lokal)
CREATE OR REPLACE FUNCTION public.check_email_available(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  v_clean := LOWER(TRIM(COALESCE(p_email, '')));

  IF v_clean = '' 
     OR LENGTH(v_clean) > 254 
     OR v_clean !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' THEN
    RETURN FALSE;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1 
    FROM auth.users 
    WHERE LOWER(email) = v_clean
  );
END;
$$;

REVOKE ALL ON FUNCTION public.check_email_available(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_email_available(TEXT) TO anon, authenticated, service_role;

-- 2. Hapus tabel pencatatan rate limit beserta index-nya
DROP TABLE IF EXISTS public.email_check_rate_limits CASCADE;

COMMIT;

