-- ==============================================================================
-- DigiQ Migration 009: Strict Verified Email Enforcement & Domain Filtering
-- File: supabase/009_verified_email_enforcement.sql
-- ==============================================================================
-- CATATAN KEAMANAN & ARSITEKTUR:
-- 1. File migrasi ini HANYA dibuat sebagai file lokal dan TIDAK dieksekusi otomatis ke live DB.
-- 2. Dijalankan melalui Supabase Dashboard > SQL Editor SETELAH membuat backup database.
-- 3. Fungsi create_purchase_transaction dibangun PERSIS di atas definisi LIVE (002)
--    dengan mempertahankan discount_price, cek AAL2 jika 2FA aktif, trx_seq ('#TRX-'),
--    kolom amount & qris_payload, serta retry loop anti-collision 1..5.
-- 4. SATU-SATUNYA penambahan pada create_purchase_transaction adalah verifikasi email:
--    IF NOT public.is_email_verified() THEN ...
-- 5. Tabel domain (blocked, allowed, settings) mengaktifkan RLS penuh dan tidak terbaca oleh anon.
-- ==============================================================================

BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Helper Function: public.is_email_verified()
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_email_verified()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_confirmed_at TIMESTAMPTZ;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT email_confirmed_at INTO v_confirmed_at
  FROM auth.users
  WHERE id = auth.uid();

  RETURN v_confirmed_at IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.is_email_verified() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_email_verified() TO authenticated, anon, service_role;

COMMENT ON FUNCTION public.is_email_verified() IS 
  'Memeriksa status email_confirmed_at pengguna aktif (auth.uid()) di auth.users.';

-- ------------------------------------------------------------------------------
-- 2. RPC: create_purchase_transaction
--    (Basis PERSIS definisi LIVE dengan HANYA penambahan pengecekan is_email_verified)
-- ------------------------------------------------------------------------------
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
  -- 1. Jalankan lazy-expire terlebih dahulu
  PERFORM public.expire_pending_transactions();

  -- 2. Validasi autentikasi
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Akses ditolak: pengguna belum login' USING ERRCODE = '42501';
  END IF;

  -- TAMBAHAN 009: Validasi status email terkonfirmasi
  IF NOT public.is_email_verified() THEN
    RAISE EXCEPTION 'Akses ditolak: Email akun Anda belum diverifikasi. Silakan periksa inbox email Anda untuk memverifikasi akun.'
      USING ERRCODE = '42501';
  END IF;

  -- 3. Cek profil dan proteksi 2FA jika diaktifkan
  SELECT * INTO v_profile FROM public.profiles WHERE id = v_user_id;
  IF FOUND AND v_profile.is_2fa_enabled THEN
    IF COALESCE(auth.jwt()->>'aal', '') <> 'aal2' THEN
      RAISE EXCEPTION 'Aksi membutuhkan autentikasi dua faktor (AAL2)' USING ERRCODE = '42501';
    END IF;
  END IF;

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

  -- 7. Ambil konfigurasi QRIS & rentang kode unik
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

  -- 8. Loop retry maksimal 5 kali untuk memilih kode unik dan insert transaksi secara atomik
  FOR v_attempt IN 1..5 LOOP
    -- Pilih kode unik acak yang total_amount (base + kode) belum ada di status pending
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
    -- Sequence TRX code: terurut, unik tanpa tabrakan birthday paradox
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
        -- Terjadi bentrok konkurensi (race condition), coba lagi di iterasi berikutnya
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

-- ------------------------------------------------------------------------------
-- 3. Tabel Filter Domain & Disposable Email (RLS Aktif, Tidak Terbaca Anon)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.blocked_email_domains (
  domain TEXT PRIMARY KEY,
  category TEXT NOT NULL DEFAULT 'disposable',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.blocked_email_domains ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.blocked_email_domains FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.blocked_email_domains TO service_role;

-- Starter pack domain disposable
INSERT INTO public.blocked_email_domains (domain, category) VALUES
  ('10minutemail.com', 'disposable'),
  ('10minutemail.net', 'disposable'),
  ('tempmail.com', 'disposable'),
  ('temp-mail.org', 'disposable'),
  ('guerrillamail.com', 'disposable'),
  ('guerrillamailblock.com', 'disposable'),
  ('sharklasers.com', 'disposable'),
  ('grr.la', 'disposable'),
  ('mailinator.com', 'disposable'),
  ('throwawaymail.com', 'disposable'),
  ('trashmail.com', 'disposable'),
  ('trashmail.net', 'disposable'),
  ('yopmail.com', 'disposable'),
  ('yopmail.fr', 'disposable'),
  ('dispostable.com', 'disposable'),
  ('getairmail.com', 'disposable'),
  ('mohmal.com', 'disposable'),
  ('crazymailing.com', 'disposable'),
  ('nada.ltd', 'disposable'),
  ('dropmail.me', 'disposable'),
  ('fakemailgenerator.com', 'disposable'),
  ('emailondeck.com', 'disposable'),
  ('mytemp.email', 'disposable'),
  ('inboxkitten.com', 'disposable'),
  ('burnermail.io', 'disposable'),
  ('generator.email', 'disposable'),
  ('guerrillamail.info', 'disposable'),
  ('guerrillamail.biz', 'disposable'),
  ('guerrillamail.de', 'disposable'),
  ('guerrillamail.net', 'disposable'),
  ('guerrillamail.org', 'disposable'),
  ('spam4.me', 'disposable'),
  ('tempr.email', 'disposable'),
  ('discard.email', 'disposable'),
  ('discardmail.com', 'disposable'),
  ('spambog.com', 'disposable'),
  ('mailcatch.com', 'disposable'),
  ('maildrop.cc', 'disposable'),
  ('mailnesia.com', 'disposable'),
  ('meltmail.com', 'disposable'),
  ('mintemail.com', 'disposable'),
  ('mytrashmail.com', 'disposable'),
  ('no-spam.ws', 'disposable'),
  ('oneoffmail.com', 'disposable'),
  ('owlymail.com', 'disposable'),
  ('pokemail.net', 'disposable'),
  ('trash-mail.com', 'disposable'),
  ('trashmail.me', 'disposable'),
  ('wegwerfmail.de', 'disposable'),
  ('wegwerfmail.net', 'disposable')
ON CONFLICT (domain) DO NOTHING;

-- Tabel whitelist domain
CREATE TABLE IF NOT EXISTS public.allowed_email_domains (
  domain TEXT PRIMARY KEY,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.allowed_email_domains ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.allowed_email_domains FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.allowed_email_domains TO service_role;

INSERT INTO public.allowed_email_domains (domain, is_active) VALUES
  ('gmail.com', true)
ON CONFLICT (domain) DO NOTHING;

-- Tabel pengaturan email security: default allow_plus_alias = true, enforce_domain_allowlist = false
CREATE TABLE IF NOT EXISTS public.email_security_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.email_security_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.email_security_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.email_security_settings TO service_role;

INSERT INTO public.email_security_settings (key, value, description) VALUES
  ('allow_plus_alias', 'true'::jsonb, 'Jika false, email format user+alias@gmail.com akan ditolak. Default: true.'),
  ('enforce_domain_allowlist', 'false'::jsonb, 'Jika true, hanya domain di public.allowed_email_domains yang diizinkan mendaftar. Default: false.')
ON CONFLICT (key) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 4. Fungsi Validasi Email Registrasi: validate_signup_email
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_signup_email(p_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean TEXT;
  v_domain TEXT;
  v_local TEXT;
  v_allow_plus BOOLEAN := true;
  v_enforce_allowlist BOOLEAN := false;
  v_is_blocked BOOLEAN := false;
  v_is_allowed BOOLEAN := false;
BEGIN
  v_clean := lower(trim(p_email));

  -- Format regex standar RFC 5322 ringkas
  IF v_clean IS NULL OR v_clean !~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' THEN
    RETURN jsonb_build_object('valid', false, 'error_code', 'INVALID_FORMAT', 'message', 'Format email tidak valid.');
  END IF;

  v_local := split_part(v_clean, '@', 1);
  v_domain := split_part(v_clean, '@', 2);

  -- Pengecekan plus alias (default: izinkan true)
  SELECT COALESCE((value)::boolean, true) INTO v_allow_plus
  FROM public.email_security_settings
  WHERE key = 'allow_plus_alias';

  IF v_allow_plus IS FALSE AND v_local LIKE '%+%' THEN
    RETURN jsonb_build_object('valid', false, 'error_code', 'PLUS_ALIAS_NOT_ALLOWED', 'message', 'Pendaftaran menggunakan alias plus (+) tidak diizinkan.');
  END IF;

  -- Pengecekan domain disposable / blacklist
  SELECT EXISTS(
    SELECT 1 FROM public.blocked_email_domains WHERE domain = v_domain
  ) INTO v_is_blocked;

  IF v_is_blocked THEN
    RETURN jsonb_build_object('valid', false, 'error_code', 'DISPOSABLE_DOMAIN', 'message', 'Domain email sementara/disposable tidak diizinkan. Gunakan email pribadi.');
  END IF;

  -- Pengecekan allowlist (default: false)
  SELECT COALESCE((value)::boolean, false) INTO v_enforce_allowlist
  FROM public.email_security_settings
  WHERE key = 'enforce_domain_allowlist';

  IF v_enforce_allowlist IS TRUE THEN
    SELECT EXISTS(
      SELECT 1 FROM public.allowed_email_domains WHERE domain = v_domain AND is_active = true
    ) INTO v_is_allowed;

    IF NOT v_is_allowed THEN
      RETURN jsonb_build_object('valid', false, 'error_code', 'DOMAIN_NOT_ALLOWED', 'message', 'Domain email tidak terdaftar dalam domain yang diizinkan.');
    END IF;
  END IF;

  RETURN jsonb_build_object('valid', true, 'domain', v_domain);
END;
$$;

REVOKE ALL ON FUNCTION public.validate_signup_email(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_signup_email(TEXT) TO anon, authenticated, service_role;

COMMIT;
