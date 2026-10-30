-- ============================================================
-- FILE: supabase/010_products_images_hardening_rollback.sql
-- ROLLBACK UNTUK: 010_products_images_hardening.sql
-- CATATAN:
-- Menghapus policy storage product-images dan bucket product-images.
-- Mengembalikan RLS products ke kondisi awal 01_main_schema.sql.
-- ============================================================

-- 1. Hapus policies pada storage.objects untuk product-images
DROP POLICY IF EXISTS "Product images are publicly accessible" ON storage.objects;
DROP POLICY IF EXISTS "Only admin can upload product images" ON storage.objects;
DROP POLICY IF EXISTS "Only admin can update product images" ON storage.objects;
DROP POLICY IF EXISTS "Only admin can delete product images" ON storage.objects;

-- 2. Hapus bucket product-images (jika ada file di dalamnya, kosongkan dulu via dashboard)
DELETE FROM storage.buckets WHERE id = 'product-images';

-- 3. Pertahankan RLS dasar tabel products
-- (Kebijakan products_select_customer, products_select_admin, dll. tetap sama dengan 01_main_schema)

DO $$
BEGIN
  RAISE NOTICE 'Rollback migrasi 010_products_images_hardening selesai.';
END;
$$;

