# Task 03: Product Management, Catalog, & Realtime Updates

## 1. Tujuan
Menyediakan katalog produk digital (akun streaming, voucher game, pulsa, token) yang diperbarui secara realtime antara Dashboard Admin dan Dashboard Customer, dengan kontrol status aktif dan manajemen stok.

## 2. File Terkait
- [lib/models/product_model.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/models/product_model.dart)
- [lib/services/product_service.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/services/product_service.dart)
- [lib/widgets/add_product_dialog.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/widgets/add_product_dialog.dart)
- [lib/screens/admin_dashboard_screen.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/admin_dashboard_screen.dart)
- [lib/screens/customer_dashboard_screen.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/customer_dashboard_screen.dart)

## 3. Keputusan Desain
1. **Pemisahan Model & Data**: `ProductModel` memetakan langsung data dari Supabase table `products`, sementara `ProductItem` membungkus kompatibilitas ke UI lama.
2. **Realtime Broadcast**: Perubahan stok, harga, dan ketersediaan langsung disinkronkan ke pelanggan tanpa perlu refresh manual melalui stream `ProductService.watchProducts()`.
3. **Optimistic Locking**: Operasi pengurangan stok tidak pernah dilakukan di client, melainkan menggunakan `SELECT ... FOR UPDATE` di PostgreSQL.

## 4. Cara Uji
1. Buka Admin Dashboard dan Customer Dashboard di dua window/layar.
2. Ubah stok produk dari admin atau tambahkan produk baru.
3. Layar customer otomatis menampilkan pembaruan katalog secara instan.

## 5. Status Aktual
**SELESAI (100% Verified)**: Katalog realtime beroperasi mulus dan sinkron.
