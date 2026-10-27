# 09 - Perbaikan Bug Kritis Hasil Audit & Pembersihan Kode Mati (Ponytail Audit)

Dokumen ini mencatat seluruh perbaikan bug kritis (Bagian A) dan pembersihan kode mati (Bagian B) yang diimplementasikan pada proyek DigiQ berdasarkan temuan audit keamanan dan arsitektur senior.

---

## 1. Perbaikan Bug Kritis (Bagian A)

### A.1 Webhook Fail-Closed & Verifikasi Signature Mandatori
- **File**: [`supabase/functions/payment-webhook/index.ts`](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/functions/payment-webhook/index.ts)
- **Masalah Sebelumnya**: Bila environment variable `WEBHOOK_SECRET` belum disetel atau kosong di Supabase Secrets, blok `if (webhookSecret)` dilewati sehingga webhook memproses request tanpa tanda tangan (unauthenticated request bypass).
- **Perbaikan**:
  - Diterapkan pengecekan *fail-closed* di awal fungsi: jika `!webhookSecret`, fungsi segera mengembalikan status HTTP 500 `"Secret not configured"` sebelum membaca raw body atau memproses payload.
  - Semua percabangan opsional `if (webhookSecret)` dihapus.
  - Header `x-webhook-signature` wajib hadir; jika tidak ada atau signature tidak cocok, return HTTP 401.
  - Verifikasi HMAC-SHA256 dilakukan secara constant-time (`timingSafeEqual`) untuk menangkal timing attack.
  - Tidak ada pencatatan (logging) secret atau signature pada server log.

### A.2 Standarisasi Keamanan 2FA Admin (Database & Flutter)
- **File Database**: [`supabase/004_audit_fixes.sql`](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/004_audit_fixes.sql) & [`supabase/002_qris_unique_code.sql`](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/002_qris_unique_code.sql)
- **File Flutter**: [`lib/services/auth_service.dart`](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/services/auth_service.dart), [`lib/screens/login_screen.dart`](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/login_screen.dart), [`lib/screens/auth_gate_screen.dart`](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/auth_gate_screen.dart)
- **Masalah Sebelumnya**: Pengecekan `auth.jwt()->>'aal' = 'aal2'` tersebar di banyak fungsi SQL secara manual. Sementara di sisi aplikasi Flutter, login admin belum memiliki dialog enrollment QR code TOTP otomatis dan challenge verification.
- **Perbaikan**:
  - Dibuat fungsi terpusat `public.admin_session_ok()` (`SECURITY DEFINER`, `STABLE`, `SET search_path = public`):
    ```sql
    CREATE OR REPLACE FUNCTION public.admin_session_ok()
    RETURNS BOOLEAN AS $$
    BEGIN
      RETURN public.is_admin() AND COALESCE(auth.jwt() ->> 'aal', '') = 'aal2';
    END;
    $$ LANGUAGE plpgsql;
    ```
  - `public.admin_session_ok()` dipakai pada seluruh RLS policy dan RPC admin (`app_settings`, `payment_mutations`, `admin_update_transaction_status`, `verify_payment_by_amount`, `admin_list_mutations`, `admin_today_stats`).
  - Di Flutter, ditambahkan alur MFA TOTP:
    - `AuthService.listFactors()` mengecek faktor terverifikasi setelah password login.
    - Jika ada faktor terverifikasi: muncul dialog verifikasi 6 digit (`_TotpVerifyDialog`) untuk menaikkan sesi ke AAL2.
    - Jika belum ada faktor (admin baru): muncul dialog enrollment (`_TotpEnrollDialog`) yang merender QR Code SVG (`qr_flutter`) dan Secret Key dengan tombol salin, lalu memvalidasi kode 6 digit pertama via `AuthService.challengeAndVerifyTotp()`.
    - Admin tidak diizinkan masuk ke `AdminDashboardScreen` tanpa AAL2 (`AuthService.isSessionAal2()`).
    - Semua controller di-dispose secara bersih pada lifecycle `State.dispose()`.

### A.3 Sequence Transaksi Anti-Tabrakan (`trx_code`)
- **File Database**: [`supabase/004_audit_fixes.sql`](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/004_audit_fixes.sql)
- **Masalah Sebelumnya**: Formula `floor(random() * 9000) + 1000` hanya menghasilkan 9.000 kemungkinan per hari, rentan terhadap paradox birthday pada volume pemesanan tinggi.
- **Perbaikan**:
  - Dibuat database sequence `CREATE SEQUENCE IF NOT EXISTS public.trx_seq START 10000;`.
  - Kode transaksi diformat secara berurutan dan terjamin unik:
    `'#TRX-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(nextval('public.trx_seq')::text, 6, '0')`.
  - Transaksi tetap atomik dengan penguncian baris produk `FOR UPDATE` dan pengembalian stok jika insert gagal.

### A.4 Idempotensi Verifikasi Manual & Konfirmasi UI
- **File Database**: [`supabase/004_audit_fixes.sql`](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/004_audit_fixes.sql)
- **File Flutter**: [`lib/screens/admin_dashboard_screen.dart`](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/admin_dashboard_screen.dart)
- **Masalah Sebelumnya**: Jika parameter `p_external_ref` dikosongkan pada verifikasi manual, string kosong bertabrakan dengan constraint `UNIQUE (source, external_ref)` pada input manual kedua.
- **Perbaikan**:
  - Di SQL: `v_external_ref := COALESCE(NULLIF(btrim(p_external_ref), ''), 'MAN-' || gen_random_uuid()::text);`. Idempotensi tetap berjalan jika referensi manual diisi, dan dua entri manual berbeda tanpa referensi keduanya diproses dengan aman.
  - Di UI Admin: Ditambahkan dialog konfirmasi modal "Cocokkan nominal Rp X?" sebelum request dipanggil, dan tombol verifikasi dinonaktifkan (`_verifying ? null : ...`) selama proses berlangsung.

### A.5 Optimasi Skalabilitas Admin & RPC Statistik Hari Ini
- **File Flutter**: [`lib/services/transaction_service.dart`](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/services/transaction_service.dart) & [`lib/screens/admin_dashboard_screen.dart`](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/admin_dashboard_screen.dart)
- **File Database**: [`supabase/004_audit_fixes.sql`](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/004_audit_fixes.sql)
- **Masalah Sebelumnya**: `watchAllTransactionsForAdmin` streaming seluruh baris tanpa batas dan melakukan subquery produk `inFilter` berulang pada setiap emisi stream. Omset dihitung dari total baris di memori.
- **Perbaikan**:
  - Dibatasi `.limit(100)` pada stream transaksi realtime admin.
  - Ditambahkan cache produk in-memory `_productCache` pada `TransactionService`: hanya ID produk yang belum dicache yang di-fetch dari database.
  - Ditambahkan metode pagination `loadOlderTransactions({required DateTime before, int limit = 50})`.
  - Dibuat RPC PostgreSQL `public.admin_today_stats()` yang menghitung agregat riil hari ini (omset, transaksi sukses, pending, total) langsung di level database berdasarkan zona waktu `Asia/Jakarta`.

### A.6 Formatter Rupiah Nilai Negatif & Unit Test
- **File**: [`lib/services/qris_service.dart`](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/services/qris_service.dart) & [`test/qris_service_test.dart`](file:///d:/PROJEK%20FAN%20DEV/digiq/test/qris_service_test.dart)
- **Perbaikan**:
  - `formatRupiah` memisahkan penanganan tanda minus terlebih dahulu, memformat nilai absolutnya, dan menambahkan tanda `-` di depan: `-100` -> `-Rp100`.
  - Ditambahkan unit test lengkap yang mencakup `0` (`Rp0`), `100` (`Rp100`), `10300` (`Rp10.300`), `1234567` (`Rp1.234.567`), `-100` (`-Rp100`), dan `-1234567` (`-Rp1.234.567`). Seluruh pengujian lulus 100%.

### A.7 Pencegahan Re-render Berulang di Admin Dashboard
- **File**: [`lib/screens/admin_dashboard_screen.dart`](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/admin_dashboard_screen.dart)
- **Perbaikan**: Transformasi list transaksi (`_transactions`, `_pendingTrxModels`) dan katalog produk (`_products`) disimpan ke variabel state saat stream memberi data baru, menghilangkan komputasi `.map().toList()` pada getter di setiap frame rebuild.

---

## 2. Pembersihan Kode Mati (Bagian B)

1. **`supabase/003_qris_unique_code.sql`**:
   - Terbukti memiliki SHA256 hash `61483D254805D4F6243AB333AE2742B4B41D72F426DE5DAF63CDC5BCF5F0E4BE`, identik 100% byte-for-byte dengan `002_qris_unique_code.sql`. File duplikat telah dihapus (-740 baris).
2. **`lib/models/user_model.dart`**:
   - Terbukti tidak diimpor maupun dipakai di seluruh codebase (`UserStore`, `UserAccount`, `UserRole` tidak memiliki referensi aktif). File dihapus (-86 baris).
3. **`TransactionStore` di `lib/models/transaction_model.dart`**:
   - Terbukti tidak dipakai di komponen UI mana pun. Class `TransactionStore` dihapus (-17 baris).
4. **`supabase/digiq_schema.sql`**:
   - Terbukti murni tumpang tindih dengan kombinasi `01_main_schema.sql` dan `02_storage_and_realtime.sql`. File dihapus (-507 baris).
5. **`cupertino_icons` di `pubspec.yaml`**:
   - Dihapus dari dependensi setelah dipastikan tidak ada import atau pemakaian `CupertinoIcons` di proyek. Pengurangan dependensi: -1 package.

---

## 3. Validasi & Hasil Pengujian

- **`flutter analyze`**: **No issues found!** (0 warning, 0 error).
- **`flutter test`**: **11/11 tests passed** (100% pass rate).
- **Total Pengurangan Kode Mati**: ~1.350 baris kode dan 1 dependensi eksternal.
