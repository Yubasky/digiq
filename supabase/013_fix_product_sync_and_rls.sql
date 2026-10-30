-- ==============================================================================
-- DigiQ Migration 013: Sinkronisasi Produk, RLS Customer/Admin & Perbaikan Toggle
-- File: supabase/013_fix_product_sync_and_rls.sql
-- ==============================================================================
-- TUJUAN:
-- 1. Memastikan seluruh produk aktif (khususnya "Netflix Premium 4K UHD") dapat dibaca
--    oleh Customer (baik sesi authenticated maupun anon) tanpa terblokir RLS.
-- 2. Memastikan Admin dapat melakukan toggle status (is_active: true <-> false) secara langsung.
-- 3. Mengaktifkan kembali produk Netflix yang sebelumnya berstatus nonaktif di database.
-- 4. Memastikan hak akses GRANT SELECT diberikan kepada anon dan authenticated.
-- ==============================================================================

BEGIN;

-- 1. Pastikan RLS aktif pada tabel products
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- 2. Kebijakan SELECT untuk Customer & Pengunjung Publik (anon)
--    Hanya menampilkan produk yang aktif (is_active = true).
DROP POLICY IF EXISTS "products_select_customer" ON public.products;
CREATE POLICY "products_select_customer"
  ON public.products FOR SELECT TO authenticated, anon
  USING (is_active = true);

-- 3. Kebijakan SELECT untuk Admin (Dapat melihat semua produk: aktif maupun nonaktif)
DROP POLICY IF EXISTS "products_select_admin" ON public.products;
CREATE POLICY "products_select_admin"
  ON public.products FOR SELECT TO authenticated
  USING (public.is_admin());

-- 4. Kebijakan INSERT untuk Admin
DROP POLICY IF EXISTS "products_insert_admin" ON public.products;
CREATE POLICY "products_insert_admin"
  ON public.products FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

-- 5. Kebijakan UPDATE untuk Admin (termasuk toggle is_active, edit harga, edit stok)
DROP POLICY IF EXISTS "products_update_admin" ON public.products;
CREATE POLICY "products_update_admin"
  ON public.products FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- 6. Kebijakan DELETE untuk Admin
DROP POLICY IF EXISTS "products_delete_admin" ON public.products;
CREATE POLICY "products_delete_admin"
  ON public.products FOR DELETE TO authenticated
  USING (public.is_admin());

-- 7. Grant izin tabel products ke anon dan authenticated
GRANT SELECT ON public.products TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated;

-- 8. Aktifkan produk Netflix di database secara langsung
UPDATE public.products
SET is_active = true
WHERE name ILIKE '%Netflix%' OR provider ILIKE '%Netflix%';

-- 9. Pastikan replikasi realtime aktif untuk tabel products
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

COMMIT;

