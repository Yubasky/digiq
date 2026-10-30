# SUPABASE DATABASE MIGRATION RUN ORDER (PANDUAN EKSEKUSI MIGRASI)

Dokumen ini adalah panduan resmi eksekusi migrasi basis data DigiQ secara berurutan (*gated execution*).
**PENTING: Jangan menjalankan semua migrasi sekaligus. Jalankan satu per satu, verifikasi hasilnya, baru lanjut ke langkah berikutnya.**

---

## LANGKAH 0: PENCADANGAN BASIS DATA (WAJIB)
1. Buka **Supabase Dashboard** -> Proyek DigiQ (`iqxoofrhhrqkgehuvrlb`).
2. Masuk ke menu **Database** -> **Backups**.
3. Pastikan cadangan (*backup*) terbaru telah tersedia atau klik **Create Backup** (jika menggunakan plan yang mendukung snapshot manual).

---

## LANGKAH 1: MIGRASI 008 (RATE LIMIT PENGECEKAN EMAIL)
* **File Target:** [`supabase/008_rate_limit_email_check.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/008_rate_limit_email_check.sql)
* **Tujuan:** Menambahkan tabel internal `email_check_rate_limits` dan membatasi pemanggilan RPC `check_email_available` maksimal 10x per menit per IP untuk mencegah *mass account enumeration*.
* **Aksi:** Salin seluruh isi file `008_rate_limit_email_check.sql` dan jalankan di **Supabase SQL Editor**.
* **Query Verifikasi Langkah 1:**
```sql
SELECT 
    t.table_name,
    p.proname AS function_name,
    'OK - MIGRATION 008 APPLIED' AS status
FROM information_schema.tables t
CROSS JOIN pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE t.table_schema = 'public' 
  AND t.table_name = 'email_check_rate_limits'
  AND n.nspname = 'public' 
  AND p.proname = 'check_email_available';
```
* **Hasil yang Diharapkan:** Mengembalikan 1 baris dengan `table_name = email_check_rate_limits` dan `function_name = check_email_available`.
* **Rollback File:** [`supabase/008_rollback.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/008_rollback.sql)

---

## LANGKAH 2: MIGRASI 009 (PENEGAKAN EMAIL TERVERIFIKASI & DOMAIN BLACKLIST)
* **File Target:** [`supabase/009_verified_email_enforcement.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/009_verified_email_enforcement.sql)
* **Tujuan:** 
  1. Menambahkan fungsi `is_email_verified()` untuk memeriksa `auth.users.email_confirmed_at`.
  2. Memperbarui `create_purchase_transaction()` agar menolak pembuatan transaksi jika email belum diverifikasi.
  3. Menambahkan tabel `blocked_email_domains` dan trigger pendaftaran `validate_signup_email`.
* **Aksi:** Salin seluruh isi file `009_verified_email_enforcement.sql` dan jalankan di **Supabase SQL Editor**.
* **Query Verifikasi Langkah 2:**
```sql
SELECT 
    'is_email_verified' AS check_item,
    COUNT(*)::text AS result
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'is_email_verified'
UNION ALL
SELECT 
    'blocked_email_domains_count',
    COUNT(*)::text
FROM public.blocked_email_domains;
```
* **Hasil yang Diharapkan:** 
  - `is_email_verified`: result `1`
  - `blocked_email_domains_count`: result `> 20` (daftar domain sementara terpopulasi)
* **Rollback File:** [`supabase/009_verified_email_enforcement_rollback.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/009_verified_email_enforcement_rollback.sql)

---

## LANGKAH 3: MIGRASI 010 (STORAGE BUCKET PRODUCT-IMAGES & RLS HARDENING)
* **File Target:** [`supabase/010_products_images_hardening.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/010_products_images_hardening.sql)
* **Tujuan:** 
  1. Membuat bucket storage `product-images` (public read, 2MB limit, MIME jpeg/png/webp).
  2. Kebijakan RLS storage: Public read, Admin write/update/delete.
  3. Kebijakan RLS tabel `products`: Customer hanya melihat `is_active = true`, Admin full access.
  4. Mendaftarkan tabel `products` ke publikasi `supabase_realtime`.
* **Aksi:** Salin seluruh isi file `010_products_images_hardening.sql` dan jalankan di **Supabase SQL Editor**.
* **Query Verifikasi Langkah 3:**
```sql
SELECT 
    b.id AS bucket_id,
    b.public,
    b.file_size_limit,
    (SELECT COUNT(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'products') AS realtime_active
FROM storage.buckets b
WHERE b.id = 'product-images';
```
* **Hasil yang Diharapkan:** `bucket_id = product-images`, `public = true`, `file_size_limit = 2097152`, `realtime_active = 1`.
* **Rollback File:** [`supabase/010_products_images_hardening_rollback.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/010_products_images_hardening_rollback.sql)

---

## LANGKAH 4: AUDIT AKUN BELUM TERVERIFIKASI > 24 JAM (DRY-RUN READ-ONLY)
* **Tujuan:** Mengetahui jumlah akun yang mendaftar tetapi tidak pernah memverifikasi email lebih dari 24 jam.
* **Sifat:** **MURNI SELECT (READ-ONLY, TANPA DELETE)**.
* **Query Dry-Run:**
```sql
SELECT 
    u.id AS user_id,
    u.email,
    p.username,
    u.created_at,
    now() - u.created_at AS age_duration
FROM auth.users u
LEFT JOIN public.profiles p ON u.id = p.id
WHERE u.email_confirmed_at IS NULL
  AND u.created_at < now() - INTERVAL '24 hours'
ORDER BY u.created_at DESC;
```
*(Jangan lakukan penghapusan baris pengguna tanpa tinjauan manual dan persetujuan terpisah).*
