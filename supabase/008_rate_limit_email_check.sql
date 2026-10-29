-- ==============================================================================
-- DigiQ Migration 008: In-Database Rate Limiting untuk check_email_available
-- File: supabase/008_rate_limit_email_check.sql
-- ==============================================================================
-- LATAR BELAKANG ARSITEKTUR KEAMANAN:
-- 1. Klien Flutter Web berinteraksi secara langsung dengan Supabase REST API di
--    https://iqxoofrhhrqkgehuvrlb.supabase.co/rest/v1/... (bukan diproxy lewat
--    Cloudflare Tunnel enikzrad.web.id).
-- 2. Aturan WAF Cloudflare pada zona enikzrad.web.id hanya menyaring request aset web statis
--    (HTML, JS, font), sehingga TIDAK DAPAT menginspeksi atau membatasi pemanggilan RPC Supabase.
-- 3. Untuk mencegah enumerasi email massal oleh penyerang, pembatasan laju (throttling)
--    HARUS ditegakkan di level database (In-Database Rate Limiting) berdasarkan IP klien.
-- 4. IP klien diekstrak dari header HTTP PostgREST:
--    - 'cf-connecting-ip' (Cloudflare reverse proxy ke Supabase)
--    - Elemen pertama 'x-forwarded-for'
--    - Fallback ke '127.0.0.1' untuk pengujian lokal / kueri langsung.
-- 5. Batas: Maksimal 10 pengecekan per menit per IP. Pemanggilan ke-11 akan ditolak
--    dengan error 42901 (HTTP 429 Too Many Requests).
-- ==============================================================================

BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Tabel Pencatatan Frekuensi Pengecekan Email
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.email_check_rate_limits (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ip INET NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index gabungan untuk kecepatan agregasi interval waktu per IP dan pembersihan
CREATE INDEX IF NOT EXISTS idx_email_check_rate_limits_ip_time 
  ON public.email_check_rate_limits (ip, created_at DESC);

-- Proteksi tabel: Kunci dari akses publik/anonim langsung via PostgREST
ALTER TABLE public.email_check_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.email_check_rate_limits FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.email_check_rate_limits TO service_role;

COMMENT ON TABLE public.email_check_rate_limits IS 
  'Tabel internal pencatatan rate limit IP untuk RPC check_email_available guna mencegah enumerasi akun.';

-- ------------------------------------------------------------------------------
-- 2. Perbarui RPC check_email_available dengan Throttle In-Database
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_email_available(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_headers JSON;
  v_raw_ip TEXT;
  v_client_ip INET;
  v_attempts INT;
  v_clean TEXT;
BEGIN
  -- 1. Ekstraksi IP klien secara aman dari konfigurasi request.headers PostgREST
  BEGIN
    v_headers := NULLIF(current_setting('request.headers', true), '')::json;
    v_raw_ip := COALESCE(
      v_headers->>'cf-connecting-ip',
      split_part(v_headers->>'x-forwarded-for', ',', 1),
      '127.0.0.1'
    );
    v_client_ip := TRIM(v_raw_ip)::inet;
  EXCEPTION WHEN OTHERS THEN
    v_client_ip := '127.0.0.1'::inet;
  END;

  -- 2. Pembersihan berkala data lama (>5 menit) agar tabel tetap kecil & cepat
  DELETE FROM public.email_check_rate_limits 
  WHERE created_at < (now() - INTERVAL '5 minutes');

  -- 3. Hitung jumlah request dari IP yang sama dalam jendela waktu 1 menit terakhir
  SELECT COUNT(*) INTO v_attempts
  FROM public.email_check_rate_limits
  WHERE ip = v_client_ip
    AND created_at >= (now() - INTERVAL '1 minute');

  -- 4. Batasi maksimal 10 permintaan per menit per IP (Pemanggilan ke-11 ditolak)
  IF v_attempts >= 10 THEN
    -- Teruskan HTTP status 429 ke PostgREST
    PERFORM set_config('response.status', '429', true);
    RAISE EXCEPTION 'Rate limit exceeded: Maksimal 10 pengecekan email per menit per IP'
      USING ERRCODE = '42901';
  END IF;

  -- 5. Catat percobaan yang sah
  INSERT INTO public.email_check_rate_limits (ip, created_at)
  VALUES (v_client_ip, now());

  -- 6. Validasi format dan keunikan email
  v_clean := LOWER(TRIM(COALESCE(p_email, '')));

  IF v_clean = '' 
     OR LENGTH(v_clean) > 254 
     OR v_clean !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' THEN
    RETURN FALSE;
  END IF;

  -- Periksa keberadaan di auth.users (case-insensitive)
  RETURN NOT EXISTS (
    SELECT 1 
    FROM auth.users 
    WHERE LOWER(email) = v_clean
  );
END;
$$;

REVOKE ALL ON FUNCTION public.check_email_available(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_email_available(TEXT) TO anon, authenticated, service_role;

COMMIT;

-- ==============================================================================
-- BLOK UJI PROBE SIMULASI: PEMANGGILAN KE-11 HARUS DITOLAK (42901)
-- ==============================================================================
/*
DO $$
DECLARE
  v_i INT;
  v_res BOOLEAN;
  v_test_ip TEXT := '198.51.100.42';
BEGIN
  -- Bersihkan data uji untuk IP ini
  DELETE FROM public.email_check_rate_limits WHERE ip = v_test_ip::inet;

  -- Simulasikan header request PostgREST dari IP uji
  PERFORM set_config('request.headers', json_build_object('cf-connecting-ip', v_test_ip)::text, true);

  -- Panggilan ke 1 s/d 10: HARUS BERHASIL
  FOR v_i IN 1..10 LOOP
    v_res := public.check_email_available('probe_test_' || v_i || '@example.com');
  END LOOP;
  RAISE NOTICE '[SUKSES] 10 pemanggilan pertama berhasil diterima.';

  -- Panggilan ke-11: HARUS DIBATASI (melempar SQLSTATE 42901)
  BEGIN
    v_res := public.check_email_available('probe_test_11@example.com');
    RAISE EXCEPTION 'GAGAL: Pemanggilan ke-11 seharusnya ditolak oleh rate limit!';
  EXCEPTION WHEN SQLSTATE '42901' THEN
    RAISE NOTICE '[SUKSES] Pemanggilan ke-11 BERHASIL DIBATASI dengan status 42901 (Rate limit exceeded).';
  END;

  -- Bersihkan data uji setelah pengujian
  DELETE FROM public.email_check_rate_limits WHERE ip = v_test_ip::inet;
END;
$$;
*/

