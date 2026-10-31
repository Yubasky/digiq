-- supabase/018_rollback.sql
-- Rollback migrasi 018: Kembalikan handle_new_user dengan auto-confirm (darurat)

BEGIN;

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

  IF v_username = '' OR v_username IS NULL THEN
    v_username := 'user' || SUBSTRING(REPLACE(NEW.id::text, '-', ''), 1, 8);
  END IF;

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

  UPDATE auth.users
  SET email_confirmed_at = COALESCE(email_confirmed_at, NOW())
  WHERE id = NEW.id AND email_confirmed_at IS NULL;

  RETURN NEW;
END;
$$;

COMMIT;

