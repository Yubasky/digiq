// lib/services/auth_service.dart
//
// Alur 2FA yang dipilih: TOTP (Time-based One-Time Password)
// Alasan: TOTP berjalan offline setelah enrollment sehingga tidak bergantung
// pada pengiriman email/SMS, lebih andal untuk aplikasi payment digital.
//
// Alur login:
//  1. signInWithPassword → sesi aal1
//  2. cek apakah faktor TOTP sudah terdaftar (mfa.listFactors)
//  3a. Jika sudah → challenge + verify kode 6 digit → sesi naik ke aal2
//  3b. Jika belum (customer baru) → enroll TOTP → tampilkan QR → verify → aal2
//  4. Admin WAJIB aal2; jika tidak, aksi admin ditolak di server.

import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import '../models/profile_model.dart';

/// Hasil operasi AuthService untuk feedback UI.
class AuthResult {
  final bool success;
  final String? message;
  final ProfileModel? profile;

  /// Saat login membutuhkan verifikasi TOTP, ini berisi factor ID.
  final String? mfaFactorId;

  /// Saat enrollment TOTP baru, ini berisi TOTP URI (untuk QR code).
  final String? totpUri;

  /// Factor ID saat enrollment, dipakai untuk verify.
  final String? enrollFactorId;

  const AuthResult({
    required this.success,
    this.message,
    this.profile,
    this.mfaFactorId,
    this.totpUri,
    this.enrollFactorId,
  });
}

class AuthService {
  static SupabaseClient get _sb => SupabaseConfig.supabase;

  /// Default redirect URI custom scheme untuk verifikasi email PKCE & deep link Supabase
  static const String kAuthRedirectUri = 'digiq://auth-callback';
  static const String kAuthCallbackUrl = kAuthRedirectUri;

  // ─── Sign Up ────────────────────────────────────────────────────────────────

  /// Daftar akun baru dengan emailRedirectTo custom scheme digiq://auth-callback.
  /// Setelah sukses, profil dibuat otomatis via trigger DB.
  static Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    String? emailRedirectTo,
  }) async {
    try {
      final res = await _sb.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: emailRedirectTo ?? kAuthRedirectUri,
        data: {
          'full_name': fullName.trim(),
          'phone': phone.trim(),
        },
      );

      if (res.user == null) {
        return const AuthResult(
          success: false,
          message: 'Pendaftaran gagal. Silakan coba lagi.',
        );
      }

      // Beri jeda agar trigger handle_new_user di DB selesai dieksekusi
      await Future<void>.delayed(const Duration(milliseconds: 500));

      return const AuthResult(
        success: true,
        message: 'Akun berhasil dibuat! Silakan verifikasi email Anda.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(success: false, message: 'Terjadi kesalahan: $e');
    }
  }

  // ─── Resend Verification Email ──────────────────────────────────────────────

  /// Kirim ulang email aktivasi/verifikasi pendaftaran dengan rate limit handling.
  static Future<AuthResult> resendVerificationEmail(
    String email, {
    String? emailRedirectTo,
  }) async {
    try {
      await _sb.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: emailRedirectTo ?? kAuthRedirectUri,
      );

      return const AuthResult(
        success: true,
        message: 'Email verifikasi baru berhasil dikirim. Periksa kotak masuk atau spam di Gmail Anda.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(success: false, message: 'Gagal mengirim ulang email verifikasi: $e');
    }
  }

  /// Cek apakah pengguna saat ini sudah mengonfirmasi email
  static bool get isCurrentUserEmailVerified {
    final user = _sb.auth.currentUser;
    return user != null && user.emailConfirmedAt != null;
  }

  /// Dapatkan email user yang sedang login atau sesi aktif
  static String? get currentUserEmail => _sb.auth.currentUser?.email;

  // ─── Sign In (Email & Password Langsung) ────────────────────────────────────

  /// Login email & password standar (1 langkah, tanpa MFA/TOTP).
  static Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _sb.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      if (res.user == null) {
        return const AuthResult(
          success: false,
          message: 'Login gagal. Periksa kembali email dan password.',
        );
      }

      final profile = await getCurrentProfile();
      return AuthResult(
        success: true,
        profile: profile,
        message: 'Login berhasil.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(success: false, message: 'Terjadi kesalahan: $e');
    }
  }

  /// Alias signInStep1 untuk kompatibilitas.
  static Future<AuthResult> signInStep1({
    required String email,
    required String password,
  }) => signIn(email: email, password: password);

  /// Login via Google / Gmail OAuth dari Supabase.
  static Future<bool> signInWithGoogle() async {
    try {
      return await _sb.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'digiq://login-callback',
      );
    } catch (_) {
      return false;
    }
  }

  // ─── Profile helpers ────────────────────────────────────────────────────────

  /// Ambil profil pengguna yang sedang login.
  static Future<ProfileModel?> getCurrentProfile() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final data = await _sb
          .from('profiles')
          .select()
          .eq('id', uid)
          .single();
      return ProfileModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Ambil role dari profil (untuk routing di main.dart).
  static Future<String?> getCurrentRole() async {
    final profile = await getCurrentProfile();
    return profile?.role;
  }

  /// Cek apakah user sedang login (selalu true jika ada sesi aktif).
  static Future<bool> isAal2() async => _sb.auth.currentUser != null;

  // ─── Update profile ─────────────────────────────────────────────────────────

  /// Update nama, HP, dan/atau avatar_url.
  static Future<AuthResult> updateProfile({
    required String fullName,
    required String phone,
    String? avatarUrl,
  }) async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        return const AuthResult(success: false, message: 'Tidak terautentikasi.');
      }

      final updates = <String, dynamic>{
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'avatar_url': ?avatarUrl,
      };

      await _sb.from('profiles').update(updates).eq('id', uid);

      return const AuthResult(success: true, message: 'Profil berhasil diperbarui.');
    } catch (e) {
      return AuthResult(success: false, message: 'Gagal update profil: $e');
    }
  }

  /// Ganti password.
  static Future<AuthResult> changePassword(String newPassword) async {
    try {
      await _sb.auth.updateUser(UserAttributes(password: newPassword));
      return const AuthResult(success: true, message: 'Password berhasil diubah.');
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(success: false, message: 'Gagal ganti password: $e');
    }
  }

  // ─── Upload avatar ke Storage ────────────────────────────────────────────────

  static Future<String?> uploadAvatar(String filePath, List<int> bytes) async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return null;
      final storagePath = '$uid/avatar.jpg';

      await _sb.storage.from('avatars').uploadBinary(
        storagePath,
        Uint8List.fromList(bytes),
        fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
      );

      return _sb.storage.from('avatars').getPublicUrl(storagePath);
    } catch (_) {
      return null;
    }
  }

  // ─── Sign Out ────────────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    await _sb.auth.signOut();
  }

  // ─── Auth state stream ───────────────────────────────────────────────────────

  static Stream<AuthState> get authStateChanges =>
      _sb.auth.onAuthStateChange;

  // ─── Terjemahan pesan error ──────────────────────────────────────────────────

  /// Menerjemahkan pesan error Supabase Auth ke Bahasa Indonesia yang ramah.
  static String translateAuthError(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('over_email_send_rate_limit') ||
        lower.contains('rate limit') ||
        lower.contains('for security purposes, you can only request')) {
      return 'Terlalu banyak permintaan pengiriman email. Harap tunggu beberapa saat sebelum mencoba lagi.';
    }
    if (lower.contains('otp_expired') ||
        lower.contains('token has expired') ||
        lower.contains('email link is invalid or has expired') ||
        lower.contains('token is expired')) {
      return 'Tautan verifikasi sudah kedaluwarsa. Silakan kirim ulang email verifikasi baru.';
    }
    if (lower.contains('access_denied') || lower.contains('access denied')) {
      return 'Akses tautan verifikasi ditolak atau tautan sudah digunakan.';
    }
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials')) {
      return 'Email atau password salah.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Email belum diverifikasi. Cek kotak masuk atau spam di Gmail Anda.';
    }
    if (lower.contains('user already registered') ||
        lower.contains('already been registered')) {
      return 'Email sudah terdaftar. Silakan login.';
    }
    if (lower.contains('password should be at least')) {
      return 'Password minimal 6 karakter.';
    }
    if (lower.contains('invalid totp') || lower.contains('mfa')) {
      return 'Kode autentikator tidak valid. Coba lagi.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Koneksi internet bermasalah. Periksa jaringan Anda.';
    }
    return msg;
  }

  static String _translateAuthError(String msg) => translateAuthError(msg);
}

