-- ==============================================================================
-- DigiQ Migration 007: Profile Edit RPC, Email Check RPC, Sensitive Column Lock,
--                      & Avatar Storage Hardening (REVISED)
-- File: supabase/007_profile_edit_and_email_check.sql
-- ==============================================================================
-- PENTING:
-- 1. Buat backup database di Supabase Dashboard (Database -> Backups) terlebih dahulu.
-- 2. Jalankan seluruh skrip ini di SQL Editor Supabase.
-- 3. Jalankan blok UJI SKENARIO dan BLOK VERIFIKASI di bagian akhir.
-- ==============================================================================

BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Kolom username_changed_at (Tracking Cooldown Perubahan Username 30 Hari)
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles 
  ADD COLUMN IF NOT EXISTS username_changed_at TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.username_changed_at IS 
  'Mencatat timestamp terakhir kali pengguna mengubah username untuk membatasi frekuensi ganti username (cooldown 30 hari).';

-- ------------------------------------------------------------------------------
-- 2. Trigger Proteksi Kolom Sensitif: role, balance, is_2fa_enabled, id
-- ------------------------------------------------------------------------------
-- Mekanisme Bypass Berlapis yang Sah:
--  a. auth.role() = 'service_role' (background worker, script admin, supabase backend)
--  b. current_setting('app.bypass_profile_lock', true) = 'on'
--     (Hanya fungsi SECURITY DEFINER internal tepercaya yang dapat mengaktifkan flag transaksi ini,
--      misalnya alur pencatatan saldo / verifikasi pembayaran)
--  c. public.is_admin() = true (Administrator resmi yang sedang mengelola pengguna)
-- Kunci bagi Customer Biasa:
--  - Direct PATCH / UPDATE via REST ditolak jika memodifikasi role, balance, is_2fa_enabled, atau id.
CREATE OR REPLACE FUNCTION public.protect_profile_sensitive_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bypass TEXT;
BEGIN
  -- 1. Izinkan bypass untuk service_role
  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- 2. Izinkan bypass jika flag transaksi lokal 'app.bypass_profile_lock' aktif
  --    (Diaktifkan oleh fungsi SECURITY DEFINER tepercaya via PERFORM set_config('app.bypass_profile_lock', 'on', true))
  v_bypass := NULLIF(current_setting('app.bypass_profile_lock', true), '');
  IF v_bypass = 'on' THEN
    RETURN NEW;
  END IF;

  -- 3. Izinkan bypass jika pemanggil adalah admin yang sah (menggunakan public.is_admin())
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  -- 4. KUNCI UNTUK CUSTOMER: Tolak perubahan pada kolom sensitif
  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION 'Akses ditolak: ID profil bersifat permanen dan tidak boleh diubah'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION 'Akses ditolak: Anda tidak memiliki wewenang mengubah role profil'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.balance IS DISTINCT FROM OLD.balance THEN
    RAISE EXCEPTION 'Akses ditolak: Saldo profil hanya dapat diubah melalui sistem pembayaran resmi'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.is_2fa_enabled IS DISTINCT FROM OLD.is_2fa_enabled THEN
    RAISE EXCEPTION 'Akses ditolak: Status 2FA hanya dapat diubah melalui alur verifikasi 2FA resmi'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_profile_sensitive_columns ON public.profiles;

CREATE TRIGGER trg_protect_profile_sensitive_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_profile_sensitive_columns();

-- ------------------------------------------------------------------------------
-- 3. RPC: check_email_available (Pengecekan Ketersediaan Email)
-- ------------------------------------------------------------------------------
-- DOKUMENTASI KEAMANAN & MITIGASI ENUMERASI:
--  - Risiko Enumerasi: Membuka pengecekan ketersediaan email ke publik memungkinkan
--    pihak ketiga menebak daftar email pengguna yang terdaftar di platform.
--  - Mitigasi Arsitektur Database:
--    1. Mengembalikan HANYA boolean tunggal (TRUE = belum ada, FALSE = sudah ada atau format salah).
--    2. Tidak memberikan informasi tambahan: status konfirmasi, metadata, nama, atau timestamp.
--    3. Validasi format email RFC ketat; string email tidak valid langsung mengembalikan FALSE.
--  - Mitigasi Edge / Cloudflare WAF:
--    Disarankan mengaktifkan aturan Rate Limiting di Cloudflare Dashboard:
--    Expression: (http.request.uri.path eq "/rest/v1/rpc/check_email_available")
--    Action: Block atau Managed Challenge jika request > 10 req/menit per IP.
--  - OPSI TANPA REAL-TIME (Anti-Enumerasi Mutlak):
--    Jika bisnis menghendaki privasi total, form registrasi cukup memeriksa sintaks email secara lokal,
--    dan pengecekan keberadaan email HANYA dilakukan saat tombol Daftar ditekan melalui evaluasi
--    user.identities (empty identities = email sudah terdaftar).
CREATE OR REPLACE FUNCTION public.check_email_available(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  v_clean := LOWER(TRIM(COALESCE(p_email, '')));

  -- Validasi panjang dan format standar email
  IF v_clean = '' 
     OR LENGTH(v_clean) > 254 
     OR v_clean !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' THEN
    RETURN FALSE;
  END IF;

  -- Cek keberadaan di auth.users (case-insensitive)
  RETURN NOT EXISTS (
    SELECT 1 
    FROM auth.users 
    WHERE LOWER(email) = v_clean
  );
END;
$$;

REVOKE ALL ON FUNCTION public.check_email_available(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_email_available(TEXT) TO anon, authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 4. RPC: update_my_profile (Edit Profil Aman untuk Customer)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_my_profile(
  p_full_name TEXT,
  p_phone TEXT,
  p_username TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID;
  v_clean_name TEXT;
  v_clean_phone TEXT;
  v_clean_username TEXT;
  v_curr_profile RECORD;
  v_username_changed BOOLEAN := FALSE;
BEGIN
  -- 1. Autentikasi
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'unauthorized',
      'message', 'Sesi Anda telah berakhir. Silakan login kembali.'
    );
  END IF;

  SELECT * INTO v_curr_profile 
  FROM public.profiles 
  WHERE id = v_uid 
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'profile_not_found',
      'message', 'Data profil tidak ditemukan.'
    );
  END IF;

  -- 2. Normalisasi input
  v_clean_name     := TRIM(COALESCE(p_full_name, ''));
  v_clean_phone    := TRIM(COALESCE(p_phone, ''));
  v_clean_username := LOWER(TRIM(COALESCE(p_username, '')));

  -- 3. Validasi Nama (2-60 karakter)
  IF LENGTH(v_clean_name) < 2 OR LENGTH(v_clean_name) > 60 THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'invalid_name',
      'message', 'Nama lengkap harus antara 2 hingga 60 karakter.'
    );
  END IF;

  -- 4. Validasi Nomor HP (Format Indonesia: 08xx, +62xx, 62xx - 9 sampai 15 digit)
  IF v_clean_phone <> '' AND v_clean_phone !~ '^(\+62|62|08)[0-9]{7,13}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'invalid_phone',
      'message', 'Nomor HP tidak valid. Gunakan format Indonesia (misal: 08123456789 atau +628123456789).'
    );
  END IF;

  -- 5. Validasi Username (5-20 alfanumerik)
  IF LENGTH(v_clean_username) < 5 OR LENGTH(v_clean_username) > 20 OR v_clean_username !~ '^[a-z0-9]{5,20}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'invalid_username',
      'message', 'Username harus berupa 5-20 karakter huruf atau angka tanpa simbol/spasi.'
    );
  END IF;

  -- Cek perubahan username
  IF LOWER(v_curr_profile.username) IS DISTINCT FROM v_clean_username THEN
    v_username_changed := TRUE;

    -- Aturan Cooldown 30 Hari
    IF v_curr_profile.username_changed_at IS NOT NULL 
       AND v_curr_profile.username_changed_at > (now() - INTERVAL '30 days') THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'username_cooldown',
        'message', 'Username baru dapat diubah 30 hari sekali. Terakhir diubah pada ' || 
                   to_char(v_curr_profile.username_changed_at, 'DD/MM/YYYY HH24:MI') || '.'
      );
    END IF;

    -- Pengecekan keunikan username pada akun pengguna lain
    IF EXISTS (
      SELECT 1 
      FROM public.profiles 
      WHERE LOWER(username) = v_clean_username 
        AND id <> v_uid
    ) THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'username_taken',
        'message', 'Username ini telah digunakan oleh pengguna lain. Silakan pilih username lain.'
      );
    END IF;
  END IF;

  -- 6. Update hanya field profil yang diizinkan (role & balance tidak disentuh)
  UPDATE public.profiles
  SET 
    full_name           = v_clean_name,
    phone               = v_clean_phone,
    username            = v_clean_username,
    username_changed_at = CASE WHEN v_username_changed THEN now() ELSE username_changed_at END,
    updated_at          = now()
  WHERE id = v_uid;

  RETURN jsonb_build_object(
    'success', true,
    'code', 'profile_updated',
    'message', 'Profil berhasil diperbarui.',
    'data', jsonb_build_object(
      'id', v_uid,
      'full_name', v_clean_name,
      'phone', v_clean_phone,
      'username', v_clean_username,
      'username_changed', v_username_changed
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_profile(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_profile(TEXT, TEXT, TEXT) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 5. Penguatan Kebijakan Storage Avatar (Bucket 'avatars')
-- ------------------------------------------------------------------------------
-- Memperbarui batasan bucket agar secara native memvalidasi:
--  - Ukuran file maksimal: 2 MB (2.097.152 bytes)
--  - Format MIME: image/jpeg, image/png, image/webp
UPDATE storage.buckets
SET 
  file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'avatars';

-- Tambahkan policy DELETE agar pengguna bisa menghapus avatar lama miliknya
DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;
CREATE POLICY "Users can delete their own avatar"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

COMMIT;

-- ==============================================================================
-- BLOK UJI SKENARIO TRIGGER (Jalankan untuk membuktikan perilaku keamanan)
-- ==============================================================================
/*
DO $$
DECLARE
  v_test_uid UUID;
  v_initial_bal NUMERIC;
BEGIN
  -- Pilih satu user customer untuk pengujian
  SELECT id, balance INTO v_test_uid, v_initial_bal FROM public.profiles WHERE role = 'customer' LIMIT 1;
  IF v_test_uid IS NULL THEN
    RAISE NOTICE 'Tidak ada user customer untuk diuji.';
    RETURN;
  END IF;

  -- --------------------------------------------------------------------------
  -- SKENARIO (a): Simulasi Customer PATCH role / balance langsung (HARUS GAGAL)
  -- --------------------------------------------------------------------------
  -- Set sesi sebagai user customer tersebut
  PERFORM set_config('request.jwt.claim.sub', v_test_uid::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  BEGIN
    UPDATE public.profiles SET balance = 99999999 WHERE id = v_test_uid;
    RAISE EXCEPTION 'GAGAL: Customer berhasil memodifikasi saldo!';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE '[SUKSES] Skenario (a1): PATCH balance oleh customer berhasil DITOLAK (42501).';
  END;

  BEGIN
    UPDATE public.profiles SET role = 'admin' WHERE id = v_test_uid;
    RAISE EXCEPTION 'GAGAL: Customer berhasil eskalasi role ke admin!';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE '[SUKSES] Skenario (a2): PATCH role oleh customer berhasil DITOLAK (42501).';
  END;

  -- --------------------------------------------------------------------------
  -- SKENARIO (b): Fungsi Pembayaran Sah / Bypass Flag (HARUS BERHASIL)
  -- --------------------------------------------------------------------------
  BEGIN
    -- Aktifkan flag bypass lokal transaksi
    PERFORM set_config('app.bypass_profile_lock', 'on', true);
    
    -- Eksekusi penambahan saldo (misal dari webhook mutasi/topup)
    UPDATE public.profiles SET balance = balance + 5000 WHERE id = v_test_uid;
    
    -- Kembalikan saldo semula agar tidak merusak data uji
    UPDATE public.profiles SET balance = v_initial_bal WHERE id = v_test_uid;
    
    -- Reset flag
    PERFORM set_config('app.bypass_profile_lock', 'off', true);
    RAISE NOTICE '[SUKSES] Skenario (b): Pembaruan saldo melalui alur tepercaya/bypass BERHASIL.';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'GAGAL pada Skenario (b): %', SQLERRM;
  END;

  -- --------------------------------------------------------------------------
  -- SKENARIO (c): Admin Mengubah Profil Pengguna Lain (HARUS BERHASIL)
  -- --------------------------------------------------------------------------
  -- Set sesi sebagai admin
  PERFORM set_config('request.jwt.claim.sub', (SELECT id::text FROM public.profiles WHERE role = 'admin' LIMIT 1), true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  BEGIN
    UPDATE public.profiles SET full_name = full_name WHERE id = v_test_uid;
    RAISE NOTICE '[SUKSES] Skenario (c): Admin berhasil mengupdate profil.';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'GAGAL pada Skenario (c): %', SQLERRM;
  END;

END;
$$;
*/

-- ==============================================================================
-- BLOK VERIFIKASI OBJEK
-- ==============================================================================
/*
-- 1. Periksa kolom baru username_changed_at
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'profiles' AND column_name = 'username_changed_at';

-- 2. Periksa keberadaan trigger proteksi kolom sensitif
SELECT tgname, tgenabled, proname 
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE tgrelid = 'public.profiles'::regclass 
  AND tgname = 'trg_protect_profile_sensitive_columns';

-- 3. Uji fungsi check_email_available dengan email acak (harus true)
SELECT public.check_email_available('testing_nonexistent_email_12345@gmail.com') AS should_be_true;

-- 4. Uji fungsi check_email_available dengan format salah (harus false)
SELECT public.check_email_available('format-salah-tanpa-domain') AS should_be_false;

-- 5. Periksa batasan file_size_limit dan allowed_mime_types pada bucket avatars
SELECT id, name, public, file_size_limit, allowed_mime_types 
FROM storage.buckets 
WHERE id = 'avatars';
*/

-- ==============================================================================
-- BLOK ROLLBACK (Gunakan HANYA jika ingin membatalkan migrasi 007)
-- ==============================================================================
/*
DROP TRIGGER IF EXISTS trg_protect_profile_sensitive_columns ON public.profiles;
DROP FUNCTION IF EXISTS public.protect_profile_sensitive_columns();
DROP FUNCTION IF EXISTS public.check_email_available(TEXT);
DROP FUNCTION IF EXISTS public.update_my_profile(TEXT, TEXT, TEXT);
ALTER TABLE public.profiles DROP COLUMN IF EXISTS username_changed_at;
DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;
UPDATE storage.buckets SET file_size_limit = NULL, allowed_mime_types = NULL WHERE id = 'avatars';
*/
