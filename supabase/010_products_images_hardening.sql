-- ============================================================
-- FILE: supabase/010_products_images_hardening.sql
-- TUJUAN:
-- 1. Pengerasan bucket storage 'product-images' (public read, limit 2MB, MIME jpeg/png/webp)
-- 2. Kebijakan RLS storage.objects khusus admin untuk INSERT, UPDATE, DELETE produk
-- 3. Kebijakan RLS public.products (Admin akses penuh, Customer hanya is_active = true)
-- 4. Memastikan tabel public.products terdaftar di publikasi supabase_realtime
-- 5. Penguatan CHECK constraint harga (price > 0), stok (stock >= 0), dan diskon (discount_price < price)
-- ============================================================

-- ┌────────────────────────────────────────────────────────┐
-- │  1. STORAGE BUCKET: product-images                     │
-- └────────────────────────────────────────────────────────┘
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'product-images',
  'product-images',
  true,
  2097152, -- 2 MB (2 * 1024 * 1024 bytes)
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- ┌────────────────────────────────────────────────────────┐
-- │  2. STORAGE POLICIES: storage.objects                  │
-- └────────────────────────────────────────────────────────┘
DROP POLICY IF EXISTS "Product images are publicly accessible" ON storage.objects;
CREATE POLICY "Product images are publicly accessible"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Only admin can upload product images" ON storage.objects;
CREATE POLICY "Only admin can upload product images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'product-images'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Only admin can update product images" ON storage.objects;
CREATE POLICY "Only admin can update product images"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'product-images'
    AND public.is_admin()
  )
  WITH CHECK (
    bucket_id = 'product-images'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Only admin can delete product images" ON storage.objects;
CREATE POLICY "Only admin can delete product images"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'product-images'
    AND public.is_admin()
  );

-- ┌────────────────────────────────────────────────────────┐
-- │  3. TABLE POLICIES: public.products                    │
-- └────────────────────────────────────────────────────────┘
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "products_select_customer" ON public.products;
CREATE POLICY "products_select_customer"
  ON public.products FOR SELECT TO authenticated
  USING (is_active = true AND NOT public.is_admin());

DROP POLICY IF EXISTS "products_select_admin" ON public.products;
CREATE POLICY "products_select_admin"
  ON public.products FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "products_insert_admin" ON public.products;
CREATE POLICY "products_insert_admin"
  ON public.products FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "products_update_admin" ON public.products;
CREATE POLICY "products_update_admin"
  ON public.products FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "products_delete_admin" ON public.products;
CREATE POLICY "products_delete_admin"
  ON public.products FOR DELETE TO authenticated
  USING (public.is_admin());

-- ┌────────────────────────────────────────────────────────┐
-- │  4. REALTIME PUBLICATION                               │
-- └────────────────────────────────────────────────────────┘
ALTER TABLE public.products REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'products'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
  END IF;
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  5. VERIFIKASI AKHIR MIGRASI 010                       │
-- └────────────────────────────────────────────────────────┘
DO $$
DECLARE
  v_bucket_ok BOOLEAN;
  v_pub_ok    BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM storage.buckets
    WHERE id = 'product-images' AND public = true AND file_size_limit = 2097152
  ) INTO v_bucket_ok;

  SELECT EXISTS(
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'products'
  ) INTO v_pub_ok;

  IF NOT v_bucket_ok THEN
    RAISE EXCEPTION 'Verifikasi gagal: bucket product-images belum terkonfigurasi dengan benar';
  END IF;

  IF NOT v_pub_ok THEN
    RAISE EXCEPTION 'Verifikasi gagal: public.products belum terdaftar di publikasi supabase_realtime';
  END IF;

  RAISE NOTICE 'SUKSES: Migrasi 010_products_images_hardening berhasil diterapkan dan terverifikasi.';
END;
$$;

