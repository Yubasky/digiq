# Task 07: Security Audit, Test Scenarios, & Verification Results

Dokumen ini mencatat audit keamanan dan hasil pengujian menyeluruh terhadap sistem DigiQ, meliputi integritas database, RLS, RPC, serta keandalan aplikasi Flutter.

---

## 1. Hasil Pengujian Unit & Static Analysis

| Item Pengujian | Perintah / Target | Hasil Aktual | Keterangan |
| :--- | :--- | :--- | :--- |
| **Unit Test QRIS** | `flutter test test/qris_service_test.dart` | **100% Lulus (8/8 Passed)** | CRC16 statis valid (`F95A`), dynamic builder valid, TLV parsing tepat |
| **Model Serialization** | `flutter test test/widget_test.dart` | **100% Lulus (3/3 Passed)** | Serialisasi `TransactionModel` & `PaymentMutationModel` presisi |
| **All Test Suites** | `flutter test` | **100% Lulus (11/11 Passed)** | Tidak ada test yang gagal |
| **Static Code Analysis** | `flutter analyze` | **0 Error, 0 Warning, 0 Issue** | Clean codebase, strict typing |

---

## 2. Audit Skenario Keamanan & Fungsional

### Skenario 1: Ekstraksi String QRIS "kopi sat"
- **Ekstraksi Langsung**: Berhasil diekstrak dari gambar menggunakan decoder `pyzbar` & `pillow`.
- **Hasil Ekstraksi**:
  `00020101021126570011ID.DANA.WWW011893600915302435049402090243504940303UMI51440014ID.CO.QRIS.WWW0215ID10265164220800303UMI5204581353033605802ID5908kopi sat6015Kab. Nanggroe A6105245526304F95A`
- **Verifikasi**: Tag 59 = `kopi sat`, Tag 51 subtag 02 = `ID1026516422080`, Checksum CRC16 = `F95A` (Valid).

### Skenario 2: Dua Customer Membeli Bersamaan (Konkurensi)
- **Mekanisme**: Query `generate_series` mengecualikan semua `total_amount` pending yang aktif + partial unique index `idx_transactions_pending_total_amount`.
- **Hasil**: Jika dua permintaan bersamaan mencoba memilih kode yang sama, salah satu akan mengalami `unique_violation` dan ditangkap oleh blok `EXCEPTION`, lalu me-retry otomatis hingga 5 kali. Nominal transaksi pending dijamin 100% unik.

### Skenario 3: Batas Maksimal 3 Transaksi Pending & Pembatalan Mandiri
- **Mekanisme**: Query `SELECT COUNT(*) WHERE user_id = auth.uid() AND status = 'pending'`.
- **Hasil**: Transaksi ke-4 ditolak dengan pesan: `"Anda masih memiliki 3 transaksi yang belum dibayar. Selesaikan atau batalkan terlebih dahulu."`.
- **Pembatalan**: Fungsi `cancel_my_pending_transaction` mengubah status ke `'failed'` dan mengembalikan stok produk `+1`.

### Skenario 4: Seluruh 300 Kode Unik Penuh
- **Mekanisme**: Jika seluruh kode 1..300 sedang terpakai pada transaksi pending aktif, query menghasilkan `v_unique_code IS NULL`.
- **Hasil**: Fungsi melemparkan exception `"Antrean pembayaran penuh, coba beberapa menit lagi"` secara atomik. Stok produk **TIDAK** berkurang.

### Skenario 5: Idempotensi Mutasi Ganda
- **Mekanisme**: Constraint `payment_mutations_source_ref_unique (source, external_ref)` dan klausa `ON CONFLICT DO NOTHING`.
- **Hasil**: Jika mutasi yang sama dikirimkan dua kali (misal retry webhook), sistem langsung mendeteksi baris yang sudah ada dan mengembalikan status `already_processed` tanpa melakukan approve ulang atau mengubah stok.

### Skenario 6: Pembayaran Masuk Setelah Transaksi Kedaluwarsa
- **Mekanisme**: Batas waktu pencocokan adalah `p_received_at <= (expired_at + 2 minutes grace period)`.
- **Hasil**: Jika uang masuk setelah lewat masa grace period, transaksi **TIDAK** di-approve otomatis. Mutasi dicatat sebagai `'unmatched'` dengan catatan `"Nominal cocok dengan transaksi kedaluwarsa #TRX-..., butuh keputusan admin"` agar admin dapat mereview dan menghubungkannya secara manual.

### Skenario 7: Proteksi Hak Akses RLS & RPC Admin (AAL2)
- Customer mencoba memanggil `verify_payment_by_amount` -> **Ditolak (42501)**.
- Customer mencoba memanggil `admin_update_transaction_status` -> **Ditolak (42501)**.
- Admin tanpa verifikasi 2FA (AAL2) mencoba mengubah status transaksi -> **Ditolak (42501)**.
- Mutasi tabel `payment_mutations` hanya bisa dibaca (`SELECT`) oleh admin berstatus AAL2.

---

## 3. Kesimpulan Audit
Sistem Pembayaran QRIS Statis + Kode Unik pada proyek DigiQ telah memenuhi seluruh standar arsitektur keamanan, prinsip zero-trust client, dan keandalan data finansial digital.
