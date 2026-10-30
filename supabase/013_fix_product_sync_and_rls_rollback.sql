-- ==============================================================================
-- DigiQ Migration 013 Rollback
-- File: supabase/013_fix_product_sync_and_rls_rollback.sql
-- ==============================================================================

BEGIN;

DROP POLICY IF EXISTS "products_select_customer" ON public.products;
CREATE POLICY "products_select_customer"
  ON public.products FOR SELECT TO authenticated
  USING (is_active = true AND NOT public.is_admin());

DROP POLICY IF EXISTS "products_select_admin" ON public.products;
CREATE POLICY "products_select_admin"
  ON public.products FOR SELECT TO authenticated
  USING (public.is_admin());

COMMIT;
