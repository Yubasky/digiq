-- ==============================================================================
-- DigiQ Migration 020: Revoke Anon Execute Privileges on Non-Public RPCs
-- File: supabase/020_revoke_anon_rpc.sql
-- ==============================================================================
-- TUJUAN:
-- Mencabut hak EXECUTE dari role `anon` dan pseudo-role `PUBLIC` pada fungsi-fungsi
-- yang memerlukan autentikasi (khususnya alur klaim produk, admin dashboard, dan
-- mutasi transaksi), sehingga pemanggilan anonim ditolak langsung di layer database engine
-- dengan "permission denied for function ...", tanpa pernah mengeksekusi body fungsi.
--
-- FUNGSI PRA-LOGIN / PUBLIK YANG TETAP DIBERI AKSES ANON:
-- 1. check_email_available(TEXT)     - Pengecekan ketersediaan email saat registrasi
-- 2. check_username_available(TEXT)  - Pengecekan ketersediaan username saat registrasi
-- 3. resolve_login_email(TEXT)       - Resolusi username/no. telepon ke email sebelum sign in
-- 4. validate_signup_email(TEXT)     - Validasi domain email disposable saat registrasi
-- ==============================================================================

BEGIN;

DO $$
DECLARE
  r RECORD;
  -- Daftar nama fungsi yang WAJIB dicabut dari anon dan PUBLIC
  v_revoked_funcs TEXT[] := ARRAY[
    'request_claim',
    'admin_mark_delivered',
    'get_admin_pending_claims',
    'admin_list_chat_rooms',
    'admin_list_mutations',
    'admin_today_stats',
    'admin_update_transaction_status',
    'admin_session_ok',
    'cancel_my_pending_transaction',
    'create_purchase_transaction',
    'ensure_my_profile',
    'expire_pending_transactions',
    'update_my_profile',
    'verify_payment_by_amount',
    'confirm_user_by_email',
    'is_admin',
    'is_email_verified'
  ];
BEGIN
  -- Mengambil signature tepat lewat pg_proc dan regprocedure agar tidak salah argumen
  FOR r IN
    SELECT
      p.oid::regprocedure AS func_sig,
      p.proname AS func_name
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = ANY(v_revoked_funcs)
  LOOP
    -- 1. Cabut EXECUTE dari anon dan PUBLIC
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, PUBLIC;', r.func_sig);

    -- 2. Pastikan authenticated dan service_role memiliki hak EXECUTE
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role;', r.func_sig);

    RAISE NOTICE 'Dicabut dari anon & PUBLIC: %', r.func_sig;
  END LOOP;
END;
$$;

-- Eksplisit deklarasi statis untuk fungsi klaim utama (idempoten & transparan)
REVOKE ALL ON FUNCTION public.request_claim(UUID) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_claim(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_mark_delivered(UUID) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mark_delivered(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_admin_pending_claims() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_pending_claims() TO authenticated, service_role;

-- Pastikan fungsi pra-login tetap dapat dieksekusi oleh anon & authenticated
GRANT EXECUTE ON FUNCTION public.check_email_available(TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_username_available(TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_login_email(TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.validate_signup_email(TEXT) TO anon, authenticated, service_role;

COMMIT;
