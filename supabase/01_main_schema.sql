-- ============================================================
-- FILE 1: SKEMA UTAMA, TABEL, RLS & FUNGSI (RPC)
-- Jalankan file ini PERTAMA di Supabase SQL Editor
-- ============================================================

-- ┌────────────────────────────────────────────────────────┐
-- │  1. EXTENSIONS                                         │
-- └────────────────────────────────────────────────────────┘
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "pg_cron" SCHEMA extensions;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Extension pg_cron dilewati (opsional)';
END;
$$;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ┌────────────────────────────────────────────────────────┐
-- │  2. SEQUENCE: kode transaksi                           │
-- └────────────────────────────────────────────────────────┘
CREATE SEQUENCE IF NOT EXISTS trx_seq START 10000;

-- ┌────────────────────────────────────────────────────────┐
-- │  3. HELPER: set_updated_at trigger                     │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  4. TABEL: profiles                                    │
-- └────────────────────────────────────────────────────────┘
CREATE TABLE IF NOT EXISTS public.profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name       TEXT NOT NULL DEFAULT '',
  phone           TEXT NOT NULL DEFAULT '',
  avatar_url      TEXT,
  role            TEXT NOT NULL DEFAULT 'customer'
                    CHECK (role IN ('customer', 'admin')),
  balance         NUMERIC(15, 2) NOT NULL DEFAULT 0
                    CHECK (balance >= 0),
  is_2fa_enabled  BOOLEAN NOT NULL DEFAULT false,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS profiles_role_idx ON public.profiles (role);

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Trigger otomatis saat user baru register via Auth
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, phone, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    'customer'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (full_name, phone, avatar_url) ON public.profiles TO authenticated;

-- ┌────────────────────────────────────────────────────────┐
-- │  5. HELPER: is_admin()                                 │
-- └────────────────────────────────────────────────────────┘
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
  );
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  6. TABEL: products                                    │
-- └────────────────────────────────────────────────────────┘
CREATE TABLE IF NOT EXISTS public.products (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT NOT NULL,
  category       TEXT NOT NULL
                   CHECK (category IN ('Pulsa', 'PLN', 'Games', 'E-Wallet', 'Streaming')),
  description    TEXT NOT NULL DEFAULT '',
  price          NUMERIC(15, 2) NOT NULL CHECK (price >= 0),
  discount_price NUMERIC(15, 2) CHECK (discount_price < price),
  stock          INT NOT NULL DEFAULT 0 CHECK (stock >= 0),
  is_active      BOOLEAN NOT NULL DEFAULT true,
  image_url      TEXT,
  provider       TEXT NOT NULL DEFAULT '',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS products_category_active_idx
  ON public.products (category, is_active);

-- ┌────────────────────────────────────────────────────────┐
-- │  7. TABEL: transactions                                │
-- └────────────────────────────────────────────────────────┘
CREATE TABLE IF NOT EXISTS public.transactions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trx_code      TEXT NOT NULL UNIQUE DEFAULT ('#TRX-' || nextval('trx_seq')),
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  product_id    UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  target_number TEXT NOT NULL DEFAULT '',
  amount        NUMERIC(15, 2) NOT NULL CHECK (amount >= 0),
  status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'success', 'failed')),
  qris_payload  TEXT,
  expired_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS trx_user_created_idx
  ON public.transactions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS trx_status_idx
  ON public.transactions (status);

REVOKE INSERT, UPDATE, DELETE ON public.transactions FROM authenticated;

-- ┌────────────────────────────────────────────────────────┐
-- │  8. TABEL: chat_messages                               │
-- └────────────────────────────────────────────────────────┘
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  receiver_id  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  room_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  message      TEXT NOT NULL CHECK (char_length(message) BETWEEN 1 AND 1000),
  is_read      BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS chat_room_created_idx
  ON public.chat_messages (room_user_id, created_at ASC);

-- ┌────────────────────────────────────────────────────────┐
-- │  9. ROW LEVEL SECURITY (RLS)                           │
-- └────────────────────────────────────────────────────────┘
ALTER TABLE public.profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- Policy profiles
DROP POLICY IF EXISTS "profiles_select_own"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"   ON public.profiles;

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT TO authenticated
  USING (id = auth.uid());

CREATE POLICY "profiles_select_admin"
  ON public.profiles FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Policy products
DROP POLICY IF EXISTS "products_select_customer" ON public.products;
DROP POLICY IF EXISTS "products_select_admin"    ON public.products;
DROP POLICY IF EXISTS "products_insert_admin"    ON public.products;
DROP POLICY IF EXISTS "products_update_admin"    ON public.products;
DROP POLICY IF EXISTS "products_delete_admin"    ON public.products;

CREATE POLICY "products_select_customer"
  ON public.products FOR SELECT TO authenticated
  USING (is_active = true AND NOT public.is_admin());

CREATE POLICY "products_select_admin"
  ON public.products FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE POLICY "products_insert_admin"
  ON public.products FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

CREATE POLICY "products_update_admin"
  ON public.products FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "products_delete_admin"
  ON public.products FOR DELETE TO authenticated
  USING (public.is_admin());

-- Policy transactions
DROP POLICY IF EXISTS "trx_select_own"   ON public.transactions;
DROP POLICY IF EXISTS "trx_select_admin" ON public.transactions;

CREATE POLICY "trx_select_own"
  ON public.transactions FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "trx_select_admin"
  ON public.transactions FOR SELECT TO authenticated
  USING (public.is_admin());

-- Policy chat_messages
DROP POLICY IF EXISTS "chat_select_customer" ON public.chat_messages;
DROP POLICY IF EXISTS "chat_select_admin"    ON public.chat_messages;
DROP POLICY IF EXISTS "chat_insert_customer" ON public.chat_messages;
DROP POLICY IF EXISTS "chat_insert_admin"    ON public.chat_messages;
DROP POLICY IF EXISTS "chat_update_read"     ON public.chat_messages;

CREATE POLICY "chat_select_customer"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (room_user_id = auth.uid() AND NOT public.is_admin());

CREATE POLICY "chat_select_admin"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE POLICY "chat_insert_customer"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (NOT public.is_admin() AND room_user_id = auth.uid() AND sender_id = auth.uid());

CREATE POLICY "chat_insert_admin"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (public.is_admin() AND sender_id = auth.uid());

CREATE POLICY "chat_update_read"
  ON public.chat_messages FOR UPDATE TO authenticated
  USING ((room_user_id = auth.uid() OR public.is_admin()) AND sender_id <> auth.uid())
  WITH CHECK (true);

-- ┌────────────────────────────────────────────────────────┐
-- │  10. STORED PROCEDURES (RPC)                           │
-- └────────────────────────────────────────────────────────┘

-- Pembelian / Buat transaksi
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
  v_user_id    UUID;
  v_product    public.products%ROWTYPE;
  v_amount     NUMERIC(15,2);
  v_trx_code   TEXT;
  v_expired_at TIMESTAMPTZ;
  v_qris       TEXT;
  v_trx        public.transactions%ROWTYPE;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Tidak terautentikasi' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_product FROM public.products
  WHERE id = p_product_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Produk tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;
  IF NOT v_product.is_active THEN
    RAISE EXCEPTION 'Produk tidak aktif' USING ERRCODE = 'P0001';
  END IF;
  IF v_product.stock <= 0 THEN
    RAISE EXCEPTION 'Stok produk habis' USING ERRCODE = 'P0001';
  END IF;

  v_amount := COALESCE(NULLIF(v_product.discount_price, 0), v_product.price);

  UPDATE public.products SET stock = stock - 1 WHERE id = p_product_id;

  v_trx_code   := '#TRX-' || nextval('trx_seq');
  v_expired_at := now() + INTERVAL '15 minutes';
  v_qris       := 'QRIS|' || v_trx_code || '|' || v_amount::TEXT || '|DigiQ';

  INSERT INTO public.transactions (
    trx_code, user_id, product_id, target_number,
    amount, status, qris_payload, expired_at
  )
  VALUES (
    v_trx_code, v_user_id, p_product_id, p_target_number,
    v_amount, 'pending', v_qris, v_expired_at
  )
  RETURNING * INTO v_trx;

  RETURN v_trx;
END;
$$;

-- Update status transaksi oleh Admin
CREATE OR REPLACE FUNCTION public.admin_update_transaction_status(
  p_trx_id UUID,
  p_status  TEXT
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trx     public.transactions%ROWTYPE;
  v_current TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Akses ditolak: hanya admin' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('success', 'failed') THEN
    RAISE EXCEPTION 'Status tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_trx FROM public.transactions WHERE id = p_trx_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaksi tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  v_current := v_trx.status;
  IF v_current <> 'pending' THEN
    RAISE EXCEPTION 'Transaksi "%" tidak bisa diubah lagi', v_current USING ERRCODE = 'P0001';
  END IF;

  IF p_status = 'failed' THEN
    UPDATE public.products SET stock = stock + 1 WHERE id = v_trx.product_id;
  END IF;

  UPDATE public.transactions SET status = p_status WHERE id = p_trx_id RETURNING * INTO v_trx;
  RETURN v_trx;
END;
$$;

-- Otomatis expire transaksi pending
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
  FOR v_rec IN
    SELECT id, product_id FROM public.transactions
    WHERE status = 'pending' AND expired_at < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.transactions SET status = 'failed' WHERE id = v_rec.id;
    UPDATE public.products     SET stock = stock + 1  WHERE id = v_rec.product_id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- List chat rooms untuk Admin
CREATE OR REPLACE FUNCTION public.admin_list_chat_rooms()
RETURNS TABLE (
  room_user_id  UUID,
  customer_name TEXT,
  last_message  TEXT,
  last_at       TIMESTAMPTZ,
  unread_count  BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Akses ditolak: hanya admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH ranked AS (
    SELECT
      cm.room_user_id,
      cm.message,
      cm.is_read,
      cm.sender_id,
      cm.created_at,
      ROW_NUMBER() OVER (PARTITION BY cm.room_user_id ORDER BY cm.created_at DESC) AS rn
    FROM public.chat_messages cm
  )
  SELECT
    r.room_user_id,
    p.full_name   AS customer_name,
    r.message     AS last_message,
    r.created_at  AS last_at,
    COUNT(*) FILTER (WHERE r2.is_read = false AND r2.sender_id = r2.room_user_id) AS unread_count
  FROM ranked r
  JOIN public.profiles p ON p.id = r.room_user_id
  JOIN ranked r2 ON r2.room_user_id = r.room_user_id
  WHERE r.rn = 1
  GROUP BY r.room_user_id, p.full_name, r.message, r.created_at
  ORDER BY r.created_at DESC;
END;
$$;
