-- ==============================================================================
-- DigiQ Migration 016 (Sequential):
-- 1. RPC ensure_my_profile() untuk Penanganan Akun Tanpa Profil (Self-Healing)
-- 2. In-DB IP Rate Limiting pada RPC resolve_login_email (Anti-Email Harvesting)
-- File: supabase/016_ensure_my_profile_and_rate_limit.sql
-- ==============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.ensure_my_profile()
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid       UUID;
  v_user      auth.users%ROWTYPE;
  v_profile   public.profiles%ROWTYPE;
  v_username  TEXT;
  v_full_name TEXT;
  v_phone     TEXT;
  v_attempt   INT := 0;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Akses ditolak: pengguna belum login' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;
  IF FOUND THEN
    RETURN v_profile;
  END IF;

  SELECT * INTO v_user FROM auth.users WHERE id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Akun auth tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  v_username  := LOWER(TRIM(COALESCE(v_user.raw_user_meta_data->>'username', '')));
  v_full_name := TRIM(COALESCE(v_user.raw_user_meta_data->>'full_name', ''));
  v_phone     := TRIM(COALESCE(v_user.raw_user_meta_data->>'phone', ''));

  IF v_username = '' OR v_username IS NULL THEN
    v_username := 'user' || SUBSTRING(REPLACE(v_uid::text, '-', ''), 1, 8);
  END IF;

  WHILE EXISTS (SELECT 1 FROM public.profiles WHERE LOWER(username) = v_username AND id <> v_uid) AND v_attempt < 10 LOOP
    v_attempt := v_attempt + 1;
    v_username := SUBSTRING(v_username, 1, 14) || FLOOR(1000 + random() * 9000)::text;
  END LOOP;

  INSERT INTO public.profiles (id, full_name, phone, username, role)
  VALUES (
    v_uid,
    v_full_name,
    v_phone,
    v_username,
    'customer'
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = CASE WHEN public.profiles.full_name = '' THEN EXCLUDED.full_name ELSE public.profiles.full_name END,
    phone     = CASE WHEN public.profiles.phone = '' THEN EXCLUDED.phone ELSE public.profiles.phone END
  RETURNING * INTO v_profile;

  RETURN v_profile;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_my_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_my_profile() TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.login_resolve_rate_limits (
  ip_address   INET PRIMARY KEY,
  request_count INT NOT NULL DEFAULT 1,
  window_start TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.login_resolve_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.login_resolve_rate_limits FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.login_resolve_rate_limits TO service_role;

CREATE OR REPLACE FUNCTION public.resolve_login_email(p_identifier TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_clean       TEXT;
  v_email       TEXT;
  v_client_ip   TEXT;
  v_ip          INET;
  v_count       INT;
  v_window      TIMESTAMPTZ;
  c_max_req     CONSTANT INT := 10;
  c_window_sec  CONSTANT INT := 60;
BEGIN
  BEGIN
    v_client_ip := current_setting('request.headers', true)::json->>'cf-connecting-ip';
    IF v_client_ip IS NULL OR v_client_ip = '' THEN
      v_client_ip := current_setting('request.headers', true)::json->>'x-forwarded-for';
      IF v_client_ip IS NOT NULL AND v_client_ip LIKE '%,%' THEN
        v_client_ip := trim(split_part(v_client_ip, ',', 1));
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_client_ip := NULL;
  END;

  IF v_client_ip IS NOT NULL AND v_client_ip <> '' THEN
    BEGIN
      v_ip := v_client_ip::inet;
    EXCEPTION WHEN OTHERS THEN
      v_ip := NULL;
    END;
  END IF;

  IF v_ip IS NOT NULL THEN
    SELECT request_count, window_start INTO v_count, v_window
    FROM public.login_resolve_rate_limits
    WHERE ip_address = v_ip
    FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.login_resolve_rate_limits (ip_address, request_count, window_start)
      VALUES (v_ip, 1, now())
      ON CONFLICT (ip_address) DO NOTHING;
    ELSIF now() - v_window > (c_window_sec || ' seconds')::interval THEN
      UPDATE public.login_resolve_rate_limits
      SET request_count = 1, window_start = now()
      WHERE ip_address = v_ip;
    ELSE
      IF v_count >= c_max_req THEN
        RAISE EXCEPTION 'Rate limit exceeded: Maksimal 10 pengecekan username per menit per IP'
          USING ERRCODE = '42901';
      END IF;
      UPDATE public.login_resolve_rate_limits
      SET request_count = request_count + 1
      WHERE ip_address = v_ip;
    END IF;

    IF random() < 0.05 THEN
      DELETE FROM public.login_resolve_rate_limits
      WHERE now() - window_start > interval '5 minutes';
    END IF;
  END IF;

  v_clean := LOWER(TRIM(COALESCE(p_identifier, '')));

  IF v_clean = '' THEN
    RETURN NULL;
  END IF;

  IF v_clean LIKE '%@%' THEN
    RETURN v_clean;
  END IF;

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

