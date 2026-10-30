# SUPABASE DATABASE MIGRATION RUN ORDER (PANDUAN EKSEKUSI RESMI)

Dokumen ini adalah panduan resmi eksekusi migrasi basis data DigiQ secara berurutan (*gated execution*).
Berdasarkan audit langsung pada database **LIVE**:
- Migrasi **006** (`check_username_available`, validasi username) dan **007** (`check_email_available`, `update_my_profile`, trigger proteksi kolom sensitif profil) **SUDAH AKTIF**.
- Urutan migrasi yang tersisa **HANYA: 008 -> 009 -> 010** (dan opsional 011 untuk pg_cron).

**PENTING: Jangan menjalankan semua migrasi sekaligus. Jalankan satu per satu, verifikasi hasilnya, jalankan uji regresi, baru lanjut ke langkah berikutnya.**

---

## LANGKAH 0: PENCADANGAN BASIS DATA (WAJIB)
1. Buka **Supabase Dashboard** -> Proyek DigiQ (`iqxoofrhhrqkgehuvrlb`).
2. Masuk ke menu **Database** -> **Backups**.
3. Pastikan cadangan (*backup snapshot*) terbaru telah tersedia atau klik **Create Backup**.

---

## LANGKAH 1: MIGRASI 008 (RATE LIMIT PENGECEKAN EMAIL)
* **File Target:** [`supabase/008_rate_limit_email_check.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/008_rate_limit_email_check.sql)
* **Tujuan:** Menambahkan tabel internal `email_check_rate_limits` dan membatasi pemanggilan RPC `check_email_available` maksimal 10x per menit per IP dari header `cf-connecting-ip`/`x-forwarded-for` untuk mencegah *mass account enumeration*.
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
* **Uji Regresi Langkah 1 (Anon RLS & Throttle Check):**
```sql
-- 1. Pastikan tabel internal rate limit tidak bisa diakses langsung oleh anon:
SELECT COUNT(*) FROM public.email_check_rate_limits;
-- (Jika dijalankan dengan role anon / REST, harus menghasilkan 0 baris / ditolak oleh RLS).

-- 2. Pastikan RPC check_email_available tetap dapat dipanggil anon:
SELECT public.check_email_available('tes_regresi_cek@example.com');
-- (Harus mengembalikan boolean true).
```
* **Rollback File:** [`supabase/008_rollback.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/008_rollback.sql)

---

## LANGKAH 2: MIGRASI 009 (PENEGAKAN EMAIL TERVERIFIKASI & DOMAIN FILTER)
* **File Target:** [`supabase/009_verified_email_enforcement.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/009_verified_email_enforcement.sql)
* **Tujuan:** 
  1. Menambahkan fungsi `is_email_verified()` untuk memeriksa status konfirmasi email pengguna login (`auth.users.email_confirmed_at`).
  2. Memperbarui `create_purchase_transaction()` berbasis PERSIS kode LIVE (tetap memakai `discount_price`, cek AAL2 jika 2FA aktif, format `#TRX-`, retry 1..5, dan kolom `amount`/`qris_payload`), dengan HANYA menyisipkan validasi email terverifikasi.
  3. Menambahkan tabel `blocked_email_domains`, `allowed_email_domains`, dan `email_security_settings` dengan RLS aktif dan terkunci dari pembacaan langsung oleh `anon`.
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
* **Uji Regresi Langkah 2 (Anon RLS & Purchase Function):**
```sql
-- 1. Uji RLS: Pastikan tabel konfigurasi email tidak terbaca oleh publik/anon
SELECT COUNT(*) FROM public.blocked_email_domains;
SELECT COUNT(*) FROM public.email_security_settings;

-- 2. Uji RPC validate_signup_email:
SELECT public.validate_signup_email('user@tempmail.com'); 
-- Harus mengembalikan: {"valid": false, "error_code": "DISPOSABLE_DOMAIN", ...}

SELECT public.validate_signup_email('user@gmail.com');
-- Harus mengembalikan: {"valid": true, "domain": "gmail.com"}
```
* **Rollback File:** [`supabase/009_verified_email_enforcement_rollback.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/009_verified_email_enforcement_rollback.sql)
*(Mengembalikan `create_purchase_transaction` persis ke definisi LIVE tanpa blokir email verifikasi).*

---

## LANGKAH 3: MIGRASI 010 (STORAGE BUCKET PRODUCT-IMAGES & RLS HARDENING)
* **File Target:** [`supabase/010_products_images_hardening.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/010_products_images_hardening.sql)
* **Tujuan:** 
  1. Membuat bucket storage `product-images` (public read, limit 2MB, MIME jpeg/png/webp).
  2. Menetapkan kebijakan RLS storage: Public read, Admin write/update/delete berbasis `public.is_admin()`.
  3. Memastikan kebijakan RLS tabel `products` (Customer hanya melihat `is_active = true`, Admin akses penuh).
  4. Memastikan tabel `products` ada di publikasi `supabase_realtime` secara idempoten.
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
* **Uji Regresi Langkah 3 (Katalog & Hak Akses):**
```sql
-- 1. Pastikan customer hanya dapat melihat produk aktif:
SELECT id, name, is_active FROM public.products;

-- 2. Pastikan policies storage untuk product-images aktif:
SELECT policyname, cmd, roles FROM pg_policies WHERE tablename = 'objects' AND policyname ILIKE '%product%';
```
* **Rollback File:** [`supabase/010_products_images_hardening_rollback.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/010_products_images_hardening_rollback.sql)

---

## LANGKAH 4 (OPSIONAL): MIGRASI 011 (PG_CRON CLEANUP BACKGROUND JOB)
* **File Target:** [`supabase/011_cron_expire_pending_transactions.sql`](file:///c:/Users/Administrator/Documents/digiq/supabase/011_cron_expire_pending_transactions.sql)
* **Tujuan:** Menjadwalkan `public.expire_pending_transactions()` otomatis setiap 2 menit menggunakan extension `pg_cron` yang telah aktif di database LIVE.
* **Aksi:** Salin dan jalankan di Supabase SQL Editor.
* **Query Verifikasi:**
```sql
SELECT jobid, schedule, command, active FROM cron.job WHERE jobname = 'digiq_expire_pending_transactions';
```

---

## LANGKAH 5: AUDIT AKUN BELUM TERVERIFIKASI > 24 JAM (DRY-RUN READ-ONLY)
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
