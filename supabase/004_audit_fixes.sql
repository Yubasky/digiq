-- ============================================================
-- FILE: supabase/004_audit_fixes.sql
-- Proyek DigiQ: Perbaikan Audit Keamanan, AAL2 Admin, TRX Sequence, Idempotensi, & Stats RPC
-- Idempoten: Aman dijalankan berulang kali di Supabase SQL Editor
-- ============================================================

-- ┌────────────────────────────────────────────────────────┐
-- │  1. HELPER: admin_session_ok                           │
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

-- ┌────────────────────────────────────────────────────────┐
-- │  2. UPDATE POLICY RLS DENGAN admin_session_ok          │
-- └────────────────────────────────────────────────────────┘
DROP POLICY IF EXISTS "settings_write_admin_aal2" ON public.app_settings;
CREATE POLICY "settings_write_admin_aal2"
  ON public.app_settings FOR ALL TO authenticated
  USING (public.admin_session_ok())
  WITH CHECK (public.admin_session_ok());

DROP POLICY IF EXISTS "mutations_select_admin" ON public.payment_mutations;
CREATE POLICY "mutations_select_admin"
  ON public.payment_mutations FOR SELECT TO authenticated
  USING (public.admin_session_ok());

-- ┌────────────────────────────────────────────────────────┐
-- │  3. SEQUENCE TRX CODE                                  │
-- └────────────────────────────────────────────────────────┘
CREATE SEQUENCE IF NOT EXISTS public.trx_seq START 10000;

-- ┌────────────────────────────────────────────────────────┐
-- │  4. RPC: create_purchase_transaction                   │
-- │     Format trx_code: #TRX-YYYYMMDD-000001 (sequence)   │
-- └────────────────────────────────────────────────────────┘
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
  v_profile        public.profiles%ROWTYPE;
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
  -- 1. Jalankan lazy-expire terlebih dahulu
  PERFORM public.expire_pending_transactions();

  -- 2. Validasi autentikasi
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Akses ditolak: pengguna belum login' USING ERRCODE = '42501';
  END IF;

  -- 3. Cek profil dan proteksi 2FA jika diaktifkan oleh user
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

  -- 5. Lock baris produk untuk mencegah race condition stok
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

  -- 6. Baca konfigurasi QRIS dinamis dari app_settings
  SELECT COALESCE(NULLIF(value, '')::int, 1) INTO v_min
  FROM public.app_settings WHERE key = 'unique_code_min';

  SELECT COALESCE(NULLIF(value, '')::int, 300) INTO v_max
  FROM public.app_settings WHERE key = 'unique_code_max';

  SELECT COALESCE(NULLIF(value, '')::int, 15) INTO v_ttl_minutes
  FROM public.app_settings WHERE key = 'pending_ttl_minutes';

  SELECT COALESCE(value, '') INTO v_static_payload
  FROM public.app_settings WHERE key = 'qris_static_payload';

  -- 7. Loop retry maksimal 5 kali untuk memilih kode unik dan insert transaksi secara atomik
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
        -- Terjadi bentrok konkurensi, coba lagi di iterasi berikutnya
        IF v_attempt = 5 THEN
          RAISE EXCEPTION 'Antrean pembayaran penuh, coba beberapa menit lagi' USING ERRCODE = 'P0001';
        END IF;
    END;
  END LOOP;

  RAISE EXCEPTION 'Antrean pembayaran penuh, coba beberapa menit lagi' USING ERRCODE = 'P0001';
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  5. RPC: verify_payment_by_amount                      │
-- │     Fallback external_ref aman & cek admin_session_ok  │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.verify_payment_by_amount(
  p_amount       NUMERIC,
  p_source       TEXT DEFAULT 'webhook',
  p_external_ref TEXT DEFAULT '',
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

  -- 5. Cari transaksi pending dengan nominal total_amount EXACT dan waktu yang valid
  SELECT * INTO v_trx
  FROM public.transactions
  WHERE status = 'pending'
    AND total_amount = p_amount
    AND COALESCE(p_received_at, now()) >= (created_at - INTERVAL '1 minute')
    AND COALESCE(p_received_at, now()) <= (expired_at + INTERVAL '2 minutes')
  ORDER BY created_at ASC
  LIMIT 1
  FOR UPDATE;

  -- 6. Jika cocok: Tandai transaksi sukses & hubungkan dengan mutasi
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
      'status',         'matched',
      'mutation_id',    v_mutation.id,
      'matched_trx_id', v_trx.id,
      'trx_code',       v_trx.trx_code,
      'amount',         p_amount,
      'message',        'Pembayaran berhasil dicocokkan dengan transaksi #' || v_trx.trx_code
    );
  END IF;

  -- 7. Cek apakah cocok dengan transaksi yang baru saja kedaluwarsa (Late Payment)
  SELECT * INTO v_expired_trx
  FROM public.transactions
  WHERE status = 'failed'
    AND total_amount = p_amount
    AND created_at >= (now() - INTERVAL '24 hours')
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    v_notes := 'Uang masuk untuk transaksi kadaluarsa #' || v_expired_trx.trx_code || ' (perlu tindak lanjut admin)';
  ELSE
    v_notes := 'Tidak ditemukan transaksi pending dengan nominal pas Rp ' || p_amount::text;
  END IF;

  UPDATE public.payment_mutations
  SET notes = v_notes
  WHERE id = v_mutation.id;

  RETURN jsonb_build_object(
    'status',         'unmatched',
    'mutation_id',    v_mutation.id,
    'matched_trx_id', NULL,
    'notes',          v_notes,
    'message',        v_notes
  );
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  6. RPC: admin_update_transaction_status               │
-- │     Menggunakan admin_session_ok()                     │
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
    UPDATE public.transactions
    SET
      status      = 'failed',
      verified_by = 'admin'
    WHERE id = p_transaction_id
    RETURNING * INTO v_trx;

    -- Kembalikan stok produk +1
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

    -- Jika disertakan p_mutation_id, tautkan mutasi
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

-- ┌────────────────────────────────────────────────────────┐
-- │  7. RPC: admin_list_mutations                          │
-- │     Menggunakan admin_session_ok()                     │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.admin_list_mutations(
  p_limit          INT DEFAULT 50,
  p_offset         INT DEFAULT 0,
  p_unmatched_only BOOLEAN DEFAULT false
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
-- │  8. RPC: admin_today_stats                             │
-- │     Statistik riil hari ini (Asia/Jakarta)             │
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
