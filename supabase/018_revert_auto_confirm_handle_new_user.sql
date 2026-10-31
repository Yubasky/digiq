-- supabase/018_revert_auto_confirm_handle_new_user.sql
-- Migrasi: Mengembalikan trigger handle_new_user() ke versi aman tanpa auto-confirm
-- Menghapus fungsi bypass verifikasi manual confirm_user_by_email()
-- Memastikan setiap user baru yang mendaftar WAJIB memverifikasi email sebelum email_confirmed_at diisi

BEGIN;

-- 1. Hapus fungsi bypass verifikasi manual
DROP FUNCTION IF EXISTS public.confirm_user_by_email(TEXT);

-- 2. Kembalikan handle_new_user() yang hanya membuat profil customer, tanpa menyentuh email_confirmed_at
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

COMMIT;
