-- ============================================================
-- FILE: supabase/002_qris_unique_code.sql
-- Proyek DigiQ: Pembayaran QRIS Statis + Kode Unik Otomatis
-- Idempoten: Aman dijalankan berulang kali di Supabase SQL Editor
-- ============================================================

-- ┌────────────────────────────────────────────────────────┐
-- │  1. PERUBAHAN SKEMA: Tabel transactions                │
-- └────────────────────────────────────────────────────────┘

-- Tambah kolom baru jika belum ada
ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS base_amount         NUMERIC,
  ADD COLUMN IF NOT EXISTS unique_code         INT,
  ADD COLUMN IF NOT EXISTS total_amount        NUMERIC,
  ADD COLUMN IF NOT EXISTS paid_at             TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verified_by         TEXT,
  ADD COLUMN IF NOT EXISTS matched_mutation_id  UUID;

-- Tangani konversi tipe verified_by jika sebelumnya bertipe UUID
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'transactions'
      AND column_name = 'verified_by'
      AND data_type <> 'text'
  ) THEN
    ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_verified_by_fkey;
    ALTER TABLE public.transactions ALTER COLUMN verified_by TYPE TEXT USING verified_by::TEXT;
  END IF;
END $$;

-- Pastikan constraint check pada verified_by sesuai spesifikasi
ALTER TABLE public.transactions
  DROP CONSTRAINT IF EXISTS transactions_verified_by_check;

ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_verified_by_check
  CHECK (verified_by IS NULL OR verified_by IN ('auto', 'manual', 'webhook'));

-- Back-fill baris lama agar kolom NOT NULL terpenuhi
UPDATE public.transactions
SET
  base_amount  = COALESCE(base_amount, amount, 0),
  unique_code  = COALESCE(NULLIF(unique_code, 0), 1),
  total_amount = COALESCE(total_amount, amount, 0),
  amount       = COALESCE(total_amount, amount, 0)
WHERE base_amount IS NULL OR unique_code IS NULL OR total_amount IS NULL OR unique_code = 0;

-- Terapkan NOT NULL & CHECK pada unique_code
ALTER TABLE public.transactions
  DROP CONSTRAINT IF EXISTS transactions_unique_code_check;

ALTER TABLE public.transactions
  ALTER COLUMN base_amount  SET NOT NULL,
  ALTER COLUMN unique_code  SET NOT NULL,
  ALTER COLUMN total_amount SET NOT NULL,
  ADD CONSTRAINT transactions_unique_code_check CHECK (unique_code BETWEEN 1 AND 300);

-- Sinkronisasi kolom amount lama agar nilainya = total_amount (kompatibel ke belakang)
UPDATE public.transactions
SET amount = total_amount
WHERE amount <> total_amount;

-- ┌────────────────────────────────────────────────────────┐
-- │  2. PARTIAL UNIQUE INDEX: total_amount per pending     │
-- │     Menjamin tidak ada 2 pending dengan total_amount   │
-- │     yang sama pada waktu bersamaan di seluruh produk   │
-- └────────────────────────────────────────────────────────┘
DROP INDEX IF EXISTS public.trx_pending_total_unique;
CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_pending_total_amount
  ON public.transactions(total_amount)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_transactions_expired_pending
  ON public.transactions(expired_at)
  WHERE status = 'pending';

-- ┌────────────────────────────────────────────────────────┐
-- │  3. TABEL: app_settings                                │
-- └────────────────────────────────────────────────────────┘
CREATE TABLE IF NOT EXISTS public.app_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- ┌────────────────────────────────────────────────────────┐
-- │  3b. HELPER: admin_session_ok                          │
-- │     Verifikasi apakah pemanggil adalah Admin dan AAL2  │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.admin_session_ok()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  -- HANYA UNTUK DEVELOPMENT, KEMBALIKAN SEBELUM RILIS:
  -- RETURN public.is_admin();
  RETURN public.is_admin() AND COALESCE(auth.jwt() ->> 'aal', '') = 'aal2';
END;
$$;

DROP POLICY IF EXISTS "settings_select" ON public.app_settings;
DROP POLICY IF EXISTS "settings_write_admin_aal2" ON public.app_settings;
DROP POLICY IF EXISTS "settings_select_admin" ON public.app_settings;
DROP POLICY IF EXISTS "settings_all_admin" ON public.app_settings;

-- RLS: SELECT untuk semua user authenticated
CREATE POLICY "settings_select"
  ON public.app_settings FOR SELECT TO authenticated
  USING (true);

-- RLS: INSERT/UPDATE/DELETE hanya admin dengan AAL2
CREATE POLICY "settings_write_admin_aal2"
  ON public.app_settings FOR ALL TO authenticated
  USING (public.admin_session_ok())
  WITH CHECK (public.admin_session_ok());

-- Seed awal konfigurasi QRIS proyek (kopi sat - NMID: ID1026516422080)
INSERT INTO public.app_settings (key, value) VALUES
  ('qris_static_payload', '00020101021126570011ID.DANA.WWW011893600915302435049402090243504940303UMI51440014ID.CO.QRIS.WWW0215ID10265164220800303UMI5204581353033605802ID5908kopi sat6015Kab. Nanggroe A6105245526304F95A'),
  ('qris_merchant_name', 'kopi sat'),
  ('qris_nmid', 'ID1026516422080'),
  ('unique_code_min', '1'),
  ('unique_code_max', '300'),
  ('pending_ttl_minutes', '15')
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value, updated_at = now()
WHERE app_settings.value IS NULL OR app_settings.value = '';

-- ┌────────────────────────────────────────────────────────┐
-- │  4. TABEL: payment_mutations                           │
-- └────────────────────────────────────────────────────────┘
CREATE TABLE IF NOT EXISTS public.payment_mutations (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source         TEXT NOT NULL,
  external_ref   TEXT NOT NULL,
  amount         NUMERIC NOT NULL,
  received_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw            JSONB DEFAULT '{}'::jsonb,
  status         TEXT NOT NULL CHECK (status IN ('unmatched', 'matched', 'ignored')),
  matched_trx_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
  notes          TEXT,
  created_at     TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT payment_mutations_source_ref_unique UNIQUE (source, external_ref)
);

ALTER TABLE public.payment_mutations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mutations_select_admin" ON public.payment_mutations;
DROP POLICY IF EXISTS "mutations_insert_admin" ON public.payment_mutations;

-- RLS: Hanya admin dengan AAL2 yang bisa SELECT
CREATE POLICY "mutations_select_admin"
  ON public.payment_mutations FOR SELECT TO authenticated
  USING (public.admin_session_ok());

-- Tidak ada policy INSERT/UPDATE/DELETE langsung dari klien; semua melalui RPC SECURITY DEFINER.

-- ┌────────────────────────────────────────────────────────┐
-- │  5. HELPER: expire_pending_transactions                │
-- │     Kedaluwarsa transaksi setelah grace period 2 menit │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.expire_pending_transactions()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT := 0;
  v_rec   RECORD;
BEGIN
  -- Batalkan transaksi pending yang expired_at-nya sudah lewat masa grace period 2 menit
  FOR v_rec IN
    SELECT id, product_id FROM public.transactions
    WHERE status = 'pending'
      AND now() > (expired_at + INTERVAL '2 minutes')
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.transactions
    SET status = 'failed'
    WHERE id = v_rec.id;

    -- Kembalikan stok produk +1 tepat satu kali
    UPDATE public.products
    SET stock = stock + 1
    WHERE id = v_rec.product_id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  6. RPC: create_purchase_transaction                   │
-- │     Atomic: Lazy expire, anti-spam, retry kode unik,   │
-- │     dan potong stok                                    │
-- └────────────────────────────────────────────────────────┘
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

-- ┌────────────────────────────────────────────────────────┐
-- │  7. RPC: cancel_my_pending_transaction                 │
-- │     Customer membatalkan transaksinya sendiri,         │
-- │     stok produk dikembalikan +1                        │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.cancel_my_pending_transaction(
  p_transaction_id UUID
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_trx     public.transactions%ROWTYPE;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Akses ditolak: pengguna belum login' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_trx
  FROM public.transactions
  WHERE id = p_transaction_id
    AND user_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaksi tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  IF v_trx.status <> 'pending' THEN
    RAISE EXCEPTION 'Hanya transaksi berstatus pending yang dapat dibatalkan' USING ERRCODE = 'P0001';
  END IF;

  -- Kembalikan stok produk +1
  UPDATE public.products
  SET stock = stock + 1
  WHERE id = v_trx.product_id;

  -- Ubah status transaksi menjadi failed
  UPDATE public.transactions
  SET status = 'failed'
  WHERE id = p_transaction_id
  RETURNING * INTO v_trx;

  RETURN v_trx;
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  8. RPC: verify_payment_by_amount                      │
-- │     Otorisasi: service_role ATAU admin + aal2          │
-- │     Mencocokkan pembayaran nominal exact               │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.verify_payment_by_amount(
  p_amount       NUMERIC,
  p_source       TEXT,
  p_external_ref TEXT,
  p_received_at  TIMESTAMPTZ DEFAULT now(),
  p_raw          JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_service_role BOOLEAN;
  v_is_admin_aal2   BOOLEAN;
  v_external_ref    TEXT;
  v_mutation        public.payment_mutations%ROWTYPE;
  v_trx             public.transactions%ROWTYPE;
  v_expired_trx     public.transactions%ROWTYPE;
  v_notes           TEXT;
  v_verified_by_val TEXT;
BEGIN
  -- 1. Verifikasi Otorisasi: service_role ATAU admin_session_ok()
  v_is_service_role := (auth.role() = 'service_role');
  v_is_admin_aal2   := public.admin_session_ok();

  IF NOT (v_is_service_role OR v_is_admin_aal2) THEN
    RAISE EXCEPTION 'Akses ditolak: fungsi ini membutuhkan izin service_role atau admin AAL2'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Bersihkan transaksi kedaluwarsa
  PERFORM public.expire_pending_transactions();

  -- 3. Fallback external_ref: jika kosong, generate MAN-UUID agar tidak tabrakan di (source, external_ref)
  v_external_ref := COALESCE(NULLIF(btrim(p_external_ref), ''), 'MAN-' || gen_random_uuid()::text);

  -- 4. Idempoten: Simpan mutasi ke payment_mutations (ON CONFLICT DO NOTHING)
  INSERT INTO public.payment_mutations (
    source,
    external_ref,
    amount,
    received_at,
    raw,
    status,
    notes
  )
  VALUES (
    p_source,
    v_external_ref,
    p_amount,
    COALESCE(p_received_at, now()),
    p_raw,
    'unmatched',
    NULL
  )
  ON CONFLICT (source, external_ref) DO NOTHING
  RETURNING * INTO v_mutation;

  -- Jika sudah ada mutasi dengan (source, external_ref) yang sama, kembalikan status sebelumnya
  IF v_mutation.id IS NULL THEN
    SELECT * INTO v_mutation
    FROM public.payment_mutations
    WHERE source = p_source AND external_ref = v_external_ref;

    RETURN jsonb_build_object(
      'status',         'already_processed',
      'mutation_id',    v_mutation.id,
      'matched_trx_id', v_mutation.matched_trx_id,
      'message',        'Mutasi ini sudah pernah diproses sebelumnya (idempoten).'
    );
  END IF;

  -- 4. Cari transaksi pending dengan nominal total_amount EXACT dan waktu yang valid:
  --    p_received_at >= (created_at - 1 menit) AND p_received_at <= (expired_at + 2 menit grace period)
  SELECT * INTO v_trx
  FROM public.transactions
  WHERE status = 'pending'
    AND total_amount = p_amount
    AND COALESCE(p_received_at, now()) >= (created_at - INTERVAL '1 minute')
    AND COALESCE(p_received_at, now()) <= (expired_at + INTERVAL '2 minutes')
  ORDER BY created_at ASC
  LIMIT 1
  FOR UPDATE;

  -- 5. Jika cocok: Tandai transaksi sukses & hubungkan dengan mutasi
  IF FOUND THEN
    v_verified_by_val := CASE
      WHEN p_source = 'manual' THEN 'manual'
      WHEN p_source = 'webhook' THEN 'webhook'
      ELSE 'auto'
    END;

    UPDATE public.transactions
    SET
      status              = 'success',
      paid_at             = COALESCE(p_received_at, now()),
      verified_by         = v_verified_by_val,
      matched_mutation_id = v_mutation.id
    WHERE id = v_trx.id;

    UPDATE public.payment_mutations
    SET
      status         = 'matched',
      matched_trx_id = v_trx.id,
      notes          = 'Cocok otomatis dengan transaksi #' || v_trx.trx_code
    WHERE id = v_mutation.id;

    RETURN jsonb_build_object(
      'status',       'matched',
      'mutation_id',  v_mutation.id,
      'trx_id',       v_trx.id,
      'trx_code',     v_trx.trx_code,
      'user_id',      v_trx.user_id,
      'total_amount', v_trx.total_amount,
      'verified_by',  v_verified_by_val
    );
  END IF;

  -- 6. Jika tidak cocok: Cek apakah nominal cocok dengan transaksi yang baru saja expired/failed
  SELECT * INTO v_expired_trx
  FROM public.transactions
  WHERE total_amount = p_amount
    AND status IN ('failed', 'expired')
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    v_notes := 'Nominal cocok dengan transaksi kedaluwarsa #' || v_expired_trx.trx_code || ', butuh keputusan admin';
  ELSE
    v_notes := 'Tidak ada transaksi pending dengan nominal ini';
  END IF;

  UPDATE public.payment_mutations
  SET notes = v_notes
  WHERE id = v_mutation.id;

  RETURN jsonb_build_object(
    'status',      'unmatched',
    'mutation_id', v_mutation.id,
    'message',     v_notes
  );
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  9. RPC: admin_update_transaction_status               │
-- │     Wajib admin + aal2. Transaksi final tidak diubah.  │
-- │     Jika failed -> restore stok +1.                    │
-- │     Jika success -> verified_by 'manual' & hubungkan   │
-- │     p_mutation_id jika diberikan.                      │
-- └────────────────────────────────────────────────────────┘
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
  -- Validasi Admin + AAL2 via admin_session_ok()
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

  -- Transaksi final tidak boleh diubah lagi
  IF v_trx.status IN ('success', 'failed') THEN
    RAISE EXCEPTION 'Transaksi sudah final (%) dan tidak dapat diubah lagi', v_trx.status
      USING ERRCODE = 'P0001';
  END IF;

  IF p_new_status = 'failed' THEN
    -- Kembalikan stok +1 tepat satu kali
    UPDATE public.products
    SET stock = stock + 1
    WHERE id = v_trx.product_id;

    UPDATE public.transactions
    SET status = 'failed'
    WHERE id = p_transaction_id
    RETURNING * INTO v_trx;

  ELSIF p_new_status = 'success' THEN
    UPDATE public.transactions
    SET
      status              = 'success',
      paid_at             = COALESCE(paid_at, now()),
      verified_by         = 'manual',
      matched_mutation_id = COALESCE(p_mutation_id, matched_mutation_id)
    WHERE id = p_transaction_id
    RETURNING * INTO v_trx;

    -- Bila p_mutation_id diberikan, update mutasi terkait
    IF p_mutation_id IS NOT NULL THEN
      UPDATE public.payment_mutations
      SET
        status         = 'matched',
        matched_trx_id = p_transaction_id,
        notes          = COALESCE(notes || ' | ', '') || 'Diverifikasi & disetujui manual oleh admin'
      WHERE id = p_mutation_id;
    END IF;
  END IF;

  RETURN v_trx;
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  10. RPC: get_qris_settings                            │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.get_qris_settings()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT jsonb_object_agg(key, value)
  FROM public.app_settings
  WHERE key IN (
    'qris_static_payload',
    'qris_merchant_name',
    'qris_nmid',
    'unique_code_min',
    'unique_code_max',
    'pending_ttl_minutes'
  );
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  11. RPC: admin_list_mutations                         │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.admin_list_mutations(
  p_unmatched_only BOOLEAN DEFAULT false,
  p_limit          INT     DEFAULT 50,
  p_offset         INT     DEFAULT 0
)
RETURNS TABLE (
  id             UUID,
  source         TEXT,
  external_ref   TEXT,
  amount         NUMERIC,
  received_at    TIMESTAMPTZ,
  raw            JSONB,
  status         TEXT,
  matched_trx_id UUID,
  trx_code       TEXT,
  notes          TEXT,
  created_at     TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT public.admin_session_ok() THEN
    RAISE EXCEPTION 'Akses ditolak: hanya admin AAL2' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    pm.id,
    pm.source,
    pm.external_ref,
    pm.amount,
    pm.received_at,
    pm.raw,
    pm.status,
    pm.matched_trx_id,
    t.trx_code,
    pm.notes,
    pm.created_at
  FROM public.payment_mutations pm
  LEFT JOIN public.transactions t ON t.id = pm.matched_trx_id
  WHERE (NOT p_unmatched_only OR pm.status = 'unmatched')
  ORDER BY pm.received_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  12. JADWAL CRON OTOMATIS (Bila pg_cron tersedia)      │
-- └────────────────────────────────────────────────────────┘
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('digiq_expire_pending_transactions');
    PERFORM cron.schedule(
      'digiq_expire_pending_transactions',
      '*/2 * * * *',
      'SELECT public.expire_pending_transactions()'
    );
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    NULL; -- Abaikan jika pg_cron belum diaktifkan di dashboard
END $$;

-- ┌────────────────────────────────────────────────────────┐
-- │  13. GRANT PERMISSIONS                                 │
-- └────────────────────────────────────────────────────────┘
GRANT EXECUTE ON FUNCTION public.expire_pending_transactions()                     TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_purchase_transaction(UUID, TEXT)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_my_pending_transaction(UUID)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_payment_by_amount(NUMERIC, TEXT, TEXT, TIMESTAMPTZ, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_update_transaction_status(UUID, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_qris_settings()                               TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_mutations(BOOLEAN, INT, INT)           TO authenticated;

-- ┌────────────────────────────────────────────────────────┐
-- │  14. RPC: admin_today_stats                            │
-- │      Statistik riil hari ini (Asia/Jakarta)            │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.admin_today_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_today_start TIMESTAMPTZ;
  v_today_end   TIMESTAMPTZ;
  v_omset       NUMERIC := 0;
  v_success_cnt INT := 0;
  v_pending_cnt INT := 0;
  v_total_cnt   INT := 0;
BEGIN
  IF NOT public.admin_session_ok() THEN
    RAISE EXCEPTION 'Akses ditolak: fungsi ini membutuhkan izin admin AAL2'
      USING ERRCODE = '42501';
  END IF;

  -- Rentang hari ini berdasarkan zona waktu Asia/Jakarta (WIB)
  v_today_start := date_trunc('day', now() AT TIME ZONE 'Asia/Jakarta') AT TIME ZONE 'Asia/Jakarta';
  v_today_end   := v_today_start + INTERVAL '1 day';

  -- Omset dan jumlah transaksi sukses yang dibuat hari ini
  SELECT
    COALESCE(SUM(total_amount), 0),
    COUNT(*)
  INTO v_omset, v_success_cnt
  FROM public.transactions
  WHERE status = 'success'
    AND created_at >= v_today_start
    AND created_at < v_today_end;

  -- Transaksi pending aktif saat ini
  SELECT COUNT(*)
  INTO v_pending_cnt
  FROM public.transactions
  WHERE status = 'pending'
    AND expired_at > now();

  -- Total semua transaksi hari ini
  SELECT COUNT(*)
  INTO v_total_cnt
  FROM public.transactions
  WHERE created_at >= v_today_start
    AND created_at < v_today_end;

  RETURN jsonb_build_object(
    'omset', v_omset,
    'success_count', v_success_cnt,
    'pending_count', v_pending_cnt,
    'total_count', v_total_cnt
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_today_stats() TO authenticated;
