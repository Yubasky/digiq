-- Rollback 015: Restore handle_new_user without auto-confirm
BEGIN;

DROP FUNCTION IF EXISTS public.confirm_user_by_email(TEXT);

COMMIT;
