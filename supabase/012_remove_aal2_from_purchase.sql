-- ==============================================================================
-- DigiQ Migration 012: Hapus Ketergantungan AAL2/2FA dari Pembuatan Transaksi
-- File: supabase/012_remove_aal2_from_purchase.sql
-- ==============================================================================
-- PENJELASAN ROOT CAUSE:
-- Transaksi pembelian gagal dengan error:
-- "PostgrestException(message: Aksi membutuhkan autentikasi dua faktor (AAL2), code: 42501)"
-- Karena akun user memiliki profiles.is_2fa_enabled = true di database, sementara
-- aplikasi Flutter DigiQ tidak lagi menggunakan MFA/AAL2 (sesi login adalah AAL1).
--
-- CATATAN PROTEKSI TRIGGER:
-- Trigger trg_protect_profile_sensitive_columns mengunci kolom is_2fa_enabled.
-- Kita mengaktifkan bypass lokal 'app.bypass_profile_lock' khusus untuk blok transaksi ini.
-- ==============================================================================

BEGIN;

-- 1. Aktifkan bypass proteksi kolom sensitif khusus di dalam sesi transaksi ini
SELECT set_config('app.bypass_profile_lock', 'on', true);

-- 2. Reset profil yang tersisa dengan flag is_2fa_enabled = true (aman via bypass di atas)
UPDATE public.profiles
SET is_2fa_enabled = false
WHERE is_2fa_enabled = true;

-- 3. Drop dan definisikan ulang create_purchase_transaction tanpa pengecekan AAL2
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
  -- 1. Jalankan lazy-expire transaksi pending yang telah kadaluarsa
  PERFORM public.expire_pending_transactions();

  -- 2. Validasi login pengguna
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Akses ditolak: pengguna belum login' USING ERRCODE = '42501';
  END IF;

  -- 3. Validasi status email terkonfirmasi (dari Migrasi 009)
  IF NOT public.is_email_verified() THEN
    RAISE EXCEPTION 'Akses ditolak: Email akun Anda belum diverifikasi. Silakan periksa inbox email Anda untuk memverifikasi akun.'
      USING ERRCODE = '42501';
  END IF;

  -- CATATAN PENTING:
  -- Pengecekan is_2fa_enabled dan auth.jwt()->>'aal' = 'aal2' telah DIHAPUS sepenuhnya di sini,
  -- sehingga akun dengan status apa pun tidak akan pernah diblokir AAL2 saat bertransaksi.

  -- 4. Anti-Spam: Maksimal 3 transaksi pending aktif per user
  SELECT COUNT(*) INTO v_pending_count
  FROM public.transactions
  WHERE user_id = v_user_id
    AND status = 'pending'
    AND now() <= (expired_at + INTERVAL '2 minutes');

  IF v_pending_count >= 3 THEN
    RAISE EXCEPTION 'Anda masih memiliki 3 transaksi yang belum dibayar. Selesaikan atau batalkan terlebih dahulu.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 5. Kunci baris produk & validasi stok
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

  -- 6. Hitung base_amount di sisi server (utamakan discount_price bila > 0)
  IF v_product.discount_price IS NOT NULL AND v_product.discount_price > 0 THEN
    v_base_amount := v_product.discount_price;
  ELSE
    v_base_amount := v_product.price;
  END IF;

  -- 7. Ambil konfigurasi QRIS & rentang kode unik dari app_settings
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

  -- 8. Loop retry maksimal 5 kali untuk alokasi kode unik anti-bentrok
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

      -- Potong stok tepat 1 unit HANYA setelah insert transaksi berhasil
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

COMMENT ON FUNCTION public.create_purchase_transaction(UUID, TEXT) IS
  'Membuat transaksi pembelian secara atomik dengan kode unik dinamis tanpa ketergantungan AAL2.';

COMMIT;
