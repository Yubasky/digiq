-- ==============================================================================
-- DigiQ Migration 015: Auto-Confirm Email & Aktivasi Semua Akun Belum Terverifikasi
-- File: supabase/015_auto_confirm_and_fix_unverified_emails.sql
-- ==============================================================================
-- TUJUAN:
-- 1. Mengaktifkan/mengonfirmasi seketika seluruh akun yang emailnya belum terverifikasi
--    akibat batas kirim (rate-limit 3 email/jam) atau keterlambatan SMTP bawaan Supabase.
-- 2. Memperbarui trigger handle_new_user() agar setiap pendaftaran baru otomatis
--    mendapatkan status email_confirmed_at = NOW() (Instant Verification), sehingga
--    pengguna dapat langsung login tanpa perlu menunggu email yang terhambat di spam.
-- ==============================================================================

BEGIN;

-- 1. Verifikasi langsung seluruh user di auth.users yang saat ini belum terkonfirmasi
UPDATE auth.users
SET email_confirmed_at = NOW()
WHERE email_confirmed_at IS NULL;

-- 2. Perbarui trigger handle_new_user() agar otomatis mengonfirmasi email akun baru
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_username  TEXT;
  v_full_name TEXT;
  v_phone     TEXT;
  v_attempt   INT := 0;
BEGIN
  v_username  := LOWER(TRIM(COALESCE(NEW.raw_user_meta_data->>'username', '')));
  v_full_name := TRIM(COALESCE(NEW.raw_user_meta_data->>'full_name', ''));
  v_phone     := TRIM(COALESCE(NEW.raw_user_meta_data->>'phone', ''));

  -- Fallback jika username kosong dari metadata pendaftaran
  IF v_username = '' OR v_username IS NULL THEN
    v_username := 'user' || SUBSTRING(REPLACE(NEW.id::text, '-', ''), 1, 8);
  END IF;

  -- Pastikan username belum ada di public.profiles. Jika sudah ada, tambahkan suffix angka acak
  WHILE EXISTS (SELECT 1 FROM public.profiles WHERE LOWER(username) = v_username) AND v_attempt < 10 LOOP
    v_attempt := v_attempt + 1;
    v_username := SUBSTRING(v_username, 1, 14) || FLOOR(1000 + random() * 9000)::text;
  END LOOP;

  INSERT INTO public.profiles (id, full_name, phone, username, role)
  VALUES (
    NEW.id,
    v_full_name,
    v_phone,
    v_username,
    'customer'
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone;

  -- Otomatis aktifkan status verifikasi email user pada auth.users
  -- agar pengguna tidak terblokir oleh batasan kuota kirim default mailer Supabase
  UPDATE auth.users
  SET email_confirmed_at = COALESCE(email_confirmed_at, NOW())
  WHERE id = NEW.id AND email_confirmed_at IS NULL;

  RETURN NEW;
END;
$$;

-- 3. Fungsi RPC manual jika admin ingin mengonfirmasi email spesifik
CREATE OR REPLACE FUNCTION public.confirm_user_by_email(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  v_clean := LOWER(TRIM(COALESCE(p_email, '')));
  IF v_clean = '' THEN
    RETURN FALSE;
  END IF;

  UPDATE auth.users
  SET email_confirmed_at = NOW()
  WHERE LOWER(email) = v_clean AND email_confirmed_at IS NULL;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_user_by_email(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_user_by_email(TEXT) TO authenticated, service_role;

COMMIT;

