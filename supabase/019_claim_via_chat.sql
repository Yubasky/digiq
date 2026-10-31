-- ==============================================================================
-- DigiQ Migration 019: Fitur Klaim Produk Digital via Chat Admin
-- File: supabase/019_claim_via_chat.sql
-- ==============================================================================

BEGIN;

-- ┌────────────────────────────────────────────────────────┐
-- │  1. KOLOM KLAIM PADA TRANSACTIONS                      │
-- └────────────────────────────────────────────────────────┘
ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS claim_status TEXT NOT NULL DEFAULT 'none'
    CHECK (claim_status IN ('none', 'requested', 'delivered')),
  ADD COLUMN IF NOT EXISTS claim_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivered_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS claim_conversation_id UUID;

CREATE INDEX IF NOT EXISTS idx_transactions_claim_status
  ON public.transactions (claim_status) WHERE status = 'success';

-- ┌────────────────────────────────────────────────────────┐
-- │  2. KOLOM ADITIF PADA CHAT_MESSAGES                     │
-- └────────────────────────────────────────────────────────┘
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'text'
    CHECK (kind IN ('text', 'claim', 'system')),
  ADD COLUMN IF NOT EXISTS trx_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_chat_messages_kind
  ON public.chat_messages (kind);

CREATE INDEX IF NOT EXISTS idx_chat_messages_trx_id
  ON public.chat_messages (trx_id);

-- Perketat policy insert customer: pelanggan HANYA boleh menyisipkan kind='text'
DROP POLICY IF EXISTS "chat_insert_customer" ON public.chat_messages;
CREATE POLICY "chat_insert_customer"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    NOT public.is_admin()
    AND room_user_id = auth.uid()
    AND sender_id = auth.uid()
    AND kind = 'text'
  );

-- ┌────────────────────────────────────────────────────────┐
-- │  3. TABEL AUDIT: claim_events                          │
-- └────────────────────────────────────────────────────────┘
CREATE TABLE IF NOT EXISTS public.claim_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trx_id      UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
  actor_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  from_status TEXT NOT NULL,
  to_status   TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_claim_events_trx
  ON public.claim_events (trx_id, created_at DESC);

ALTER TABLE public.claim_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "claim_events_select_admin" ON public.claim_events;
CREATE POLICY "claim_events_select_admin"
  ON public.claim_events FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "claim_events_select_own" ON public.claim_events;
CREATE POLICY "claim_events_select_own"
  ON public.claim_events FOR SELECT TO authenticated
  USING (trx_id IN (SELECT id FROM public.transactions WHERE user_id = auth.uid()));

REVOKE INSERT, UPDATE, DELETE ON public.claim_events FROM authenticated;

-- ┌────────────────────────────────────────────────────────┐
-- │  4. TABEL RATE LIMIT KLAIM                             │
-- └────────────────────────────────────────────────────────┘
CREATE TABLE IF NOT EXISTS public.claim_rate_limits (
  user_id       UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  request_count INT NOT NULL DEFAULT 1,
  window_start  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.claim_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.claim_rate_limits FROM PUBLIC, authenticated;
GRANT ALL ON public.claim_rate_limits TO service_role;

-- ┌────────────────────────────────────────────────────────┐
-- │  5. TRIGGER PROTEKSI KOLOM SENSITIF KLAIM              │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.protect_transactions_claim_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  IF current_setting('digiq.in_claim_rpc', true) IS DISTINCT FROM 'true' THEN
    IF (NEW.claim_status IS DISTINCT FROM OLD.claim_status) OR
       (NEW.claim_requested_at IS DISTINCT FROM OLD.claim_requested_at) OR
       (NEW.delivered_at IS DISTINCT FROM OLD.delivered_at) OR
       (NEW.delivered_by IS DISTINCT FROM OLD.delivered_by) OR
       (NEW.claim_conversation_id IS DISTINCT FROM OLD.claim_conversation_id) THEN
      RAISE EXCEPTION 'Akses ditolak: kolom status klaim hanya dapat diubah melalui RPC resmi'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_transactions_claim ON public.transactions;
CREATE TRIGGER trg_protect_transactions_claim
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_transactions_claim_columns();

-- ┌────────────────────────────────────────────────────────┐
-- │  6. RPC: request_claim (Pelanggan)                     │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.request_claim(p_trx_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user_id       UUID;
  v_trx           public.transactions%ROWTYPE;
  v_product_name  TEXT;
  v_rl_count      INT;
  v_rl_start      TIMESTAMPTZ;
  v_paid_time     TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Akses ditolak: pengguna belum terautentikasi' USING ERRCODE = '42501';
  END IF;

  -- 1. Rate Limiting: Maksimal 10 panggilan per menit
  SELECT request_count, window_start INTO v_rl_count, v_rl_start
  FROM public.claim_rate_limits
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.claim_rate_limits (user_id, request_count, window_start)
    VALUES (v_user_id, 1, now());
  ELSIF now() - v_rl_start > INTERVAL '1 minute' THEN
    UPDATE public.claim_rate_limits
    SET request_count = 1, window_start = now()
    WHERE user_id = v_user_id;
  ELSE
    IF v_rl_count >= 10 THEN
      RAISE EXCEPTION 'Batas frekuensi klaim terlampaui. Mohon tunggu 1 menit.' USING ERRCODE = '42901';
    END IF;
    UPDATE public.claim_rate_limits
    SET request_count = request_count + 1
    WHERE user_id = v_user_id;
  END IF;

  -- 2. Lock baris transaksi
  SELECT * INTO v_trx
  FROM public.transactions
  WHERE id = p_trx_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Akses ditolak: transaksi tidak ditemukan' USING ERRCODE = '42501';
  END IF;

  -- 3. Verifikasi kepemilikan dan status lunas
  IF v_trx.user_id <> v_user_id THEN
    RAISE EXCEPTION 'Akses ditolak: Anda bukan pemilik transaksi ini' USING ERRCODE = '42501';
  END IF;

  IF v_trx.status <> 'success' THEN
    RAISE EXCEPTION 'Akses ditolak: transaksi belum berstatus lunas' USING ERRCODE = '42501';
  END IF;

  -- 4. Idempotensi: Jika sudah 'requested' atau 'delivered', jangan buat pesan baru
  IF v_trx.claim_status IN ('requested', 'delivered') THEN
    RETURN jsonb_build_object(
      'success', true,
      'conversation_id', v_trx.user_id,
      'claim_status', v_trx.claim_status,
      'trx_code', v_trx.trx_code,
      'already_requested', true
    );
  END IF;

  -- 5. Ambil nama produk
  SELECT name INTO v_product_name FROM public.products WHERE id = v_trx.product_id;

  -- 6. Update status transaksi via RPC flag
  PERFORM set_config('digiq.in_claim_rpc', 'true', true);

  UPDATE public.transactions
  SET
    claim_status = 'requested',
    claim_requested_at = now(),
    claim_conversation_id = v_trx.user_id
  WHERE id = p_trx_id
  RETURNING * INTO v_trx;

  PERFORM set_config('digiq.in_claim_rpc', 'false', true);

  -- 7. Audit log event
  INSERT INTO public.claim_events (trx_id, actor_id, from_status, to_status)
  VALUES (p_trx_id, v_user_id, 'none', 'requested');

  -- 8. Format waktu bayar & sisipkan pesan sistem (kind='claim')
  v_paid_time := to_char(COALESCE(v_trx.paid_at, now()) AT TIME ZONE 'Asia/Jakarta', 'DD/MM/YYYY HH24:MI WIB');

  INSERT INTO public.chat_messages (
    sender_id,
    receiver_id,
    room_user_id,
    message,
    kind,
    trx_id
  )
  VALUES (
    v_user_id,
    NULL,
    v_user_id,
    'Halo Admin, saya ingin klaim pesanan #' || v_trx.trx_code || ' (' || COALESCE(v_product_name, 'Produk') || ') senilai Rp ' || to_char(v_trx.total_amount, 'FM999,999,999') || ' (Lunas: ' || v_paid_time || '). Mohon diproses.',
    'claim',
    p_trx_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'conversation_id', v_trx.user_id,
    'claim_status', 'requested',
    'trx_code', v_trx.trx_code,
    'already_requested', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_claim(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_claim(UUID) TO authenticated, service_role;

-- ┌────────────────────────────────────────────────────────┐
-- │  7. RPC: admin_mark_delivered (Admin)                  │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.admin_mark_delivered(p_trx_id UUID)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_trx           public.transactions%ROWTYPE;
  v_old_status    TEXT;
  v_product_name  TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Akses ditolak: hanya admin yang dapat menandai pesanan terkirim'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_trx
  FROM public.transactions
  WHERE id = p_trx_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaksi tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  IF v_trx.status <> 'success' THEN
    RAISE EXCEPTION 'Transaksi belum lunas' USING ERRCODE = 'P0001';
  END IF;

  v_old_status := v_trx.claim_status;
  IF v_old_status = 'delivered' THEN
    RETURN v_trx;
  END IF;

  PERFORM set_config('digiq.in_claim_rpc', 'true', true);

  UPDATE public.transactions
  SET
    claim_status = 'delivered',
    delivered_at = now(),
    delivered_by = auth.uid()
  WHERE id = p_trx_id
  RETURNING * INTO v_trx;

  PERFORM set_config('digiq.in_claim_rpc', 'false', true);

  INSERT INTO public.claim_events (trx_id, actor_id, from_status, to_status)
  VALUES (p_trx_id, auth.uid(), v_old_status, 'delivered');

  SELECT name INTO v_product_name FROM public.products WHERE id = v_trx.product_id;

  INSERT INTO public.chat_messages (
    sender_id,
    receiver_id,
    room_user_id,
    message,
    kind,
    trx_id
  )
  VALUES (
    auth.uid(),
    v_trx.user_id,
    v_trx.user_id,
    'Pesanan #' || v_trx.trx_code || ' (' || COALESCE(v_product_name, 'Produk') || ') telah ditandai TERKIRIM oleh admin. Terima kasih telah berbelanja di DigiQ!',
    'system',
    p_trx_id
  );

  RETURN v_trx;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mark_delivered(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mark_delivered(UUID) TO authenticated, service_role;

-- ┌────────────────────────────────────────────────────────┐
-- │  8. RPC: get_admin_pending_claims (Admin Queue)        │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.get_admin_pending_claims()
RETURNS TABLE (
  trx_id              UUID,
  trx_code            TEXT,
  user_id             UUID,
  customer_name       TEXT,
  product_id          UUID,
  product_name        TEXT,
  base_amount         NUMERIC,
  unique_code         INT,
  total_amount        NUMERIC,
  target_number       TEXT,
  paid_at             TIMESTAMPTZ,
  claim_requested_at  TIMESTAMPTZ,
  claim_status        TEXT,
  conversation_id     UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Akses ditolak: hanya admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    t.id AS trx_id,
    t.trx_code,
    t.user_id,
    COALESCE(p.full_name, 'Pelanggan') AS customer_name,
    t.product_id,
    COALESCE(pr.name, 'Produk') AS product_name,
    t.base_amount,
    t.unique_code,
    t.total_amount,
    t.target_number,
    t.paid_at,
    t.claim_requested_at,
    t.claim_status,
    t.user_id AS conversation_id
  FROM public.transactions t
  LEFT JOIN public.profiles p ON p.id = t.user_id
  LEFT JOIN public.products pr ON pr.id = t.product_id
  WHERE t.status = 'success'
    AND t.claim_status = 'requested'
  ORDER BY t.claim_requested_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_admin_pending_claims() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_pending_claims() TO authenticated, service_role;

COMMIT;

