-- supabase/006_username_and_registration_hardening.sql
-- Migrasi: Penambahan Username NOT NULL, Validasi 5-20 Alfanumerik, Case-Insensitive Unique Index,
-- Trigger handle_new_user(), dan RPC check_username_available.

BEGIN;

-- 1. Tambah kolom username ke public.profiles jika belum ada (awalnya nullable untuk migrasi aman)
ALTER TABLE public.profiles 
  ADD COLUMN IF NOT EXISTS username TEXT;

-- 2. Backfill seluruh baris lama yang username-nya NULL atau string kosong
UPDATE public.profiles
SET username = 'user' || SUBSTRING(REPLACE(id::text, '-', ''), 1, 8)
WHERE username IS NULL OR TRIM(username) = '';

-- 3. Kunci kolom username menjadi NOT NULL setelah data lama terisi
ALTER TABLE public.profiles
  ALTER COLUMN username SET NOT NULL;

-- 4. Tambahkan Check Constraint: Hanya alfanumerik (huruf dan angka), panjang 5-20 karakter
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS chk_profiles_username_format;

ALTER TABLE public.profiles
  ADD CONSTRAINT chk_profiles_username_format
  CHECK (username ~ '^[a-zA-Z0-9]{5,20}$');

-- 5. Indeks unik case-insensitive untuk mencegah duplikasi (Bayu == bayu)
DROP INDEX IF EXISTS public.idx_profiles_username_lower;

CREATE UNIQUE INDEX idx_profiles_username_lower
  ON public.profiles (LOWER(username));

-- 6. Perbarui trigger handle_new_user() tanpa menghilangkan logika lama:
--    - id, full_name, phone tetap dipertahankan persis seperti 01_main_schema.sql
--    - role 'customer' tetap terkunci
--    - username dinormalisasi ke huruf kecil (lowercase)
--    - fallback unik jika username tidak disertakan (misal signup via OAuth / legacy client)
--    - ON CONFLICT (id) DO NOTHING tetap dipertahankan
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_username TEXT;
  v_full_name TEXT;
  v_phone TEXT;
BEGIN
  v_username  := LOWER(TRIM(COALESCE(NEW.raw_user_meta_data->>'username', '')));
  v_full_name := TRIM(COALESCE(NEW.raw_user_meta_data->>'full_name', ''));
  v_phone     := TRIM(COALESCE(NEW.raw_user_meta_data->>'phone', ''));

  -- Fallback jika username kosong dari metadata pendaftaran
  IF v_username = '' OR v_username IS NULL THEN
    v_username := 'user' || SUBSTRING(REPLACE(NEW.id::text, '-', ''), 1, 8);
  END IF;

  INSERT INTO public.profiles (id, full_name, phone, username, role)
  VALUES (
    NEW.id,
    v_full_name,
    v_phone,
    v_username,
    'customer'
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- 7. RPC Function: Pengecekan Ketersediaan Username secara Aman
--    Mengembalikan:
--    TRUE  = Tersedia (belum ada yang memakai dan format valid)
--    FALSE = Sudah digunakan atau format tidak valid
CREATE OR REPLACE FUNCTION public.check_username_available(p_username TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  v_clean := LOWER(TRIM(COALESCE(p_username, '')));

  -- Tolak jika format tidak valid (panjang 5-20, hanya a-z dan 0-9)
  IF LENGTH(v_clean) < 5 OR LENGTH(v_clean) > 20 OR v_clean !~ '^[a-z0-9]{5,20}$' THEN
    RETURN FALSE;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE LOWER(username) = v_clean
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_username_available(TEXT) TO anon, authenticated;

-- 8. Pembersihan nama data uji lama "Bayu" di Supabase (jika ada)
UPDATE public.profiles
SET full_name = 'User'
WHERE full_name ILIKE '%bayu%';

COMMIT;

