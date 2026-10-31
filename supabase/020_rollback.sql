-- ==============================================================================
-- DigiQ Rollback 020: Restore Anon Privileges (Rollback for 020_revoke_anon_rpc.sql)
-- File: supabase/020_rollback.sql
-- ==============================================================================

BEGIN;

DO $$
DECLARE
  r RECORD;
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
  FOR r IN
    SELECT
      p.oid::regprocedure AS func_sig
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = ANY(v_revoked_funcs)
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated, service_role;', r.func_sig);
    RAISE NOTICE 'Dikembalikan hak EXECUTE anon: %', r.func_sig;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_claim(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_mark_delivered(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_pending_claims() TO anon, authenticated, service_role;

COMMIT;
