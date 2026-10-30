// lib/services/app_language.dart
import 'package:flutter/foundation.dart';

enum AppLang { id, en }

class AppLanguage {
  static final ValueNotifier<AppLang> current = ValueNotifier<AppLang>(AppLang.id);

  static AppLang get lang => current.value;
  static bool get isId => current.value == AppLang.id;
  static bool get isEn => current.value == AppLang.en;

  static void setLanguage(AppLang newLang) {
    if (current.value != newLang) {
      current.value = newLang;
    }
  }

  static void toggleLanguage() {
    current.value = isId ? AppLang.en : AppLang.id;
  }

  static final Map<String, Map<AppLang, String>> _localizedValues = {
    // Header & Branding
    'tagline': {
      AppLang.id: 'Produk Digital, Bayar via QRIS',
      AppLang.en: 'Digital Products, Pay via QRIS',
    },
    'footer_branding': {
      AppLang.id: 'DigiQ Official Store',
      AppLang.en: 'DigiQ Official Store',
    },

    // Login Screen
    'welcome_title': {
      AppLang.id: 'Selamat Datang 👋',
      AppLang.en: 'Welcome Back 👋',
    },
    'welcome_subtitle': {
      AppLang.id: 'Masuk ke akun DigiQ Anda',
      AppLang.en: 'Sign in to your DigiQ account',
    },
    'email_username_label': {
      AppLang.id: 'Email / Username',
      AppLang.en: 'Email / Username',
    },
    'email_username_hint': {
      AppLang.id: 'email@kamu.com atau username',
      AppLang.en: 'email@example.com or username',
    },
    'password_label': {
      AppLang.id: 'Password',
      AppLang.en: 'Password',
    },
    'password_hint': {
      AppLang.id: 'Masukkan password',
      AppLang.en: 'Enter your password',
    },
    'remember_me': {
      AppLang.id: 'Ingat saya',
      AppLang.en: 'Remember me',
    },
    'forgot_password': {
      AppLang.id: 'Lupa password?',
      AppLang.en: 'Forgot password?',
    },
    'login_btn': {
      AppLang.id: 'Masuk',
      AppLang.en: 'Sign In',
    },
    'or_divider': {
      AppLang.id: 'atau',
      AppLang.en: 'or',
    },
    'create_account_btn': {
      AppLang.id: 'Daftar Akun Baru',
      AppLang.en: 'Create New Account',
    },
    'admin_hint_prefix': {
      AppLang.id: 'Admin: gunakan ',
      AppLang.en: 'Admin: use ',
    },
    'email_required': {
      AppLang.id: 'Email/username wajib diisi',
      AppLang.en: 'Email or username is required',
    },
    'password_required': {
      AppLang.id: 'Password wajib diisi',
      AppLang.en: 'Password is required',
    },
    'login_failed': {
      AppLang.id: 'Login gagal. Periksa kembali email dan sandi Anda.',
      AppLang.en: 'Sign in failed. Please check your email and password.',
    },
    'profile_load_failed': {
      AppLang.id: 'Gagal memuat profil. Coba login ulang.',
      AppLang.en: 'Failed to load profile. Please sign in again.',
    },
    'verify_email_btn': {
      AppLang.id: 'Verifikasi',
      AppLang.en: 'Verify',
    },

    // Register Screen
    'register_title': {
      AppLang.id: 'Buat Akun Baru',
      AppLang.en: 'Create New Account',
    },
    'register_subtitle': {
      AppLang.id: 'Daftar dan nikmati kemudahan belanja produk digital',
      AppLang.en: 'Sign up and enjoy easy digital product shopping',
    },
    'name_label': {
      AppLang.id: 'Nama Lengkap',
      AppLang.en: 'Full Name',
    },
    'name_hint': {
      AppLang.id: 'Nama lengkap kamu',
      AppLang.en: 'Your full name',
    },
    'name_required': {
      AppLang.id: 'Nama wajib diisi',
      AppLang.en: 'Full name is required',
    },
    'name_min': {
      AppLang.id: 'Nama minimal 3 karakter',
      AppLang.en: 'Name must be at least 3 characters',
    },
    'username_label': {
      AppLang.id: 'Username',
      AppLang.en: 'Username',
    },
    'username_hint': {
      AppLang.id: 'username_kamu',
      AppLang.en: 'your_username',
    },
    'username_example': {
      AppLang.id: 'Contoh: user123',
      AppLang.en: 'e.g. user123',
    },
    'email_label': {
      AppLang.id: 'Email',
      AppLang.en: 'Email',
    },
    'phone_label': {
      AppLang.id: 'Nomor HP',
      AppLang.en: 'Phone Number',
    },
    'phone_required': {
      AppLang.id: 'Nomor HP wajib diisi',
      AppLang.en: 'Phone number is required',
    },
    'phone_prefix_error': {
      AppLang.id: 'Nomor HP harus diawali 08',
      AppLang.en: 'Phone number must start with 08',
    },
    'phone_min_error': {
      AppLang.id: 'Nomor HP minimal 10 digit',
      AppLang.en: 'Phone number must be at least 10 digits',
    },
    'phone_max_error': {
      AppLang.id: 'Nomor HP maksimal 13 digit',
      AppLang.en: 'Phone number must be at most 13 digits',
    },
    'password_min_hint': {
      AppLang.id: 'Minimal 8 karakter',
      AppLang.en: 'At least 8 characters',
    },
    'password_min_error': {
      AppLang.id: 'Password minimal 8 karakter',
      AppLang.en: 'Password must be at least 8 characters',
    },
    'confirm_password_label': {
      AppLang.id: 'Konfirmasi Password',
      AppLang.en: 'Confirm Password',
    },
    'confirm_password_hint': {
      AppLang.id: 'Ulangi password',
      AppLang.en: 'Repeat password',
    },
    'confirm_password_required': {
      AppLang.id: 'Konfirmasi password wajib diisi',
      AppLang.en: 'Please confirm your password',
    },
    'passwords_not_match': {
      AppLang.id: 'Password tidak cocok',
      AppLang.en: 'Passwords do not match',
    },
    'terms_prefix': {
      AppLang.id: 'Saya menyetujui ',
      AppLang.en: 'I agree to the ',
    },
    'terms_link': {
      AppLang.id: 'Syarat & Ketentuan',
      AppLang.en: 'Terms & Conditions',
    },
    'and_connector': {
      AppLang.id: ' serta ',
      AppLang.en: ' and ',
    },
    'privacy_link': {
      AppLang.id: 'Kebijakan Privasi',
      AppLang.en: 'Privacy Policy',
    },
    'digiq_suffix': {
      AppLang.id: ' DigiQ.',
      AppLang.en: ' of DigiQ.',
    },
    'register_btn': {
      AppLang.id: 'Daftar Sekarang',
      AppLang.en: 'Register Now',
    },
    'already_have_account': {
      AppLang.id: 'Sudah punya akun? ',
      AppLang.en: 'Already have an account? ',
    },
    'sign_in_link': {
      AppLang.id: 'Masuk di sini',
      AppLang.en: 'Sign in here',
    },
    'terms_error': {
      AppLang.id: 'Harap setujui syarat & ketentuan terlebih dahulu.',
      AppLang.en: 'Please agree to terms & conditions first.',
    },

    // Forgot Password Screen
    'forgot_pwd_title': {
      AppLang.id: 'Lupa Kata Sandi?',
      AppLang.en: 'Forgot Password?',
    },
    'forgot_pwd_desc': {
      AppLang.id: 'Masukkan alamat email Anda dan kami akan mengirimkan tautan untuk mengatur ulang kata sandi.',
      AppLang.en: 'Enter your email address and we will send a link to reset your password.',
    },
    'email_address_label': {
      AppLang.id: 'Alamat Email',
      AppLang.en: 'Email Address',
    },
    'send_reset_link': {
      AppLang.id: 'Kirim Tautan Reset',
      AppLang.en: 'Send Reset Link',
    },
    'resend_in_cooldown': {
      AppLang.id: 'Kirim ulang dalam ',
      AppLang.en: 'Resend in ',
    },
    'back_to_login': {
      AppLang.id: 'Kembali ke Login',
      AppLang.en: 'Back to Sign In',
    },
    'check_email_title': {
      AppLang.id: 'Cek Email Anda',
      AppLang.en: 'Check Your Email',
    },
    'check_email_desc': {
      AppLang.id: 'Jika email terdaftar, tautan reset kata sandi telah dikirim. Silakan periksa kotak masuk atau folder spam Anda.',
      AppLang.en: 'If the email is registered, a password reset link has been sent. Please check your inbox or spam folder.',
    },
    'resend_link_btn': {
      AppLang.id: 'Kirim Ulang Tautan',
      AppLang.en: 'Resend Link',
    },
    'change_email_btn': {
      AppLang.id: 'Ubah Email',
      AppLang.en: 'Change Email',
    },

    // Set New Password Screen
    'set_new_pwd_title': {
      AppLang.id: 'Buat Kata Sandi Baru',
      AppLang.en: 'Create New Password',
    },
    'set_new_pwd_desc': {
      AppLang.id: 'Masukkan kata sandi baru Anda di bawah. Pastikan minimal 8 karakter.',
      AppLang.en: 'Enter your new password below. Make sure it has at least 8 characters.',
    },
    'new_password_label': {
      AppLang.id: 'Kata Sandi Baru',
      AppLang.en: 'New Password',
    },
    'save_password_btn': {
      AppLang.id: 'Simpan Kata Sandi Baru',
      AppLang.en: 'Save New Password',
    },
    'pwd_changed_success_title': {
      AppLang.id: 'Kata Sandi Berhasil Diubah!',
      AppLang.en: 'Password Changed Successfully!',
    },
    'pwd_changed_redirect': {
      AppLang.id: 'Anda akan dialihkan ke halaman login dalam beberapa saat...',
      AppLang.en: 'You will be redirected to the sign in page in a moment...',
    },
    'pwd_changed_snack': {
      AppLang.id: 'Kata sandi berhasil diubah. Silakan masuk dengan kata sandi baru Anda.',
      AppLang.en: 'Password successfully changed. Please sign in with your new password.',
    },

    // Email Verification Screen
    'verify_email_waiting_title': {
      AppLang.id: 'Cek Gmail Anda',
      AppLang.en: 'Check Your Gmail',
    },
    'verify_email_waiting_desc_1': {
      AppLang.id: 'Kami telah mengirimkan tautan aktivasi akun ke ',
      AppLang.en: 'We have sent an account activation link to ',
    },
    'verify_email_waiting_desc_2': {
      AppLang.id: '.\nSilakan buka aplikasi Gmail dan klik tombol verifikasi untuk mengaktifkan akun DigiQ Anda.',
      AppLang.en: '.\nPlease open your Gmail app and click the verification button to activate your DigiQ account.',
    },
    'verify_email_auto_redirect': {
      AppLang.id: 'Layar ini otomatis mengalihkan ke Beranda begitu link di Gmail diklik.',
      AppLang.en: 'This screen automatically redirects to Home once the link in Gmail is clicked.',
    },
    'verify_email_resend_btn': {
      AppLang.id: 'Kirim Ulang Email Aktivasi',
      AppLang.en: 'Resend Activation Email',
    },
    'verify_email_verified_title': {
      AppLang.id: 'Email Berhasil Diverifikasi!',
      AppLang.en: 'Email Verified Successfully!',
    },
    'verify_email_verified_desc': {
      AppLang.id: 'Akun DigiQ Anda sudah aktif dan siap digunakan untuk bertransaksi.',
      AppLang.en: 'Your DigiQ account is now active and ready for transactions.',
    },
    'verify_email_error_title': {
      AppLang.id: 'Tautan Kedaluwarsa atau Tidak Valid',
      AppLang.en: 'Link Expired or Invalid',
    },
    'back_to_login_btn': {
      AppLang.id: 'Kembali ke Layar Masuk',
      AppLang.en: 'Back to Sign In Screen',
    },

    // Customer Dashboard Navigation
    'nav_home': {
      AppLang.id: 'Beranda',
      AppLang.en: 'Home',
    },
    'nav_cart': {
      AppLang.id: 'Keranjang',
      AppLang.en: 'Cart',
    },
    'nav_history': {
      AppLang.id: 'Riwayat',
      AppLang.en: 'History',
    },
    'nav_profile': {
      AppLang.id: 'Profil',
      AppLang.en: 'Profile',
    },

    // Customer Home & Products
    'greeting_prefix': {
      AppLang.id: 'Halo, ',
      AppLang.en: 'Hello, ',
    },
    'greeting_subtitle': {
      AppLang.id: 'Mau beli akun apa hari ini?',
      AppLang.en: 'What account would you like today?',
    },
    'search_hint': {
      AppLang.id: 'Cari akun Netflix, ChatGPT, Spotify, Google...',
      AppLang.en: 'Search Netflix, ChatGPT, Spotify, Google accounts...',
    },
    'today_promo_badge': {
      AppLang.id: '🎉 PROMO HARI INI',
      AppLang.en: '🎉 TODAY\'S PROMO',
    },
    'today_promo_title': {
      AppLang.id: 'Bayar via QRIS,\nHemat Lebih Banyak!',
      AppLang.en: 'Pay via QRIS,\nSave Much More!',
    },
    'premium_catalog': {
      AppLang.id: 'Katalog Akun Premium',
      AppLang.en: 'Premium Account Catalog',
    },
    'ready_accounts_suffix': {
      AppLang.id: 'Akun Ready',
      AppLang.en: 'Ready',
    },
    'added_to_cart': {
      AppLang.id: 'ditambahkan ke keranjang',
      AppLang.en: 'added to cart',
    },
    'view_action': {
      AppLang.id: 'Lihat',
      AppLang.en: 'View',
    },
    'all_products': {
      AppLang.id: 'Semua Akun Digital',
      AppLang.en: 'All Digital Accounts',
    },
    'stock_label': {
      AppLang.id: 'Stok: ',
      AppLang.en: 'Stock: ',
    },
    'ready_stock': {
      AppLang.id: 'Tersedia',
      AppLang.en: 'Available',
    },
    'out_of_stock': {
      AppLang.id: 'Habis',
      AppLang.en: 'Sold Out',
    },
    'buy_now': {
      AppLang.id: 'Beli Sekarang',
      AppLang.en: 'Buy Now',
    },
    'add_cart': {
      AppLang.id: 'Tambah Keranjang',
      AppLang.en: 'Add to Cart',
    },
    'product_detail': {
      AppLang.id: 'Detail Produk',
      AppLang.en: 'Product Details',
    },

    // Profile & Customer
    'customer_badge': {
      AppLang.id: 'Pelanggan DigiQ',
      AppLang.en: 'DigiQ Customer',
    },
    'about_app': {
      AppLang.id: 'Tentang Aplikasi',
      AppLang.en: 'About App',
    },
    'notifications': {
      AppLang.id: 'Notifikasi',
      AppLang.en: 'Notifications',
    },
    'help_faq': {
      AppLang.id: 'Bantuan & FAQ',
      AppLang.en: 'Help & FAQ',
    },
    'language_setting': {
      AppLang.id: 'Bahasa (Indonesia)',
      AppLang.en: 'Language (English)',
    },
    'edit_profile': {
      AppLang.id: 'Edit Profil',
      AppLang.en: 'Edit Profile',
    },
    'change_password': {
      AppLang.id: 'Ubah Sandi',
      AppLang.en: 'Change Password',
    },
    'account_info': {
      AppLang.id: 'Informasi Akun',
      AppLang.en: 'Account Information',
    },
    'account_balance': {
      AppLang.id: 'Saldo DigiQ',
      AppLang.en: 'DigiQ Balance',
    },

    // Admin Dashboard
    'admin_store_title': {
      AppLang.id: 'DigiQ Store',
      AppLang.en: 'DigiQ Store',
    },
    'admin_store_active': {
      AppLang.id: 'Toko Aktif • QRIS',
      AppLang.en: 'Store Active • QRIS',
    },
    'nav_admin_home': {
      AppLang.id: 'Beranda',
      AppLang.en: 'Home',
    },
    'nav_admin_catalog': {
      AppLang.id: 'Katalog',
      AppLang.en: 'Catalog',
    },
    'nav_admin_trx': {
      AppLang.id: 'Transaksi',
      AppLang.en: 'Transactions',
    },
    'nav_admin_store': {
      AppLang.id: 'Toko Admin',
      AppLang.en: 'Admin Store',
    },
    'admin_logout_title': {
      AppLang.id: 'Keluar',
      AppLang.en: 'Sign Out',
    },
    'admin_logout_confirm': {
      AppLang.id: 'Yakin ingin keluar dari akun Admin?',
      AppLang.en: 'Are you sure you want to sign out from Admin account?',
    },
    'admin_security_title': {
      AppLang.id: 'Keamanan & Autentikasi 2-User',
      AppLang.en: 'Security & 2-User Authentication',
    },
    'admin_security_sub': {
      AppLang.id: 'Akun Admin terlindungi enkripsi',
      AppLang.en: 'Admin account is secured with encryption',
    },
    'admin_about_title': {
      AppLang.id: 'Tentang Aplikasi DigiQ',
      AppLang.en: 'About DigiQ App',
    },
    'admin_about_sub': {
      AppLang.id: 'Versi 1.0.0 (Production Release)',
      AppLang.en: 'Version 1.0.0 (Production Release)',
    },
    'language_tile_title': {
      AppLang.id: 'Bahasa / Language',
      AppLang.en: 'Language / Bahasa',
    },
    'language_tile_sub': {
      AppLang.id: 'Beralih antara Bahasa Indonesia dan English',
      AppLang.en: 'Switch between Bahasa Indonesia and English',
    },
    'language_changed_toast': {
      AppLang.id: 'Bahasa diubah ke Bahasa Indonesia',
      AppLang.en: 'Language changed to English',
    },

    // Dialogs & Actions
    'logout_confirm_title': {
      AppLang.id: 'Konfirmasi Keluar',
      AppLang.en: 'Confirm Sign Out',
    },
    'logout_confirm_desc': {
      AppLang.id: 'Apakah Anda yakin ingin keluar dari akun ini?',
      AppLang.en: 'Are you sure you want to sign out?',
    },
    'cancel': {
      AppLang.id: 'Batal',
      AppLang.en: 'Cancel',
    },
    'logout': {
      AppLang.id: 'Keluar',
      AppLang.en: 'Sign Out',
    },
    'close': {
      AppLang.id: 'Tutup',
      AppLang.en: 'Close',
    },
    // Product & Catalog Details
    'no_products_found': {
      AppLang.id: 'Produk tidak ditemukan',
      AppLang.en: 'No products found',
    },
    'no_products_desc': {
      AppLang.id: 'Coba cari dengan kata kunci lain atau periksa kategori yang dipilih.',
      AppLang.en: 'Try searching with different keywords or check the selected category.',
    },
    'ready_accounts_count': {
      AppLang.id: 'Akun Siap Pakai',
      AppLang.en: 'Ready Accounts',
    },
    'price_label': {
      AppLang.id: 'Harga',
      AppLang.en: 'Price',
    },
    'add_to_cart_btn': {
      AppLang.id: '+ Keranjang',
      AppLang.en: '+ Cart',
    },
    'buy_action_btn': {
      AppLang.id: 'Beli',
      AppLang.en: 'Buy',
    },
    'creating_transaction': {
      AppLang.id: 'Membuat transaksi...',
      AppLang.en: 'Creating transaction...',
    },

    // Cart Screen
    'cart_title': {
      AppLang.id: 'Keranjang Belanja',
      AppLang.en: 'Shopping Cart',
    },
    'cart_empty_title': {
      AppLang.id: 'Keranjang kosong',
      AppLang.en: 'Your cart is empty',
    },
    'cart_empty_desc': {
      AppLang.id: 'Yuk, tambahkan produk favoritmu!',
      AppLang.en: 'Go ahead, add your favorite products!',
    },
    'browse_products': {
      AppLang.id: 'Lihat Produk',
      AppLang.en: 'Browse Products',
    },
    'clear_cart': {
      AppLang.id: 'Kosongkan Keranjang',
      AppLang.en: 'Clear Cart',
    },
    'clear_cart_confirm': {
      AppLang.id: 'Yakin ingin menghapus semua item dari keranjang?',
      AppLang.en: 'Are you sure you want to remove all items from your cart?',
    },
    'remove_all': {
      AppLang.id: 'Hapus Semua',
      AppLang.en: 'Remove All',
    },
    'pay_with_qris': {
      AppLang.id: 'Bayar dengan QRIS',
      AppLang.en: 'Pay with QRIS',
    },
    'total_payment': {
      AppLang.id: 'Total Pembayaran',
      AppLang.en: 'Total Payment',
    },

    // History Screen
    'history_title': {
      AppLang.id: 'Riwayat Transaksi',
      AppLang.en: 'Transaction History',
    },
    'history_empty_title': {
      AppLang.id: 'Belum ada transaksi',
      AppLang.en: 'No transactions yet',
    },
    'history_empty_desc': {
      AppLang.id: 'Transaksi yang berhasil akan muncul di sini',
      AppLang.en: 'Successful transactions will appear here',
    },
    'status_pending': {
      AppLang.id: 'Menunggu',
      AppLang.en: 'Pending',
    },
    'status_success': {
      AppLang.id: 'Berhasil',
      AppLang.en: 'Success',
    },
    'status_expired': {
      AppLang.id: 'Kedaluwarsa',
      AppLang.en: 'Expired',
    },
    'status_cancelled': {
      AppLang.id: 'Batal',
      AppLang.en: 'Cancelled',
    },

    // Notifications & Info
    'no_notifications_title': {
      AppLang.id: 'Belum Ada Notifikasi Baru',
      AppLang.en: 'No New Notifications',
    },
    'no_notifications_desc': {
      AppLang.id: 'Pembaruan status pesanan dan informasi akun Anda akan muncul di sini.',
      AppLang.en: 'Order updates and account notices will appear here.',
    },
    'understand_btn': {
      AppLang.id: 'Mengerti',
      AppLang.en: 'Got It',
    },

    // Admin Dashboard
    'admin_digital_catalog': {
      AppLang.id: 'Katalog Produk Digital',
      AppLang.en: 'Digital Product Catalog',
    },
    'admin_ready_sale_suffix': {
      AppLang.id: 'produk siap dijual via QRIS',
      AppLang.en: 'products ready for sale via QRIS',
    },
    'admin_manage_all': {
      AppLang.id: 'Kelola Semua',
      AppLang.en: 'Manage All',
    },
    'admin_today_transactions': {
      AppLang.id: 'Transaksi Masuk Hari Ini',
      AppLang.en: 'Today\'s Transactions',
    },
    'admin_success_trx': {
      AppLang.id: 'Berhasil (QRIS)',
      AppLang.en: 'Successful (QRIS)',
    },
    'admin_pending_trx': {
      AppLang.id: 'Pending Aktif',
      AppLang.en: 'Active Pending',
    },
    'admin_total_omset': {
      AppLang.id: 'Total Pendapatan',
      AppLang.en: 'Total Revenue',
    },
    'admin_recent_notif': {
      AppLang.id: 'Notifikasi Transaksi Terakhir',
      AppLang.en: 'Recent Transaction Notifications',
    },
    'admin_no_trx_today': {
      AppLang.id: 'Belum ada transaksi QRIS hari ini.',
      AppLang.en: 'No QRIS transactions today.',
    },
    'admin_payment_received': {
      AppLang.id: 'PEMBAYARAN QRIS MASUK!',
      AppLang.en: 'QRIS PAYMENT RECEIVED!',
    },
    'admin_add_product_now': {
      AppLang.id: 'Tambah Produk Sekarang',
      AppLang.en: 'Add Product Now',
    },
    'admin_showing_products': {
      AppLang.id: 'Menampilkan',
      AppLang.en: 'Showing',
    },
    'admin_products_suffix': {
      AppLang.id: 'Produk',
      AppLang.en: 'Products',
    },
    'admin_save_qris_settings': {
      AppLang.id: 'Simpan Pengaturan QRIS',
      AppLang.en: 'Save QRIS Settings',
    },
    'admin_delete_product_title': {
      AppLang.id: 'Hapus Akun?',
      AppLang.en: 'Delete Product?',
    },
    'admin_delete_product_confirm': {
      AppLang.id: 'Apakah Anda yakin ingin menghapus produk ini dari katalog toko?',
      AppLang.en: 'Are you sure you want to remove this product from the store catalog?',
    },
    'admin_delete_action': {
      AppLang.id: 'Hapus',
      AppLang.en: 'Delete',
    },
    'admin_unmatched_mutations': {
      AppLang.id: 'Mutasi Masuk Belum Terverifikasi (Unmatched)',
      AppLang.en: 'Unmatched Incoming Mutations',
    },
    'admin_no_pending_trx': {
      AppLang.id: 'Tidak ada transaksi pending yang aktif.',
      AppLang.en: 'No active pending transactions.',
    },
    'admin_match_mutation': {
      AppLang.id: 'Hubungkan Mutasi',
      AppLang.en: 'Match Mutation',
    },
  };

  static String t(String key) {
    final entry = _localizedValues[key];
    if (entry == null) return key;
    return entry[current.value] ?? entry[AppLang.id] ?? key;
  }
}
