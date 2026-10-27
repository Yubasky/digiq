# Task 04: Transaction RPC & Atomic Stock Management

## 1. Tujuan
Menjamin transaksi pembelian diproses secara atomik, aman dari race condition konkurensi antar pembeli, membatasi spam transaksi pending, serta mengembalikan stok produk secara otomatis jika transaksi dibatalkan atau kedaluwarsa.

## 2. File Terkait
- [supabase/002_qris_unique_code.sql](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/002_qris_unique_code.sql)
- [lib/models/transaction_model.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/models/transaction_model.dart)
- [lib/services/transaction_service.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/services/transaction_service.dart)

## 3. Logika Atomik & Keputusan Desain
1. **Lazy Expiration di Awal Transaksi**:
   Setiap pemanggilan `create_purchase_transaction` mengeksekusi `PERFORM public.expire_pending_transactions();` terlebih dahulu agar transaksi yang lewat masa tenggang 2 menit langsung dikembalikan stoknya.
2. **Anti-Spam Pending Transaction**:
   Maksimal 3 transaksi `pending` per user. Bila user mencoba membuat yang ke-4:
   `"Anda masih memiliki 3 transaksi yang belum dibayar. Selesaikan atau batalkan terlebih dahulu."`
3. **Penguncian Baris (FOR UPDATE)**:
   Baris produk dikunci dengan `SELECT * FROM public.products WHERE id = p_product_id FOR UPDATE;`. Jika stok `<= 0`, transaksi langsung ditolak sebelum kode unik digenerate.
4. **Alokasi Kode Unik & Retry Loop**:
   Loop retry hingga 5 kali untuk memilih kode unik acak dari `generate_series(v_min, v_max)` yang belum pernah terpakai pada transaksi pending lainnya (`NOT EXISTS ... total_amount = base + code`).
   Pengurangan stok (`UPDATE products SET stock = stock - 1`) dilakukan HANYA setelah baris transaksi berhasil di-insert.
5. **Pembatalan Mandiri (`cancel_my_pending_transaction`)**:
   Hanya pemilik transaksi (`user_id = auth.uid()`) yang dapat membatalkan transaksinya saat masih `pending`. Transaksi diubah ke `failed` dan stok produk dikembalikan `+1` tepat satu kali.

## 4. Cara Uji
1. Customer checkout pesanan -> stok berkurang 1, status transaksi `pending`.
2. Customer membatalkan pesanan dari modal QRIS -> status berubah ke `failed`, stok produk bertambah 1 kembali.
3. Dua user checkout produk yang sama secara bersamaan -> masing-masing mendapatkan `unique_code` dan `total_amount` berbeda tanpa race condition.

## 5. Status Aktual
**SELESAI (100% Verified)**: Logika atomik diterapkan di SQL dan diuji via Flutter unit test.
