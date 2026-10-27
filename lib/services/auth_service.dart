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
import 'package:flutter/foundation.dart';
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

  // ─── Redirect URI ────────────────────────────────────────────────────────────

  /// Default redirect URI.
  /// Web: PUBLIC_SITE_URL (dari --dart-define) atau Uri.base.origin, selalu berakhiran '/'.
  /// Mobile: digiq://auth-callback (custom scheme).
  static String get kAuthRedirectUri {
    if (!kIsWeb) return 'digiq://auth-callback';
    const site = String.fromEnvironment('PUBLIC_SITE_URL');
    final base = site.isNotEmpty ? site : Uri.base.origin;
    return base.endsWith('/') ? base : '$base/';
  }

  static String get kAuthCallbackUrl => kAuthRedirectUri;

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
        message:
            'Email verifikasi baru berhasil dikirim. Periksa kotak masuk atau spam di Gmail Anda.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(
          success: false, message: 'Gagal mengirim ulang email verifikasi: $e');
    }
  }

  // ─── Reset Password ──────────────────────────────────────────────────────────

  /// Kirim email reset password. Pesan sukses selalu netral agar tidak
  /// membocorkan apakah email terdaftar (anti account-enumeration).
  static Future<AuthResult> resetPassword(String email) async {
    try {
      await _sb.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: kAuthRedirectUri,
      );
      return const AuthResult(
        success: true,
        message:
            'Jika email terdaftar, tautan reset kata sandi telah dikirim. Silakan periksa kotak masuk atau folder spam Anda.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(success: false, message: 'Terjadi kesalahan jaringan: $e');
    }
  }

  // ─── Map OTP type string → OtpType ──────────────────────────────────────────

  /// Petakan string type dari URL ke OtpType Supabase.
  /// Kembalikan null jika tidak dikenal (bukan null-safe crash — caller harus cek).
  static OtpType? mapOtpType(String? t) {
    switch (t?.toLowerCase()) {
      case 'email':
      case 'signup':
        return OtpType.email;
      case 'recovery':
        return OtpType.recovery;
      case 'magiclink':
        return OtpType.magiclink;
      default:
        return null;
    }
  }

  // ─── Verify OTP (token_hash flow) ───────────────────────────────────────────

  /// Verifikasi token_hash yang datang dari link email.
  /// Kembalikan AuthResult.success = false dengan pesan Indonesia jika gagal.
  static Future<AuthResult> verifyOtp({
    required String tokenHash,
    required String type,
  }) async {
    final otpType = mapOtpType(type);
    if (otpType == null) {
      return const AuthResult(
        success: false,
        message: 'Jenis tautan tidak dikenal. Silakan minta tautan baru.',
      );
    }
    try {
      await _sb.auth.verifyOTP(tokenHash: tokenHash, type: otpType);
      return const AuthResult(success: true);
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(
          success: false, message: 'Gagal memverifikasi tautan: $e');
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
  }) =>
      signIn(email: email, password: password);

  /// Login via Google / Gmail OAuth dari Supabase.
  /// Web: gunakan kAuthRedirectUri. Mobile: scheme khusus.
  static Future<bool> signInWithGoogle() async {
    try {
      return await _sb.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? kAuthRedirectUri : 'digiq://login-callback',
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
      final data = await _sb.from('profiles').select().eq('id', uid).single();
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

  // ─── MFA / 2FA TOTP Helpers ─────────────────────────────────────────────────

  /// Cek apakah sesi saat ini berstatus AAL2 (MFA terverifikasi).
  static bool isSessionAal2() {
    try {
      final aal = _sb.auth.mfa.getAuthenticatorAssuranceLevel();
      return aal.currentLevel == AuthenticatorAssuranceLevels.aal2;
    } catch (_) {
      return false;
    }
  }

  /// Cek apakah pengguna saat ini AAL2 (asynchronous helper).
  static Future<bool> isAal2() async => isSessionAal2();

  /// Daftar faktor MFA yang terhubung pada akun saat ini.
  static Future<AuthMFAListFactorsResponse> listFactors() async {
    return await _sb.auth.mfa.listFactors();
  }

  /// Mendaftarkan faktor TOTP baru.
  static Future<AuthMFAEnrollResponse> enrollTotp({String issuer = 'DigiQ'}) async {
    return await _sb.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: issuer,
    );
  }

  /// Melakukan challenge dan verifikasi kode 6 digit TOTP untuk naik ke AAL2.
  static Future<AuthMFAVerifyResponse> challengeAndVerifyTotp({
    required String factorId,
    required String code,
  }) async {
    return await _sb.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
  }

  /// Menghapus faktor MFA yang belum selesai diverifikasi atau dibatalkan.
  static Future<void> unenrollFactor(String factorId) async {
    await _sb.auth.mfa.unenroll(factorId);
  }

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

  /// Ganti password (dipakai di SetNewPasswordScreen setelah verifyOTP recovery).
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
            fileOptions:
                const FileOptions(upsert: true, contentType: 'image/jpeg'),
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

  static Stream<AuthState> get authStateChanges => _sb.auth.onAuthStateChange;

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
    // Token sudah dipakai / tidak valid (termasuk otp_disabled, bad_otp)
    if (lower.contains('otp_disabled') ||
        lower.contains('bad_otp') ||
        lower.contains('invalid otp') ||
        lower.contains('token not found') ||
        lower.contains('invalid token')) {
      return 'Tautan tidak valid atau sudah digunakan. Silakan minta tautan baru.';
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
    if (lower.contains('password should be at least') ||
        lower.contains('password too short') ||
        lower.contains('weak password')) {
      return 'Password terlalu lemah. Gunakan minimal 8 karakter.';
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
