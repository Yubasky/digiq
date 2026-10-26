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

  // ─── Sign Up ────────────────────────────────────────────────────────────────

  /// Daftar akun baru. Setelah sukses, profil dibuat otomatis via trigger DB.
  static Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    try {
      final res = await _sb.auth.signUp(
        email: email.trim(),
        password: password,
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

  // ─── Sign In (Tahap 1: password) ────────────────────────────────────────────

  /// Login email+password. Mengembalikan:
  /// - success=true + mfaFactorId  → user punya TOTP, perlu verifikasi
  /// - success=true + totpUri       → user belum punya TOTP, perlu enrollment
  /// - success=true + profile       → aal2 sudah tercapai (jarang di sini)
  static Future<AuthResult> signInStep1({
    required String email,
    required String password,
  }) async {
    try {
      await _sb.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      // Cek faktor MFA yang terdaftar
      final factors = await _sb.auth.mfa.listFactors();
      final totpFactors = factors.totp
          .where((f) => f.status == FactorStatus.verified)
          .toList();

      if (totpFactors.isNotEmpty) {
        // Sudah punya TOTP terverifikasi → perlu challenge
        return AuthResult(
          success: true,
          mfaFactorId: totpFactors.first.id,
          message: 'Masukkan kode 6 digit dari aplikasi autentikator Anda.',
        );
      }

      // Belum punya TOTP → enrollment
      final enrollRes = await _sb.auth.mfa.enroll(
        issuer: 'DigiQ',
        factorType: FactorType.totp,
      );

      return AuthResult(
        success: true,
        totpUri: enrollRes.totp.uri,
        enrollFactorId: enrollRes.id,
        message: 'Scan QR code dengan aplikasi autentikator Anda.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(success: false, message: 'Terjadi kesalahan: $e');
    }
  }

  // ─── MFA Challenge + Verify (Tahap 2) ───────────────────────────────────────

  /// Verifikasi TOTP untuk faktor yang sudah terdaftar.
  static Future<AuthResult> verifyTotp({
    required String factorId,
    required String code,
  }) async {
    try {
      final challengeRes =
          await _sb.auth.mfa.challenge(factorId: factorId);
      await _sb.auth.mfa.verify(
        factorId: factorId,
        challengeId: challengeRes.id,
        code: code.trim(),
      );

      final profile = await getCurrentProfile();
      return AuthResult(
        success: true,
        profile: profile,
        message: 'Verifikasi berhasil.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(success: false, message: 'Kode tidak valid atau expired.');
    }
  }

  /// Verifikasi TOTP saat enrollment baru (unenrolled factor).
  static Future<AuthResult> verifyEnrollment({
    required String factorId,
    required String code,
  }) async {
    try {
      final challengeRes =
          await _sb.auth.mfa.challenge(factorId: factorId);
      await _sb.auth.mfa.verify(
        factorId: factorId,
        challengeId: challengeRes.id,
        code: code.trim(),
      );

      final profile = await getCurrentProfile();
      return AuthResult(
        success: true,
        profile: profile,
        message: 'Autentikator berhasil dikonfigurasi!',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (e) {
      return AuthResult(
          success: false, message: 'Verifikasi enrollment gagal: $e');
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

  /// Cek apakah sesi saat ini sudah aal2.
  static Future<bool> isAal2() async {
    try {
      final level = await _sb.auth.mfa.getAuthenticatorAssuranceLevel();
      return level.currentLevel == AuthenticatorAssuranceLevelString.aal2;
    } catch (_) {
      return false;
    }
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
        if (avatarUrl != null) 'avatar_url': avatarUrl,
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
        bytes,
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

  static String _translateAuthError(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials')) {
      return 'Email atau password salah.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Email belum diverifikasi. Cek kotak masuk Anda.';
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
    if (lower.contains('token has expired') || lower.contains('refresh')) {
      return 'Sesi kedaluwarsa. Silakan login ulang.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Koneksi internet bermasalah. Periksa jaringan Anda.';
    }
    return msg;
  }
}

/// Extension kecil supaya perbandingan AAL lebih readable.
extension AuthenticatorAssuranceLevelString on AuthenticatorAssuranceLevelString {
  static const aal1 = 'aal1';
  static const aal2 = 'aal2';
}
