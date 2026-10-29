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
      AppLang.id: 'DigiQ Official Store • Transaksi Cepat & Aman via QRIS',
      AppLang.en: 'DigiQ Official Store • Fast & Secure via QRIS',
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
    'username_label': {
      AppLang.id: 'Username',
      AppLang.en: 'Username',
    },
    'username_hint': {
      AppLang.id: 'username_kamu',
      AppLang.en: 'your_username',
    },
    'email_label': {
      AppLang.id: 'Email',
      AppLang.en: 'Email',
    },
    'phone_label': {
      AppLang.id: 'Nomor HP',
      AppLang.en: 'Phone Number',
    },
    'confirm_password_label': {
      AppLang.id: 'Konfirmasi Password',
      AppLang.en: 'Confirm Password',
    },
    'confirm_password_hint': {
      AppLang.id: 'Ulangi password',
      AppLang.en: 'Repeat password',
    },
    'terms_agreement': {
      AppLang.id: 'Saya menyetujui Syarat & Ketentuan serta Kebijakan Privasi DigiQ',
      AppLang.en: 'I agree to DigiQ Terms & Conditions and Privacy Policy',
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

    // Dashboard Navigation
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
      AppLang.id: 'Cari akun digital...',
      AppLang.en: 'Search digital accounts...',
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
  };

  static String t(String key) {
    final entry = _localizedValues[key];
    if (entry == null) return key;
    return entry[current.value] ?? entry[AppLang.id] ?? key;
  }
}
