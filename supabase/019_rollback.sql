-- ==============================================================================
-- DigiQ Migration 019 Rollback: Revert Fitur Klaim Produk Digital via Chat Admin
-- File: supabase/019_rollback.sql
-- ==============================================================================

BEGIN;

-- 1. Drop RPCs
DROP FUNCTION IF EXISTS public.get_admin_pending_claims();
DROP FUNCTION IF EXISTS public.admin_mark_delivered(UUID);
DROP FUNCTION IF EXISTS public.request_claim(UUID);

-- 2. Drop Triggers & Protect Functions
DROP TRIGGER IF EXISTS trg_protect_transactions_claim ON public.transactions;
DROP FUNCTION IF EXISTS public.protect_transactions_claim_columns();

DROP TRIGGER IF EXISTS trg_protect_chat_messages ON public.chat_messages;
DROP FUNCTION IF EXISTS public.protect_chat_messages_content();

-- 3. Drop Rate Limits & Audit Tables
DROP TABLE IF EXISTS public.claim_rate_limits CASCADE;
DROP TABLE IF EXISTS public.claim_events CASCADE;

-- 4. Restore original chat_insert_customer policy
DROP POLICY IF EXISTS "chat_insert_customer" ON public.chat_messages;
CREATE POLICY "chat_insert_customer"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    NOT public.is_admin()
    AND room_user_id = auth.uid()
    AND sender_id = auth.uid()
  );

-- 5. Drop Indexes
DROP INDEX IF EXISTS public.idx_transactions_claim_status;
DROP INDEX IF EXISTS public.idx_chat_messages_kind;
DROP INDEX IF EXISTS public.idx_chat_messages_trx_id;

-- 6. Drop Columns (Catatan: Pesan chat yang sudah dibuat tetap tersimpan sebagai teks biasa sebelum kolom di-drop)
ALTER TABLE public.chat_messages
  DROP COLUMN IF EXISTS kind,
  DROP COLUMN IF EXISTS trx_id;

ALTER TABLE public.transactions
  DROP COLUMN IF EXISTS claim_status,
  DROP COLUMN IF EXISTS claim_requested_at,
  DROP COLUMN IF EXISTS delivered_at,
  DROP COLUMN IF EXISTS delivered_by,
  DROP COLUMN IF EXISTS claim_conversation_id;

COMMIT;
