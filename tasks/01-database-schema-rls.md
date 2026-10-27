# Task 01: Database Schema & Row Level Security (RLS)

## 1. Tujuan
Membangun fondasi skema database PostgreSQL di Supabase yang aman, terisolasi dengan Row Level Security (RLS), dan memisahkan tanggung jawab tabel (`profiles`, `products`, `transactions`, `chat_messages`, `app_settings`, `payment_mutations`).

## 2. File Terkait
- [supabase/01_main_schema.sql](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/01_main_schema.sql)
- [supabase/02_storage_and_realtime.sql](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/02_storage_and_realtime.sql)
- [supabase/002_qris_unique_code.sql](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/002_qris_unique_code.sql)

## 3. Keputusan Desain & Keamanan
1. **Zero-Trust Client Principle**: Klien Flutter tidak dipercaya untuk melakukan update data sensitif (stok, status transaksi, balance) secara langsung. Semua mutasi kritis dilakukan lewat fungsi `SECURITY DEFINER` dengan `SET search_path = public`.
2. **RLS Mandatory**: Semua tabel publik memiliki `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`.
3. **Helper `is_admin()`**:
   ```sql
   CREATE OR REPLACE FUNCTION public.is_admin()
   RETURNS BOOLEAN
   LANGUAGE plpgsql
   SECURITY DEFINER
   STABLE
   SET search_path = public
   AS $$
   BEGIN
     RETURN EXISTS (
       SELECT 1 FROM public.profiles
       WHERE id = auth.uid() AND role = 'admin'
     );
   END;
   $$;
   ```
4. **Isolasi Mutasi**: Tabel `payment_mutations` hanya bisa diakses (SELECT) oleh admin berstatus AAL2 (`public.is_admin() AND (auth.jwt()->>'aal') = 'aal2'`). Tidak ada policy INSERT/UPDATE/DELETE dari klien (hanya diakses via RPC).

## 4. Cara Uji
1. Login sebagai user biasa (customer) di Supabase Studio.
2. Coba jalankan `SELECT * FROM payment_mutations;` -> harus mengembalikan 0 baris atau ditolak RLS.
3. Jalankan `SELECT * FROM app_settings;` -> berhasil membaca setting QRIS (`SELECT TO authenticated USING (true)`).
4. Coba lakukan `UPDATE app_settings SET value = 'test';` sebagai customer -> ditolak RLS (42501).

## 5. Status Aktual
**SELESAI (100% Verified)**: Skema idempoten telah diterapkan di file SQL dan RLS berjalan ketat.
