-- ==============================================================================
-- DigiQ Rollback 007: Rollback untuk Migration 007 (Profile Edit, Email Check,
--                     Sensitive Column Lock, & Avatar Storage Hardening)
-- File: supabase/007_rollback.sql
-- ==============================================================================
-- PERINGATAN PENTING & RISIKO DATA:
-- 1. DROP COLUMN 'username_changed_at' akan MENGHAPUS SECARA PERMANEN SELURUH
--    RIWAYAT timestamp kapan pengguna terakhir kali mengganti username.
--    Data ini TIDAK DAPAT dipulihkan setelah kolom dihapus kecuali dari backup.
-- 2. Mengembalikan bucket 'avatars' ke pengaturan sebelum 007 (file_size_limit = NULL
--    dan allowed_mime_types = NULL) sesuai dengan skema asal pada
--    'supabase/02_storage_and_realtime.sql' baris 41-43 di mana bucket dibuat
--    hanya dengan atribut (id, name, public).
-- ==============================================================================

BEGIN;

-- 1. Hapus trigger proteksi kolom sensitif pada tabel public.profiles
DROP TRIGGER IF EXISTS trg_protect_profile_sensitive_columns ON public.profiles;

-- 2. Hapus fungsi trigger proteksi kolom sensitif
DROP FUNCTION IF EXISTS public.protect_profile_sensitive_columns();

-- 3. Hapus RPC pengecekan email
DROP FUNCTION IF EXISTS public.check_email_available(TEXT);

-- 4. Hapus RPC update_my_profile
DROP FUNCTION IF EXISTS public.update_my_profile(TEXT, TEXT, TEXT);

-- 5. Hapus Storage Policy penghapusan avatar yang ditambahkan pada 007
DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;

-- 6. Kembalikan pengaturan bucket 'avatars' ke kondisi awal sebelum 007
--    (Sesuai supabase/02_storage_and_realtime.sql: INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true))
UPDATE storage.buckets
SET 
  file_size_limit = NULL,
  allowed_mime_types = NULL
WHERE id = 'avatars';

-- 7. Hapus kolom username_changed_at
-- PERINGATAN: Eksekusi baris ini menyebabkan hilangnya data riwayat tanggal ganti username!
ALTER TABLE public.profiles 
  DROP COLUMN IF EXISTS username_changed_at;

COMMIT;

-- ==============================================================================
-- VERIFIKASI ROLLBACK
-- ==============================================================================
-- 1. Pastikan kolom username_changed_at sudah tidak ada:
--    SELECT column_name FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'username_changed_at';
-- 2. Pastikan trigger sudah terhapus:
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_protect_profile_sensitive_columns';
-- 3. Pastikan RPC sudah terhapus:
--    SELECT proname FROM pg_proc WHERE proname IN ('update_my_profile', 'check_email_available', 'protect_profile_sensitive_columns');
-- 4. Pastikan policy delete avatar sudah terhapus:
--    SELECT policyname FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Users can delete their own avatar';
-- 5. Pastikan bucket avatars kembali ke NULL:
--    SELECT id, file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = 'avatars';

