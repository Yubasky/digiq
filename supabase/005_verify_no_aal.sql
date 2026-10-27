-- ============================================================
-- FILE: supabase/005_verify_no_aal.sql
-- Skrip Verifikasi & Pengujian Pasca-Migrasi 005
-- Read-Only & Uji Coba Atomik (BEGIN ... ROLLBACK)
-- Aman dijalankan di Supabase SQL Editor: TIDAK mengubah data produksi
-- ============================================================

-- ============================================================
-- BAGIAN 1: PEMERIKSAAN STATIS (READ-ONLY)
-- ============================================================

-- 1. Verifikasi: Tidak ada lagi policy di schema public yang menyebut 'aal'
SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual ILIKE '%aal%' OR with_check ILIKE '%aal%');
-- HASIL YANG DIHARAPKAN: 0 baris

-- 2. Verifikasi: Tidak ada lagi fungsi di schema public yang menyebut 'aal2'
SELECT p.proname, pg_get_functiondef(p.oid) AS def
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND pg_get_functiondef(p.oid) ILIKE '%aal2%';
-- HASIL YANG DIHARAPKAN: 0 baris

-- 3. Verifikasi: Hak level tabel profiles untuk role 'authenticated'
-- Membuktikan TIDAK ADA hak UPDATE di level tabel
SELECT table_name, privilege_type, grantee
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND grantee = 'authenticated';
-- HASIL YANG DIHARAPKAN: Tidak ada baris dengan privilege_type = 'UPDATE'

-- 4. Verifikasi: Hak level kolom profiles untuk role 'authenticated'
-- Membuktikan kolom 'role' dan 'is_2fa_enabled' TIDAK BISA di-UPDATE
SELECT column_name, privilege_type, grantee
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND grantee = 'authenticated';
-- HASIL YANG DIHARAPKAN: Hanya ada kolom full_name, phone, avatar_url. Kolom 'role' TIDAK ADA.

-- 5. Verifikasi: Trigger signup handle_new_user()
-- Membuktikan role 'customer' di-hardcode dan tidak membaca dari raw_user_meta_data
SELECT pg_get_functiondef('public.handle_new_user()'::regprocedure);
-- HASIL YANG DIHARAPKAN: baris 'customer' hardcoded, bukan mengambil NEW.raw_user_meta_data->>'role'


-- ============================================================
-- BAGIAN 2: SKRIP SIMULASI ATOMIK (BEGIN ... ROLLBACK)
-- Menguji skenario izin: Customer AAL1 vs Admin AAL1 vs Anon
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_admin_id       UUID;
  v_customer_id    UUID;
  v_product_id     UUID;
  v_trx            public.transactions%ROWTYPE;
  v_stats          JSONB;
  v_err_msg        TEXT;
  v_passed_tests   INT := 0;
BEGIN
  RAISE NOTICE '=== MEMULAI TEST RUNNER 005 (SIMULASI ATOMIK) ===';

  -- 1. Cari atau buat sampel admin dan customer untuk pengetesan di dalam transaksi
  SELECT id INTO v_admin_id FROM public.profiles WHERE role = 'admin' LIMIT 1;
  IF v_admin_id IS NULL THEN
    v_admin_id := gen_random_uuid();
    INSERT INTO public.profiles (id, full_name, phone, role)
    VALUES (v_admin_id, 'Test Admin', '0811111111', 'admin');
  END IF;

  SELECT id INTO v_customer_id FROM public.profiles WHERE role = 'customer' LIMIT 1;
  IF v_customer_id IS NULL THEN
    v_customer_id := gen_random_uuid();
    INSERT INTO public.profiles (id, full_name, phone, role, is_2fa_enabled)
    VALUES (v_customer_id, 'Test Customer', '0822222222', 'customer', true);
  ELSE
    -- Pastikan user test ini memiliki is_2fa_enabled = true untuk membuktikan blokir terlepas
    UPDATE public.profiles SET is_2fa_enabled = true WHERE id = v_customer_id;
  END IF;

  SELECT id INTO v_product_id FROM public.products WHERE is_active = true AND stock > 0 LIMIT 1;
  IF v_product_id IS NULL THEN
    v_product_id := gen_random_uuid();
    INSERT INTO public.products (id, name, category, price, stock, is_active)
    VALUES (v_product_id, 'Test Pulsa', 'Pulsa', 10000, 10, true);
  END IF;

  -- -------------------------------------------------------------------------
  -- UJI A: Customer non-admin memanggil create_purchase_transaction (HARUS BERHASIL)
  -- Catatan: user ini memiliki is_2fa_enabled = true dan sesi AAL1
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_customer_id::text,
    'role', 'authenticated',
    'aal', 'aal1'
  )::text, true);

  BEGIN
    v_trx := public.create_purchase_transaction(v_product_id, '081299998888');
    IF v_trx.id IS NOT NULL AND v_trx.status = 'pending' THEN
      RAISE NOTICE '[PASS] Uji A: Customer sesi AAL1 (is_2fa_enabled=true) berhasil checkout TRX %', v_trx.trx_code;
      v_passed_tests := v_passed_tests + 1;
    ELSE
      RAISE EXCEPTION 'Uji A GAGAL: Transaksi tidak terbuat';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Uji A GAGAL dengan error: %', SQLERRM;
  END;

  -- -------------------------------------------------------------------------
  -- UJI B: Customer non-admin memanggil RPC admin_* (HARUS DITOLAK ERRCODE 42501)
  -- -------------------------------------------------------------------------
  -- B1: admin_today_stats
  BEGIN
    PERFORM public.admin_today_stats();
    RAISE EXCEPTION 'Uji B1 GAGAL: Customer bisa memanggil admin_today_stats!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      RAISE NOTICE '[PASS] Uji B1: Customer memanggil admin_today_stats ditolak (42501: %)', SQLERRM;
      v_passed_tests := v_passed_tests + 1;
    ELSE
      RAISE EXCEPTION 'Uji B1 GAGAL: Error code bukan 42501, tetapi % (%)', SQLSTATE, SQLERRM;
    END IF;
  END;

  -- B2: admin_list_mutations
  BEGIN
    PERFORM * FROM public.admin_list_mutations(10, 0, false);
    RAISE EXCEPTION 'Uji B2 GAGAL: Customer bisa memanggil admin_list_mutations!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      RAISE NOTICE '[PASS] Uji B2: Customer memanggil admin_list_mutations ditolak (42501: %)', SQLERRM;
      v_passed_tests := v_passed_tests + 1;
    ELSE
      RAISE EXCEPTION 'Uji B2 GAGAL: Error code bukan 42501, tetapi % (%)', SQLSTATE, SQLERRM;
    END IF;
  END;

  -- B3: admin_update_transaction_status
  BEGIN
    PERFORM public.admin_update_transaction_status(v_trx.id, 'failed', NULL);
    RAISE EXCEPTION 'Uji B3 GAGAL: Customer bisa memanggil admin_update_transaction_status!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      RAISE NOTICE '[PASS] Uji B3: Customer memanggil admin_update_transaction_status ditolak (42501: %)', SQLERRM;
      v_passed_tests := v_passed_tests + 1;
    ELSE
      RAISE EXCEPTION 'Uji B3 GAGAL: Error code bukan 42501, tetapi % (%)', SQLSTATE, SQLERRM;
    END IF;
  END;

  -- -------------------------------------------------------------------------
  -- UJI C: Customer mencoba UPDATE profiles SET role = 'admin' (HARUS DITOLAK)
  -- -------------------------------------------------------------------------
  BEGIN
    EXECUTE 'UPDATE public.profiles SET role = ''admin'' WHERE id = $1' USING v_customer_id;
    RAISE EXCEPTION 'Uji C GAGAL: Customer berhasil mengupdate kolom role!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      RAISE NOTICE '[PASS] Uji C: Customer UPDATE profiles.role ditolak (42501: %)', SQLERRM;
      v_passed_tests := v_passed_tests + 1;
    ELSE
      RAISE EXCEPTION 'Uji C GAGAL: Error code bukan 42501, tetapi % (%)', SQLSTATE, SQLERRM;
    END IF;
  END;

  -- -------------------------------------------------------------------------
  -- UJI D: Akun Admin memanggil admin_today_stats dengan sesi AAL1 (HARUS BERHASIL)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', v_admin_id::text,
    'role', 'authenticated',
    'aal', 'aal1'
  )::text, true);

  BEGIN
    v_stats := public.admin_today_stats();
    IF v_stats ? 'omset' AND v_stats ? 'total_count' THEN
      RAISE NOTICE '[PASS] Uji D: Admin sesi AAL1 berhasil memanggil admin_today_stats: %', v_stats;
      v_passed_tests := v_passed_tests + 1;
    ELSE
      RAISE EXCEPTION 'Uji D GAGAL: Format stats tidak sesuai: %', v_stats;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Uji D GAGAL dengan error: %', SQLERRM;
  END;

  -- -------------------------------------------------------------------------
  -- UJI E: Sesi Anonim mencoba memanggil RPC admin (HARUS DITOLAK)
  -- -------------------------------------------------------------------------
  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  BEGIN
    PERFORM public.admin_today_stats();
    RAISE EXCEPTION 'Uji E GAGAL: Anonim bisa memanggil admin_today_stats!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
      RAISE NOTICE '[PASS] Uji E: Anonim memanggil admin_today_stats ditolak (42501: %)', SQLERRM;
      v_passed_tests := v_passed_tests + 1;
    ELSE
      RAISE EXCEPTION 'Uji E GAGAL: Error code bukan 42501, tetapi % (%)', SQLSTATE, SQLERRM;
    END IF;
  END;

  RAISE NOTICE '=== SEMUA 7 SKENARIO PENGUJIAN BERHASIL LULUS (%/7) ===', v_passed_tests;
END;
$$;

-- BATALKAN TRANSAKSI: TIDAK ADA DATA UJI YANG TERSIMPAN DI DATABASE
ROLLBACK;

