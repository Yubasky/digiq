-- ==============================================================================
-- DigiQ Migration 012 Rollback
-- File: supabase/012_remove_aal2_from_purchase_rollback.sql
-- ==============================================================================

BEGIN;

-- Catatan: Rollback ini mengembalikan pengecekan is_2fa_enabled di create_purchase_transaction
-- jika sistem di masa mendatang memutuskan mengaktifkan MFA/TOTP kembali.

DROP FUNCTION IF EXISTS public.create_purchase_transaction(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.create_purchase_transaction(
  p_product_id    UUID,
  p_target_number TEXT DEFAULT ''
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        UUID;
  v_product        public.products%ROWTYPE;
  v_profile        public.profiles%ROWTYPE;
  v_base_amount    NUMERIC;
  v_unique_code    INT;
  v_total_amount   NUMERIC;
  v_trx_code       TEXT;
  v_ttl_minutes    INT;
  v_min            INT;
  v_max            INT;
  v_static_payload TEXT;
  v_pending_count  INT;
  v_trx            public.transactions%ROWTYPE;
  v_attempt        INT;
BEGIN
  PERFORM public.expire_pending_transactions();

  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Akses ditolak: pengguna belum login' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_email_verified() THEN
    RAISE EXCEPTION 'Akses ditolak: Email akun Anda belum diverifikasi. Silakan periksa inbox email Anda untuk memverifikasi akun.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_user_id;
  IF FOUND AND v_profile.is_2fa_enabled THEN
    IF COALESCE(auth.jwt()->>'aal', '') <> 'aal2' THEN
      RAISE EXCEPTION 'Aksi membutuhkan autentikasi dua faktor (AAL2)' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT COUNT(*) INTO v_pending_count
  FROM public.transactions
  WHERE user_id = v_user_id
    AND status = 'pending'
    AND now() <= (expired_at + INTERVAL '2 minutes');

  IF v_pending_count >= 3 THEN
    RAISE EXCEPTION 'Anda masih memiliki 3 transaksi yang belum dibayar. Selesaikan atau batalkan terlebih dahulu.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_product
  FROM public.products
  WHERE id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Produk tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_product.is_active THEN
    RAISE EXCEPTION 'Produk saat ini sedang tidak aktif' USING ERRCODE = 'P0001';
  END IF;

  IF v_product.stock <= 0 THEN
    RAISE EXCEPTION 'Stok produk telah habis' USING ERRCODE = 'P0001';
  END IF;

  IF v_product.discount_price IS NOT NULL AND v_product.discount_price > 0 THEN
    v_base_amount := v_product.discount_price;
  ELSE
    v_base_amount := v_product.price;
  END IF;

  SELECT COALESCE(NULLIF(value, '')::INT, 1) INTO v_min
  FROM public.app_settings WHERE key = 'unique_code_min';
  v_min := COALESCE(v_min, 1);

  SELECT COALESCE(NULLIF(value, '')::INT, 300) INTO v_max
  FROM public.app_settings WHERE key = 'unique_code_max';
  v_max := COALESCE(v_max, 300);

  SELECT COALESCE(NULLIF(value, '')::INT, 15) INTO v_ttl_minutes
  FROM public.app_settings WHERE key = 'pending_ttl_minutes';
  v_ttl_minutes := COALESCE(v_ttl_minutes, 15);

  SELECT COALESCE(value, '') INTO v_static_payload
  FROM public.app_settings WHERE key = 'qris_static_payload';

  FOR v_attempt IN 1..5 LOOP
    SELECT code INTO v_unique_code
    FROM generate_series(v_min, v_max) AS code
    WHERE NOT EXISTS (
      SELECT 1 FROM public.transactions
      WHERE status = 'pending'
        AND total_amount = (v_base_amount + code)
    )
    ORDER BY random()
    LIMIT 1;

    IF v_unique_code IS NULL THEN
      RAISE EXCEPTION 'Antrean pembayaran penuh, coba beberapa menit lagi' USING ERRCODE = 'P0001';
    END IF;

    v_total_amount := v_base_amount + v_unique_code;
    v_trx_code     := '#TRX-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(nextval('public.trx_seq')::text, 6, '0');

    BEGIN
      INSERT INTO public.transactions (
        trx_code,
        user_id,
        product_id,
        target_number,
        base_amount,
        unique_code,
        total_amount,
        amount,
        status,
        qris_payload,
        expired_at
      )
      VALUES (
        v_trx_code,
        v_user_id,
        p_product_id,
        p_target_number,
        v_base_amount,
        v_unique_code,
        v_total_amount,
        v_total_amount,
        'pending',
        v_static_payload,
        now() + (v_ttl_minutes || ' minutes')::interval
      )
      RETURNING * INTO v_trx;

      UPDATE public.products
      SET stock = stock - 1
      WHERE id = p_product_id;

      RETURN v_trx;
    EXCEPTION
      WHEN unique_violation THEN
        IF v_attempt = 5 THEN
          RAISE EXCEPTION 'Antrean pembayaran penuh, coba beberapa menit lagi' USING ERRCODE = 'P0001';
        END IF;
    END;
  END LOOP;

  RAISE EXCEPTION 'Antrean pembayaran penuh, coba beberapa menit lagi' USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.create_purchase_transaction(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_purchase_transaction(UUID, TEXT) TO authenticated, service_role;

COMMIT;

