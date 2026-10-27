# Task 06: QRIS Statis "kopi sat" + Kode Unik & Verifikasi Mandiri

## 1. Identitas QRIS Proyek (Resmi)
Sistem DigiQ menggunakan QRIS resmi yang diekstrak dari gambar proyek:
- **Nama Merchant (Tag 59)**: `kopi sat`
- **NMID (Tag 51 sub-tag 02)**: `ID1026516422080`
- **Sub-ID / Terminal**: `A01`
- **Dicetak oleh (Acquirer PAN Tag 26)**: `93600915` (Versi cetak: `1.0.27.10.26`)
- **Raw String EMVCo Statis**:
  ```text
  00020101021126570011ID.DANA.WWW011893600915302435049402090243504940303UMI51440014ID.CO.QRIS.WWW0215ID10265164220800303UMI5204581353033605802ID5908kopi sat6015Kab. Nanggroe A6105245526304F95A
  ```
- **File Asset Gambar**: [assets/images/qris_kopi_sat.jpg](file:///d:/PROJEK%20FAN%20DEV/digiq/assets/images/qris_kopi_sat.jpg)

## 2. File Terkait
- [supabase/002_qris_unique_code.sql](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/002_qris_unique_code.sql)
- [supabase/functions/payment-webhook/index.ts](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/functions/payment-webhook/index.ts)
- [lib/services/qris_service.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/services/qris_service.dart)
- [lib/models/transaction_model.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/models/transaction_model.dart)
- [lib/models/payment_mutation_model.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/models/payment_mutation_model.dart)
- [lib/services/transaction_service.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/services/transaction_service.dart)
- [lib/widgets/qris_modal.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/widgets/qris_modal.dart)
- [lib/screens/admin_dashboard_screen.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/admin_dashboard_screen.dart)
- [test/qris_service_test.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/test/qris_service_test.dart)

## 3. Konsep Sistem & Alur Kerja
1. **Harga + Kode Unik = Total Bayar**:
   Contoh: Produk Rp10.000 + Kode Unik Rp300 = Total Rp10.300.
2. **Dynamic QRIS Injection**:
   Sistem membaca raw string EMVCo `kopi sat`, lalu:
   - Mengubah Tag `01` dari `"11"` (statis) ke `"12"` (dinamis).
   - Menghapus Tag `54` lama (jika ada), lalu menyisipkan Tag `54` baru dengan nilai nominal `total_amount` (misal `"540510300"`) tepat sebelum Tag `58` (Country Code).
   - Menghitung ulang CRC16/CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflect, XOR out 0x0000) atas payload hingga `"6304"`, dan menambahkan 4 digit HEX checksum di akhir.
3. **Partial Unique Index**:
   ```sql
   CREATE UNIQUE INDEX idx_transactions_pending_total_amount
     ON public.transactions(total_amount)
     WHERE status = 'pending';
   ```
   Menjamin tidak ada dua transaksi berstatus pending dengan nominal sama yang aktif bersamaan.
4. **Verifikasi Mandiri & Idempoten**:
   RPC `verify_payment_by_amount` menerima mutasi dari webhook atau input manual admin:
   - Idempoten pada `UNIQUE(source, external_ref)`.
   - Mencocokkan transaksi pending dengan `total_amount = p_amount` pada rentang waktu `p_received_at >= (created_at - 1 menit)` dan `p_received_at <= (expired_at + 2 menit grace period)`.
   - Bila tepat satu cocok: transaksi otomatis sukses, dicatat `verified_by = 'auto'/'manual'/'webhook'`, dan mutasi menjadi `'matched'`.
   - Bila tidak ada transaksi pending cocok: mutasi dicatat sebagai `'unmatched'` dengan catatan audit, tanpa pernah menaikkan status transaksi secara sembarangan.

## 4. UI Customer & Admin
- **Customer Modal (`QrisModal`)**:
  - Header resmi `kopi sat`, NMID `ID1026516422080 • A01`.
  - Render QR code dinamis menggunakan `QrImageView` (`qr_flutter`).
  - Toggle antara QR Dinamis (nominal otomatis terisi) vs QR Statis Asli (input manual).
  - Rincian biaya: Harga + Kode Unik = Total Bayar, tombol "Salin Nominal", badge peringatan 3 digit terakhir.
  - Countdown timer real-time menuju `expired_at`, tombol "Batalkan Pesanan", dan auto-dismiss saat transaksi sukses/gagal via Supabase stream.
- **Admin Dashboard**:
  - Highlight 3 digit kode unik pada kartu transaksi pending.
  - Form pencocokan/simulasi mutasi masuk.
  - Daftar mutasi `unmatched` dengan aksi "Hubungkan & Approve Manual" atau "Abaikan".
  - Tab Pengaturan QRIS: preview QR code aktif `kopi sat`, editor payload statis dengan verifikasi CRC16 otomatis, pengaturan rentang kode unik (1-300), dan TTL menit.

## 5. Status Aktual
**SELESAI (100% Verified)**: Unit test lulus 100%, `flutter analyze` 0 issues, skema database dan Edge function webhook siap produksi.
