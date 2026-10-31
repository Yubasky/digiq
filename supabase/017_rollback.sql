-- supabase/017_rollback.sql
-- Rollback: Kembalikan pembatasan AAL2 pada admin_session_ok dan admin_update_transaction_status

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_session_ok()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN public.is_admin() AND COALESCE(auth.jwt() ->> 'aal', '') = 'aal2';
END;
$$;

REVOKE ALL ON FUNCTION public.admin_session_ok() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_session_ok() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_update_transaction_status(
  p_transaction_id UUID,
  p_new_status     TEXT,
  p_mutation_id    UUID DEFAULT NULL
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trx public.transactions%ROWTYPE;
BEGIN
  IF NOT public.admin_session_ok() THEN
    RAISE EXCEPTION 'Akses ditolak: hanya admin dengan verifikasi 2FA (AAL2) yang dapat mengubah status'
      USING ERRCODE = '42501';
  END IF;

  IF p_new_status NOT IN ('success', 'failed') THEN
    RAISE EXCEPTION 'Status tidak valid. Harus success atau failed.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_trx
  FROM public.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaksi tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  IF v_trx.status IN ('success', 'failed') THEN
    RAISE EXCEPTION 'Transaksi sudah final (%) dan tidak dapat diubah lagi', v_trx.status
      USING ERRCODE = 'P0001';
  END IF;

  IF p_new_status = 'failed' THEN
    UPDATE public.transactions
    SET
      status      = 'failed',
      verified_by = 'admin'
    WHERE id = p_transaction_id
    RETURNING * INTO v_trx;

    UPDATE public.products
    SET stock = stock + 1
    WHERE id = v_trx.product_id;

  ELSIF p_new_status = 'success' THEN
    UPDATE public.transactions
    SET
      status              = 'success',
      paid_at             = now(),
      verified_by         = 'manual',
      matched_mutation_id = COALESCE(p_mutation_id, matched_mutation_id)
    WHERE id = p_transaction_id
    RETURNING * INTO v_trx;

    IF p_mutation_id IS NOT NULL THEN
      UPDATE public.payment_mutations
      SET
        status         = 'matched',
        matched_trx_id = p_transaction_id,
        notes          = 'Dicocokkan manual oleh admin dengan transaksi #' || v_trx.trx_code
      WHERE id = p_mutation_id;
    END IF;
  END IF;

  RETURN v_trx;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_transaction_status(UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_transaction_status(UUID, TEXT, UUID) TO authenticated, service_role;

COMMIT;

