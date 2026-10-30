-- ==============================================================================
-- DigiQ Migration 014: Pengerasan Registrasi, Fallback Username Unik & Login via Username/Email
-- File: supabase/014_hardening_registration_and_profiles.sql
-- ==============================================================================
-- TUJUAN:
-- 1. Menjadikan trigger handle_new_user() tahan banting (resilient):
--    Jika username yang didaftarkan kebetulan sudah terpakai (race condition/duplikasi),
--    trigger tidak akan melempar error crash (HTTP 500), melainkan otomatis menambahkan
--    akhiran angka acak unik sehingga pembuatan akun di auth.users selalu sukses.
-- 2. Menyediakan RPC resolve_login_email(p_identifier TEXT) yang mengizinkan
--    pengguna untuk login menggunakan Email MAUPUN Username secara fleksibel.
-- ==============================================================================

BEGIN;

-- 1. Perbarui trigger handle_new_user() agar tidak pernah crash karena duplikasi username
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  RETURN NEW;
END;
$$;

-- 2. Fungsi RPC: Resolve Email dari Identifier (Email atau Username)
--    Digunakan oleh AuthService.signIn agar pengguna dapat login dengan username atau email.
CREATE OR REPLACE FUNCTION public.resolve_login_email(p_identifier TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean TEXT;
  v_email TEXT;
BEGIN
  v_clean := LOWER(TRIM(COALESCE(p_identifier, '')));

  IF v_clean = '' THEN
    RETURN NULL;
  END IF;

  -- Jika identifier sudah berupa format email (mengandung @)
  IF v_clean LIKE '%@%' THEN
    RETURN v_clean;
  END IF;

  -- Cari email dari auth.users yang berelasi dengan username di public.profiles
  SELECT u.email INTO v_email
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE LOWER(p.username) = v_clean
  LIMIT 1;

  RETURN v_email;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_login_email(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_login_email(TEXT) TO anon, authenticated, service_role;

COMMIT;

