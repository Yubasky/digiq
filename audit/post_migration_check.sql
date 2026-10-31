-- ==============================================================================
-- DigiQ Post-Migration 019 Verification Check
-- File: audit/post_migration_check.sql
-- HANYA BERISI QUERY SELECT (READ-ONLY) UNTUK DIJALANKAN DI SQL EDITOR SETELAH MIGRASI
-- ==============================================================================

-- 1. Verifikasi Keberadaan Kolom Klaim di public.transactions
SELECT
  column_name,
  data_type,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'transactions'
  AND column_name IN (
    'claim_status',
    'claim_requested_at',
    'delivered_at',
    'delivered_by',
    'claim_conversation_id'
  )
ORDER BY column_name;

-- 2. Verifikasi Kolom kind dan trx_id di public.chat_messages
SELECT
  column_name,
  data_type,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'chat_messages'
  AND column_name IN ('kind', 'trx_id')
ORDER BY column_name;

-- 3. Verifikasi Tabel Pendukung: claim_events & claim_rate_limits
SELECT
  table_name,
  rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('claim_events', 'claim_rate_limits')
ORDER BY tablename;

-- 4. Verifikasi Hak Akses Seluruh Fungsi SECURITY DEFINER di Schema public
-- Menampilkan status has_function_privilege untuk role anon dan authenticated
-- Kolom compliance_status menandai secara tegas apakah hak akses anon sesuai aturan keamanan.
SELECT
  p.oid::regprocedure AS function_signature,
  p.prosecdef AS is_security_definer,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute,
  CASE
    WHEN p.proname IN ('check_email_available', 'check_username_available', 'resolve_login_email', 'validate_signup_email')
      THEN 'PUBLIC/PRE-LOGIN (OK IF TRUE)'
    ELSE 'SENSITIVE (MUST BE FALSE)'
  END AS security_rule,
  CASE
    WHEN p.proname IN ('check_email_available', 'check_username_available', 'resolve_login_email', 'validate_signup_email')
      THEN CASE WHEN has_function_privilege('anon', p.oid, 'EXECUTE') THEN 'COMPLIANT (PASS)' ELSE 'UNEXPECTED (FAIL: pre-login blocked)' END
    ELSE
      CASE WHEN NOT has_function_privilege('anon', p.oid, 'EXECUTE') THEN 'COMPLIANT (PASS)' ELSE 'VULNERABLE (FAIL: anon can execute)' END
  END AS compliance_status
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
ORDER BY compliance_status DESC, p.proname ASC;

-- 5. Verifikasi Triggers Proteksi Aktif
SELECT
  trigger_name,
  event_manipulation,
  event_object_table,
  action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND trigger_name IN ('trg_protect_chat_messages', 'trg_protect_transactions_claim')
ORDER BY trigger_name;

-- 6. Verifikasi Kebijakan RLS pada chat_messages dan claim_events
SELECT
  tablename,
  policyname,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('chat_messages', 'claim_events')
ORDER BY tablename, policyname;

