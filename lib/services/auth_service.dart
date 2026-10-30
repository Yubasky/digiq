// lib/services/auth_service.dart
//
// Layanan autentikasi DigiQ: Registrasi, Login, Password Reset, Verifikasi Email.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import '../models/profile_model.dart';

/// Status ketersediaan username
enum UsernameCheckStatus {
  available,
  taken,
  invalidFormat,
  networkError,
  serverNotReady,
  permissionDenied,
  unknownError,
}

/// Status ketersediaan email
enum EmailCheckStatus {
  available,
  taken,
  invalidFormat,
  networkError,
  serverNotReady,
  permissionDenied,
  unknownError,
}


/// Hasil operasi AuthService untuk feedback UI.
class AuthResult {
  final bool success;
  final String? message;
  final ProfileModel? profile;

  const AuthResult({required this.success, this.message, this.profile});
}

class AuthService {
  static SupabaseClient get _sb => SupabaseConfig.supabase;

  /// In-memory security flag: true saat alur recovery aktif.
  /// Mencegah akses ke dashboard hingga password diperbarui atau user sign out.
  static bool isPasswordRecovery = false;

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

  // ─── Username Validation & Availability Check ─────────────────────────────

  /// Validasi format username: 5-20 karakter, hanya huruf dan angka (alfanumerik)
  static String? validateUsernameFormat(String? v) {
    if (v == null || v.trim().isEmpty) return 'Username wajib diisi.';
    final u = v.trim();
    if (u.length < 5) return 'Username minimal 5 karakter.';
    if (u.length > 20) return 'Username maksimal 20 karakter.';
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(u)) {
      return 'Hanya boleh berisi huruf dan angka tanpa spasi/simbol.';
    }
    return null;
  }

  /// Normalisasi username: hapus spasi ujung dan konversi ke huruf kecil
  static String normalizeUsername(String input) => input.trim().toLowerCase();

  /// Mengklasifikasikan error dari pemanggilan RPC check_username_available:
  /// - PGRST202 (atau pesan tidak ditemukan di schema cache) -> serverNotReady
  /// - 401 / 403 / 42501 (atau permission denied) -> permissionDenied
  /// - TimeoutException / Socket / Client / Network -> networkError
  /// - Error tak dikenal -> unknownError (TIDAK mengasumsikan serverNotReady)
  /// Pencocokan string longgar seperti 'not found' atau '404' telah dihapus.
  static UsernameCheckStatus classifyUsernameCheckError(Object error) {
    if (error is TimeoutException) {
      return UsernameCheckStatus.networkError;
    }
    if (error is PostgrestException) {
      final code = (error.code ?? '').toUpperCase();
      final msg = error.message.toLowerCase();
      // Hanya PGRST202 atau pesan spesifik schema cache yang menandakan fungsi belum ada
      if (code == 'PGRST202' ||
          msg.contains('could not find the function') ||
          msg.contains('schema cache')) {
        return UsernameCheckStatus.serverNotReady;
      }
      // 401 / 403 / 42501 menandakan penolakan izin akses (RLS / peran anon)
      if (code == '401' ||
          code == '403' ||
          code == '42501' ||
          msg.contains('permission denied')) {
        return UsernameCheckStatus.permissionDenied;
      }
    }
    final str = error.toString().toLowerCase();
    if (str.contains('pgrst202') || str.contains('schema cache')) {
      return UsernameCheckStatus.serverNotReady;
    }
    if (str.contains('permission denied') || str.contains('unauthorized')) {
      return UsernameCheckStatus.permissionDenied;
    }
    if (str.contains('socket') ||
        str.contains('timeoutexception') ||
        str.contains('clientexception') ||
        str.contains('network') ||
        str.contains('failed host lookup') ||
        str.contains('connection refused') ||
        str.contains('xmlhttprequest') ||
        str.contains('connection closed')) {
      return UsernameCheckStatus.networkError;
    }
    // Error tak dikenal tidak diasumsikan serverNotReady
    return UsernameCheckStatus.unknownError;
  }

  /// Pesan netral dan ramah untuk pengguna umum berdasarkan status pengecekan username.
  /// Tidak menggunakan kata 'Hubungi admin' agar tidak membingungkan pengguna akhir.
  static String? getUsernameStatusMessage(UsernameCheckStatus status) {
    switch (status) {
      case UsernameCheckStatus.available:
        return null;
      case UsernameCheckStatus.taken:
        return 'Username ini telah digunakan';
      case UsernameCheckStatus.invalidFormat:
        return 'Username minimal 5 dan maksimal 20 karakter alfanumerik.';
      case UsernameCheckStatus.serverNotReady:
        return 'Pemeriksaan username sementara tidak tersedia. Anda tetap dapat melanjutkan pendaftaran.';
      case UsernameCheckStatus.permissionDenied:
        return 'Pemeriksaan username tidak dapat dilakukan saat ini. Anda tetap dapat melanjutkan pendaftaran.';
      case UsernameCheckStatus.networkError:
        return 'Gangguan jaringan saat memeriksa username. Silakan periksa koneksi.';
      case UsernameCheckStatus.unknownError:
        return 'Terjadi kendala saat memeriksa username. Anda tetap dapat melanjutkan pendaftaran.';
    }
  }

  /// Memeriksa ketersediaan username ke Supabase RPC check_username_available.
  /// Membedakan: available (tersedia), taken (sudah dipakai), invalidFormat,
  /// networkError (jaringan), serverNotReady (PGRST202), permissionDenied (401/403),
  /// dan unknownError.
  /// Dilengkapi auto-retry 1x (jeda 500ms) dan batas waktu 4 detik per percobaan.
  /// Total waktu tunggu terburuk (worst-case): ~8.5 detik.
  static Future<UsernameCheckStatus> checkUsernameStatus(
    String username, {
    int maxRetries = 1,
    Duration timeoutDuration = const Duration(seconds: 4),
  }) async {
    final formatErr = validateUsernameFormat(username);
    if (formatErr != null) return UsernameCheckStatus.invalidFormat;

    final cleanUsername = normalizeUsername(username);

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final res = await _sb
            .rpc(
              'check_username_available',
              params: {'p_username': cleanUsername},
            )
            .timeout(timeoutDuration);

        if (res == true) return UsernameCheckStatus.available;
        return UsernameCheckStatus.taken;
      } catch (e) {
        debugPrint(
          '[AuthService] checkUsernameStatus (attempt ${attempt + 1}/${maxRetries + 1}) error: $e',
        );
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        return classifyUsernameCheckError(e);
      }
    }
    return UsernameCheckStatus.networkError;
  }


  // ─── Email & Profile Validation ──────────────────────────────────────────

  /// Validasi format email RFC sederhana
  static String? validateEmailFormat(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email wajib diisi.';
    final clean = v.trim();
    if (clean.length > 254) return 'Email terlalu panjang.';
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(clean)) {
      return 'Format email tidak valid.';
    }
    return null;
  }

  /// Validasi nama lengkap (2-60 karakter)
  static String? validateFullNameFormat(String? v) {
    if (v == null || v.trim().isEmpty) return 'Nama lengkap wajib diisi.';
    final clean = v.trim();
    if (clean.length < 2) return 'Nama minimal 2 karakter.';
    if (clean.length > 60) return 'Nama maksimal 60 karakter.';
    return null;
  }

  /// Validasi nomor HP format Indonesia (08xx, +62xx, 62xx - 9 sampai 15 digit)
  static String? validatePhoneFormat(String? v) {
    if (v == null || v.trim().isEmpty) return 'Nomor HP wajib diisi.';
    final clean = v.trim();
    if (!RegExp(r'^(\+62|62|08)[0-9]{7,13}$').hasMatch(clean)) {
      return 'Format nomor HP tidak valid (contoh: 08123456789 atau +628123456789).';
    }
    return null;
  }

  /// Pesan status ketersediaan email yang ramah dan netral
  static String? getEmailStatusMessage(EmailCheckStatus status) {
    switch (status) {
      case EmailCheckStatus.available:
        return null;
      case EmailCheckStatus.taken:
        return 'Email ini sudah terdaftar. Silakan masuk atau gunakan Lupa Password.';
      case EmailCheckStatus.invalidFormat:
        return 'Format email tidak valid.';
      case EmailCheckStatus.networkError:
        return 'Koneksi lambat saat memeriksa email. Anda tetap dapat melanjutkan pendaftaran.';
      case EmailCheckStatus.serverNotReady:
      case EmailCheckStatus.permissionDenied:
      case EmailCheckStatus.unknownError:
        return 'Layanan pengecekan email sedang sibuk. Anda tetap dapat melanjutkan pendaftaran.';
    }
  }

  /// Klasifikasi error dari pemanggilan RPC check_email_available
  static EmailCheckStatus classifyEmailCheckError(Object error) {
    if (error is TimeoutException) {
      return EmailCheckStatus.networkError;
    }
    if (error is PostgrestException) {
      final code = (error.code ?? '').toUpperCase();
      final msg = error.message.toLowerCase();
      if (code == 'PGRST202' ||
          msg.contains('could not find the function') ||
          msg.contains('schema cache')) {
        return EmailCheckStatus.serverNotReady;
      }
      if (code == '401' ||
          code == '403' ||
          code == '42501' ||
          msg.contains('permission denied') ||
          msg.contains('unauthorized')) {
        return EmailCheckStatus.permissionDenied;
      }
    }
    final str = error.toString().toLowerCase();
    if (str.contains('pgrst202') || str.contains('schema cache')) {
      return EmailCheckStatus.serverNotReady;
    }
    if (str.contains('permission denied') || str.contains('unauthorized')) {
      return EmailCheckStatus.permissionDenied;
    }
    if (str.contains('socket') ||
        str.contains('timeoutexception') ||
        str.contains('clientexception') ||
        str.contains('network') ||
        str.contains('failed host lookup') ||
        str.contains('connection refused') ||
        str.contains('xmlhttprequest') ||
        str.contains('connection closed')) {
      return EmailCheckStatus.networkError;
    }
    return EmailCheckStatus.unknownError;
  }

  /// Cek ketersediaan email via RPC check_email_available
  static Future<EmailCheckStatus> checkEmailStatus(
    String email, {
    int maxRetries = 1,
    Duration timeoutDuration = const Duration(seconds: 4),
  }) async {
    final formatErr = validateEmailFormat(email);
    if (formatErr != null) return EmailCheckStatus.invalidFormat;

    final cleanEmail = email.trim().toLowerCase();

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final res = await _sb
            .rpc(
              'check_email_available',
              params: {'p_email': cleanEmail},
            )
            .timeout(timeoutDuration);

        if (res == true) return EmailCheckStatus.available;
        return EmailCheckStatus.taken;
      } catch (e) {
        debugPrint(
          '[AuthService] checkEmailStatus (attempt /) error: ',
        );
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        return classifyEmailCheckError(e);
      }
    }
    return EmailCheckStatus.networkError;
  }

  // ─── Sign Up ────────────────────────────────────────────────────────────────

  /// Daftar akun baru dengan emailRedirectTo custom scheme digiq://auth-callback.
  /// Setelah sukses, profil dibuat otomatis via trigger DB.
  static Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    String? username,
    String? emailRedirectTo,
  }) async {
    final cleanEmail = email.trim();
    final cleanFullName = fullName.trim();
    final cleanPhone = phone.trim();
    final cleanUsername = username != null ? normalizeUsername(username) : '';

    if (cleanUsername.isNotEmpty) {
      final formatErr = validateUsernameFormat(cleanUsername);
      if (formatErr != null) {
        return AuthResult(success: false, message: formatErr);
      }
    }

    try {
      final payloadData = <String, dynamic>{
        'full_name': cleanFullName,
        'phone': cleanPhone,
      };
      if (cleanUsername.isNotEmpty) {
        payloadData['username'] = cleanUsername;
      }

      final res = await _sb.auth
          .signUp(
            email: cleanEmail,
            password: password,
            emailRedirectTo: emailRedirectTo ?? kAuthRedirectUri,
            data: payloadData,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'Batas waktu koneksi pendaftaran berakhir (Upstream Timeout).',
            ),
          );

      if (res.user == null) {
        return const AuthResult(
          success: false,
          message: 'Pendaftaran gagal. Silakan coba lagi.',
        );
      }

      // Guard anti-enumerasi Supabase: jika email sudah terdaftar, identities bernilai kosong
      if (res.user?.identities == null || res.user!.identities!.isEmpty) {
        return const AuthResult(
          success: false,
          message: 'Email ini sudah terdaftar. Silakan login atau gunakan Lupa Password.',
        );
      }

      // Beri jeda agar trigger handle_new_user di DB selesai dieksekusi
      await Future<void>.delayed(const Duration(milliseconds: 500));

      return const AuthResult(
        success: true,
        message: 'Akun berhasil dibuat! Silakan verifikasi email Anda.',
      );
    } on TimeoutException catch (e) {
      return AuthResult(
        success: false,
        message: e.message ?? 'Server sedang lambat merespons. Silakan periksa jaringan Anda atau coba sesaat lagi.',
      );
    } on AuthException catch (e) {
      return AuthResult(
        success: false,
        message: _translateAuthError(e.message),
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Terjadi kesalahan sistem: $e',
      );
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
      return AuthResult(
        success: false,
        message: _translateAuthError(e.message),
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Gagal mengirim ulang email verifikasi: $e',
      );
    }
  }

  // ─── Reset Password ──────────────────────────────────────────────────────────

  /// Kirim email reset password. Pesan sukses selalu netral agar tidak
  /// membocorkan apakah email terdaftar (anti account-enumeration).
  /// Rate-limit dan network errors diterjemahkan secara ramah.
  static Future<AuthResult> resetPassword(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      return const AuthResult(success: false, message: 'Email wajib diisi.');
    }
    try {
      await _sb.auth.resetPasswordForEmail(
        cleanEmail,
        redirectTo: kAuthRedirectUri,
      );
      return const AuthResult(
        success: true,
        message: 'Jika email terdaftar, tautan telah dikirim. Silakan periksa kotak masuk atau folder spam Anda.',
      );
    } on AuthException catch (e) {
      final lower = e.message.toLowerCase();
      // Hanya tampilkan error jika kena rate limit, selebihnya netral
      if (lower.contains('rate limit') ||
          lower.contains('over_email_send_rate_limit') ||
          lower.contains('for security purposes')) {
        return AuthResult(
          success: false,
          message: _translateAuthError(e.message),
        );
      }
      return const AuthResult(
        success: true,
        message: 'Jika email terdaftar, tautan telah dikirim. Silakan periksa kotak masuk atau folder spam Anda.',
      );
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'Koneksi internet bermasalah. Periksa jaringan Anda.',
      );
    }
  }

  // ─── Map OTP type string → OtpType ──────────────────────────────────────────

  /// Petakan string type dari URL ke OtpType Supabase.
  /// Mendukung: email, signup, recovery, magiclink, emailChange (email_change), invite.
  /// Kembalikan null jika tidak dikenal.
  static OtpType? mapOtpType(String? t) {
    switch (t?.toLowerCase()) {
      case 'email':
        return OtpType.email;
      case 'signup':
        return OtpType.signup;
      case 'recovery':
        return OtpType.recovery;
      case 'magiclink':
        return OtpType.magiclink;
      case 'email_change':
      case 'emailchange':
        return OtpType.emailChange;
      case 'invite':
        return OtpType.invite;
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
    final cleanHash = tokenHash.trim();
    final cleanType = type.trim();

    if (cleanHash.isEmpty || cleanType.isEmpty) {
      return const AuthResult(
        success: false,
        message:
            'Tautan verifikasi tidak lengkap. Parameter token tidak ditemukan.',
      );
    }

    final otpType = mapOtpType(cleanType);
    if (otpType == null) {
      return const AuthResult(
        success: false,
        message: 'Jenis tautan tidak dikenal. Silakan minta tautan baru.',
      );
    }

    try {
      await _sb.auth.verifyOTP(tokenHash: cleanHash, type: otpType);
      return const AuthResult(success: true);
    } on AuthException catch (e) {
      return AuthResult(
        success: false,
        message: _translateAuthError(e.message),
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Koneksi internet bermasalah saat memverifikasi tautan: $e',
      );
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
    String loginEmail = email.trim();
    // Jika login menggunakan username (tanpa @), selesaikan ke email akun via RPC
    if (!loginEmail.contains('@') && loginEmail.isNotEmpty) {
      try {
        final res = await _sb.rpc('resolve_login_email', params: {'p_identifier': loginEmail}).timeout(
          const Duration(seconds: 4),
        );
        if (res != null && res is String && res.contains('@')) {
          loginEmail = res.trim();
        }
      } catch (_) {}
    }

    try {
      final res = await _sb.auth.signInWithPassword(
        email: loginEmail,
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
      return AuthResult(
        success: false,
        message: _translateAuthError(e.message),
      );
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
    for (int i = 0; i < 3; i++) {
      try {
        final data = await _sb.from('profiles').select().eq('id', uid).single();
        return ProfileModel.fromMap(data);
      } catch (_) {
        if (i < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    return null;
  }

  /// Ambil role dari profil (untuk routing di main.dart).
  static Future<String?> getCurrentRole() async {
    final profile = await getCurrentProfile();
    return profile?.role;
  }


  /// Update profil aman melalui RPC update_my_profile (melindungi role & balance).
  static Future<AuthResult> updateMyProfile({
    required String fullName,
    required String phone,
    required String username,
  }) async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        return const AuthResult(
          success: false,
          message: 'Sesi Anda telah berakhir. Silakan login kembali.',
        );
      }

      final res = await _sb.rpc('update_my_profile', params: {
        'p_full_name': fullName.trim(),
        'p_phone': phone.trim(),
        'p_username': normalizeUsername(username),
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Batas waktu koneksi habis.'),
      );

      if (res is Map) {
        final resMap = Map<String, dynamic>.from(res);
        final success = resMap['success'] == true;
        final message = (resMap['message'] as String?) ??
            (success ? 'Profil berhasil diperbarui.' : 'Gagal memperbarui profil.');

        ProfileModel? updatedProfile;
        if (success) {
          updatedProfile = await getCurrentProfile();
        }
        return AuthResult(
          success: success,
          message: message,
          profile: updatedProfile,
        );
      }

      return const AuthResult(
        success: false,
        message: 'Format data dari server tidak dikenali. Silakan coba sesaat lagi.',
      );
    } on TimeoutException {
      return const AuthResult(
        success: false,
        message: 'Koneksi ke server mengalami batas waktu. Silakan periksa jaringan Anda.',
      );
    } on PostgrestException catch (e) {
      return AuthResult(
        success: false,
        message: _translateAuthError(e.message),
      );
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'Terjadi kendala saat memperbarui profil. Silakan coba beberapa saat lagi.',
      );
    }
  }

  /// Kirim permintaan perubahan email. Tautan konfirmasi akan dikirim ke alamat email baru (dan lama).
  static Future<AuthResult> updateEmailAddress(String newEmail) async {
    final formatErr = validateEmailFormat(newEmail);
    if (formatErr != null) {
      return AuthResult(success: false, message: formatErr);
    }
    final cleanEmail = newEmail.trim().toLowerCase();
    try {
      final currentEmail = _sb.auth.currentUser?.email?.toLowerCase();
      if (currentEmail == cleanEmail) {
        return const AuthResult(
          success: false,
          message: 'Email baru sama dengan email akun Anda saat ini.',
        );
      }

      final checkStatus = await checkEmailStatus(cleanEmail);
      if (checkStatus == EmailCheckStatus.taken) {
        return const AuthResult(
          success: false,
          message: 'Email ini sudah digunakan oleh akun lain.',
        );
      }

      await _sb.auth.updateUser(
        UserAttributes(email: cleanEmail),
        emailRedirectTo: kAuthRedirectUri,
      );

      return const AuthResult(
        success: true,
        message: 'Tautan konfirmasi telah dikirim ke email baru Anda. Silakan buka email tersebut untuk menyelesaikan perubahan.',
      );
    } on AuthException catch (e) {
      final lower = e.message.toLowerCase();
      if (lower.contains('already') || lower.contains('taken') || lower.contains('unique')) {
        return const AuthResult(
          success: false,
          message: 'Email ini sudah digunakan oleh akun lain.',
        );
      }
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'Gagal mengajukan perubahan email. Silakan coba lagi.',
      );
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
        return const AuthResult(
          success: false,
          message: 'Tidak terautentikasi.',
        );
      }

      final updates = <String, dynamic>{
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'avatar_url': ?avatarUrl,
      };

      await _sb.from('profiles').update(updates).eq('id', uid);

      return const AuthResult(
        success: true,
        message: 'Profil berhasil diperbarui.',
      );
    } catch (e) {
      return AuthResult(success: false, message: 'Gagal update profil: $e');
    }
  }


  /// Ganti password dengan verifikasi password lama terlebih dahulu (re-autentikasi aman).
  static Future<AuthResult> changePasswordWithOld({
    required String oldPassword,
    required String newPassword,
  }) async {
    final user = _sb.auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      return const AuthResult(
        success: false,
        message: 'Sesi Anda telah berakhir. Silakan login kembali.',
      );
    }

    if (newPassword.trim().length < 8) {
      return const AuthResult(
        success: false,
        message: 'Password baru minimal 8 karakter.',
      );
    }

    try {
      // 1. Verifikasi kredensial lama via re-autentikasi
      await _sb.auth.signInWithPassword(
        email: email,
        password: oldPassword,
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid') || msg.contains('credentials') || msg.contains('grant')) {
        return const AuthResult(
          success: false,
          message: 'Password saat ini salah. Silakan periksa kembali.',
        );
      }
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'Gagal memverifikasi password saat ini. Periksa koneksi Anda.',
      );
    }

    // 2. Update password baru
    try {
      await _sb.auth.updateUser(UserAttributes(password: newPassword));
      return const AuthResult(
        success: true,
        message: 'Password berhasil diperbarui.',
      );
    } on AuthException catch (e) {
      return AuthResult(success: false, message: _translateAuthError(e.message));
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'Gagal memperbarui password baru. Silakan coba lagi.',
      );
    }
  }

  /// Ganti password (dipakai di SetNewPasswordScreen setelah verifyOTP recovery).
  static Future<AuthResult> changePassword(String newPassword) async {
    try {
      await _sb.auth.updateUser(UserAttributes(password: newPassword));
      return const AuthResult(
        success: true,
        message: 'Password berhasil diubah.',
      );
    } on AuthException catch (e) {
      return AuthResult(
        success: false,
        message: _translateAuthError(e.message),
      );
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

      await _sb.storage
          .from('avatars')
          .uploadBinary(
            storagePath,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      return _sb.storage.from('avatars').getPublicUrl(storagePath);
    } catch (_) {
      return null;
    }
  }

  // ─── Sign Out ────────────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    isPasswordRecovery = false;
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
      return 'Terlalu banyak permintaan pengiriman email. Batas keamanan tercapai, harap tunggu sekitar 1 menit sebelum mencoba kembali.';
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
    if (lower.contains('database error saving new user')) {
      if (lower.contains('username') ||
          lower.contains('idx_profiles_username')) {
        return 'Username ini telah digunakan. Silakan pilih username lain.';
      }
      return 'Gagal menyimpan profil pengguna baru. Username atau data yang dimasukkan mungkin sudah digunakan atau tidak valid.';
    }
    if (lower.contains('idx_profiles_username') ||
        (lower.contains('duplicate key') && lower.contains('username'))) {
      return 'Username ini telah digunakan. Silakan pilih username lain.';
    }
    if (lower.contains('error sending confirmation email') ||
        lower.contains('error sending email') ||
        lower.contains('failed to send confirmation')) {
      return 'Gagal mengirim email konfirmasi pendaftaran. Layanan email sedang sibuk, silakan coba beberapa saat lagi.';
    }
    if (lower.contains('upstream') || lower.contains('gateway timeout')) {
      return 'Layanan autentikasi sedang mengalami batas waktu (timeout). Silakan periksa koneksi atau coba beberapa saat lagi.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Koneksi internet bermasalah. Periksa jaringan Anda.';
    }
    return msg;
  }

  static String _translateAuthError(String msg) => translateAuthError(msg);
}
