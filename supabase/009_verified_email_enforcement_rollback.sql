-- ==============================================================================
-- DigiQ Migration 009 ROLLBACK: Strict Verified Email Enforcement
-- File: supabase/009_verified_email_enforcement_rollback.sql
-- ==============================================================================

BEGIN;

-- 1. Hapus fungsi validasi email
DROP FUNCTION IF EXISTS public.validate_signup_email(TEXT);

-- 2. Hapus tabel pengaturan dan domain
DROP TABLE IF EXISTS public.email_security_settings CASCADE;
DROP TABLE IF EXISTS public.allowed_email_domains CASCADE;
DROP TABLE IF EXISTS public.blocked_email_domains CASCADE;

-- 3. Kembalikan create_purchase_transaction ke versi Migration 005 (tanpa cek is_email_verified)
CREATE OR REPLACE FUNCTION public.create_purchase_transaction(
  p_product_id    UUID,
  p_target_number TEXT
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        UUID;
  v_product        public.products%ROWTYPE;
  v_pending_count  INT;
  v_base_amount    NUMERIC;
  v_min            INT := 1;
  v_max            INT := 300;
  v_ttl_minutes    INT := 15;
  v_static_payload TEXT := '';
  v_unique_code    INT;
  v_total_amount   NUMERIC;
  v_trx_code       TEXT;
  v_trx            public.transactions%ROWTYPE;
  v_attempt        INT;
BEGIN
  PERFORM public.expire_pending_transactions();

  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Akses ditolak: pengguna belum login' USING ERRCODE = '42501';
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

  IF v_product.stock < 1 THEN
    RAISE EXCEPTION 'Stok produk habis' USING ERRCODE = 'P0001';
  END IF;

  v_base_amount := v_product.price;

  SELECT payload_string INTO v_static_payload
  FROM public.qris_static
  WHERE is_active = true
  LIMIT 1;

  IF v_static_payload IS NULL OR v_static_payload = '' THEN
    RAISE EXCEPTION 'Sistem QRIS belum dikonfigurasi oleh admin' USING ERRCODE = 'P0001';
  END IF;

  v_unique_code := NULL;
  FOR v_attempt IN 1..10 LOOP
    v_unique_code := floor(random() * (v_max - v_min + 1) + v_min)::INT;
    v_total_amount := v_base_amount + v_unique_code;

    PERFORM 1
    FROM public.transactions
    WHERE status = 'pending'
      AND total_amount = v_total_amount
      AND expired_at > now();

    IF NOT FOUND THEN
      EXIT;
    END IF;
    v_unique_code := NULL;
  END LOOP;

  IF v_unique_code IS NULL THEN
    RAISE EXCEPTION 'Antrean transaksi sedang padat. Silakan coba 1 menit lagi.' USING ERRCODE = 'P0001';
  END IF;

  v_trx_code := 'TRX-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(md5(random()::text), 1, 6));

  INSERT INTO public.transactions (
    trx_code,
    user_id,
    product_id,
    target_number,
    base_amount,
    unique_code,
    total_amount,
    status,
    expired_at,
    created_at
  ) VALUES (
    v_trx_code,
    v_user_id,
    p_product_id,
    p_target_number,
    v_base_amount,
    v_unique_code,
    v_total_amount,
    'pending',
    now() + (v_ttl_minutes || ' minutes')::INTERVAL,
    now()
  )
  RETURNING * INTO v_trx;

  UPDATE public.products
  SET stock = stock - 1,
      updated_at = now()
  WHERE id = p_product_id;

  RETURN v_trx;
END;
$$;

REVOKE ALL ON FUNCTION public.create_purchase_transaction(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_purchase_transaction(UUID, TEXT) TO authenticated, service_role;

-- 4. Hapus fungsi is_email_verified
DROP FUNCTION IF EXISTS public.is_email_verified();

COMMIT;

