// lib/screens/auth/email_verification_screen.dart
//
// Halaman konfirmasi verifikasi email DigiQ 100% murni Flutter Dart Widgets.
// Menangani 3 status verifikasi:
// 1. VerificationStatus.waiting: Menunggu konfirmasi user di Gmail (ikon amplop Cyan #06ACDC, cooldown 60s)
// 2. VerificationStatus.verified: Email sukses diverifikasi (ikon centang Emerald #10B981, countdown 3s ke Beranda)
// 3. VerificationStatus.error: Tautan kedaluwarsa atau tidak valid (ikon peringatan Rose #E11D48, kirim ulang)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/app_language.dart';
import '../../theme/app_theme.dart';
import '../admin_dashboard_screen.dart';
import '../customer_dashboard_screen.dart';
import '../login_screen.dart';
import 'forgot_password_screen.dart';

enum VerificationStatus {
  waiting,
  verified,
  error;

  static const VerificationStatus pending = VerificationStatus.waiting;
}

typedef VerificationState = VerificationStatus;

class EmailVerificationScreen extends StatefulWidget {
  final String? email;
  final VerificationStatus initialStatus;
  final String? errorMessage;
  final bool isRecovery;

  const EmailVerificationScreen({
    super.key,
    this.email,
    VerificationStatus? initialStatus,
    VerificationStatus? initialState,
    this.errorMessage,
    this.isRecovery = false,
  }) : initialStatus =
           initialStatus ?? initialState ?? VerificationStatus.waiting;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  late VerificationStatus _status;
  late TextEditingController _emailController;
  String? _errorMessage;

  StreamSubscription<AuthState>? _authSub;
  Timer? _cooldownTimer;
  Timer? _redirectTimer;

  int _resendCooldown = 0;
  int _redirectCountdown = 3;
  bool _isResending = false;
  bool _isNavigating = false;
  bool _isCheckingStatus = false;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _errorMessage = widget.errorMessage;
    _emailController = TextEditingController(
      text: widget.email ?? AuthService.currentUserEmail ?? '',
    );

    _setupAuthListener();

    if (_status == VerificationStatus.waiting) {
      _startCooldown(60);
    } else if (_status == VerificationStatus.verified) {
      _startRedirectCountdown();
    }
  }

  void _setupAuthListener() {
    _authSub = AuthService.authStateChanges.listen(
      (data) {
        if (!mounted) return;
        final session = data.session;
        final event = data.event;

        // Terdeteksi ketika link di Gmail diklik dan PKCE berhasil menukar session
        final isConfirmed = session?.user.emailConfirmedAt != null;
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.userUpdated ||
            isConfirmed) {
          if (_status != VerificationStatus.verified) {
            setState(() {
              _status = VerificationStatus.verified;
              _errorMessage = null;
            });
            _startRedirectCountdown();
          }
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _status = VerificationStatus.error;
          _errorMessage = AuthService.translateAuthError(error.toString());
        });
      },
    );
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  void _startRedirectCountdown() {
    _redirectTimer?.cancel();
    setState(() => _redirectCountdown = 3);
    _redirectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_redirectCountdown <= 1) {
        timer.cancel();
        _navigateToDashboard();
      } else {
        setState(() => _redirectCountdown--);
      }
    });
  }

  Future<void> _resendEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Masukkan alamat email yang valid.', isError: true);
      return;
    }
    if (_resendCooldown > 0 || _isResending) return;

    setState(() => _isResending = true);
    final result = await AuthService.resendVerificationEmail(email);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result.success) {
      setState(() {
        _status = VerificationStatus.waiting;
        _errorMessage = null;
      });
      _startCooldown(60);
      _showSnack(
        result.message ?? 'Email verifikasi berhasil dikirim ulang.',
        isError: false,
      );
    } else {
      _showSnack(
        result.message ??
            (AppLanguage.isId
                ? 'Gagal mengirim ulang email verifikasi.'
                : 'Failed to resend verification email.'),
        isError: true,
      );
    }
  }

  Future<void> _checkStatusManually() async {
    if (_isCheckingStatus || !mounted) return;
    setState(() => _isCheckingStatus = true);

    try {
      final sessionRes = await AuthService.refreshSession();
      if (sessionRes != null && sessionRes.user?.emailConfirmedAt != null) {
        if (!mounted) return;
        setState(() {
          _isCheckingStatus = false;
          _status = VerificationStatus.verified;
          _errorMessage = null;
        });
        _startRedirectCountdown();
        return;
      }
    } catch (_) {}

    if (AuthService.isCurrentUserEmailVerified) {
      if (!mounted) return;
      setState(() {
        _isCheckingStatus = false;
        _status = VerificationStatus.verified;
        _errorMessage = null;
      });
      _startRedirectCountdown();
      return;
    }

    if (!mounted) return;
    setState(() => _isCheckingStatus = false);
    _showSnack(
      AppLanguage.isId
          ? 'Email belum terkonfirmasi di server. Silakan periksa folder Spam/Promosi di Gmail Anda, atau klik "Kirim Ulang Email".'
          : 'Email is not confirmed yet. Please check your Spam/Promotions folder or click "Resend Email".',
      isError: true,
    );
  }

  Future<void> _navigateToDashboard() async {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;
    _redirectTimer?.cancel();

    final profile = await AuthService.getCurrentProfile();
    if (!mounted) return;

    if (profile == null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      return;
    }

    final Widget target = profile.isAdmin
        ? const AdminDashboardScreen()
        : CustomerDashboardScreen(profile: profile);

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => target),
      (route) => false,
    );
  }

  Future<void> _navigateToLogin() async {
    _redirectTimer?.cancel();
    _cooldownTimer?.cancel();
    try {
      await AuthService.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cooldownTimer?.cancel();
    _redirectTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigateToLogin();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // Background decorative blobs
            Positioned(
              top: -100,
              right: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _status == VerificationStatus.verified
                          ? AppColors.success.withValues(alpha: 0.20)
                          : _status == VerificationStatus.error
                          ? AppColors.error.withValues(alpha: 0.18)
                          : AppColors.primary.withValues(alpha: 0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -60,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryGradientStart.withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: anim, child: child),
                      ),
                      child: _buildCurrentStateCard(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStateCard() {
    switch (_status) {
      case VerificationStatus.waiting:
        return _buildWaitingCard();
      case VerificationStatus.verified:
        return _buildVerifiedCard();
      case VerificationStatus.error:
        return _buildErrorCard();
    }
  }

  // ─── Tampilan 1 — Menunggu Verifikasi (waiting) ─────────────────────────────

  Widget _buildWaitingCard() {
    final emailText = _emailController.text.trim();

    return Container(
      key: const ValueKey('waiting_card'),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ikon amplop outline Cyan #06ACDC
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.mark_email_unread_outlined,
              size: 42,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),

          Text(
            AppLanguage.t('verify_email_waiting_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),

          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              children: [
                TextSpan(text: AppLanguage.t('verify_email_waiting_desc_1')),
                TextSpan(
                  text: emailText.isNotEmpty
                      ? emailText
                      : (AppLanguage.isId
                            ? 'alamat email Anda'
                            : 'your email address'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextSpan(text: AppLanguage.t('verify_email_waiting_desc_2')),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Banner Realtime Deteksi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.sync_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppLanguage.t('verify_email_auto_redirect'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),

          // Tombol Cek Status Verifikasi / Masuk
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isCheckingStatus ? null : _checkStatusManually,
              icon: _isCheckingStatus
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_user_rounded, size: 18),
              label: Text(
                AppLanguage.isId
                    ? 'Cek Status Verifikasi'
                    : 'Check Verification Status',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Tombol Kirim Ulang Email dengan Cooldown 60s
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: (_resendCooldown > 0 || _isResending)
                  ? null
                  : _resendEmail,
              icon: _isResending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                _resendCooldown > 0
                    ? '${AppLanguage.t('resend_in_cooldown')}${_resendCooldown}s'
                    : AppLanguage.t('verify_email_resend_btn'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: _resendCooldown > 0
                      ? AppColors.cardBorder
                      : AppColors.primary,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          const SizedBox(height: 10),
          Text(
            AppLanguage.isId
                ? 'Tidak menerima email? Periksa folder Spam/Promosi.'
                : 'Didn\'t receive the email? Check your Spam/Promotions folder.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          // Tombol Keluar / Ganti Akun
          TextButton.icon(
            onPressed: _navigateToLogin,
            icon: const Icon(
              Icons.logout_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
            label: Text(
              AppLanguage.isId
                  ? 'Keluar / Ganti Akun'
                  : 'Sign Out / Switch Account',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tampilan 2 — Halaman Konfirmasi Sukses Saat Kembali ke APK (verified) ──

  Widget _buildVerifiedCard() {
    return Container(
      key: const ValueKey('verified_card'),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withValues(alpha: 0.15),
            blurRadius: 36,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Centang besar Emerald #10B981 dalam lingkaran
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.successLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.35),
                width: 2.5,
              ),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 54,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 24),

          // Judul tebal
          Text(
            AppLanguage.t('verify_email_verified_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),

          // Subjudul
          Text(
            AppLanguage.t('verify_email_verified_desc'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Indikator countdown di Dart
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppLanguage.isId
                      ? 'Mengalihkan ke Beranda dalam $_redirectCountdown detik...'
                      : 'Redirecting to Home in $_redirectCountdown seconds...',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Tombol utama Masuk ke Aplikasi Sekarang
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _navigateToDashboard,
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              label: Text(
                AppLanguage.isId
                    ? 'Masuk ke Aplikasi Sekarang'
                    : 'Enter App Now',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tampilan 3 — Halaman Gagal / Link Kedaluwarsa (error) ──────────────────

  Widget _buildErrorCard() {
    if (widget.isRecovery) {
      final displayError =
          _errorMessage ??
          (AppLanguage.isId
              ? 'Tautan reset kata sandi sudah kedaluwarsa atau sudah digunakan. Silakan minta tautan baru.'
              : 'Password reset link has expired or has already been used. Please request a new link.');

      return Container(
        key: const ValueKey('recovery_error_card'),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                size: 46,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppLanguage.isId
                  ? 'Tautan Reset Tidak Valid'
                  : 'Invalid Reset Link',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              displayError,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text(
                  'Minta Tautan Reset Baru',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _navigateToLogin,
              child: Text(
                AppLanguage.isId
                    ? 'Kembali ke Halaman Login'
                    : 'Back to Login Page',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final displayError =
        _errorMessage ??
        (AppLanguage.isId
            ? 'Tautan verifikasi sudah kedaluwarsa atau tidak valid saat kembali dari Gmail. Silakan kirim ulang tautan baru.'
            : 'Verification link has expired or is invalid. Please resend a new link.');

    return Container(
      key: const ValueKey('error_card'),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ikon peringatan Rose #E11D48
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              size: 46,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 24),

          Text(
            AppLanguage.isId
                ? 'Tautan Kedaluwarsa / Tidak Valid'
                : 'Expired / Invalid Link',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),

          Text(
            displayError,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Input / Konfirmasi Alamat Email
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Masukkan email Anda',
              prefixIcon: const Icon(
                Icons.email_outlined,
                size: 20,
                color: AppColors.textMuted,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: AppColors.background,
            ),
          ),
          const SizedBox(height: 20),

          // Tombol Kirim Ulang Tautan Baru
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: (_resendCooldown > 0 || _isResending)
                  ? null
                  : _resendEmail,
              icon: _isResending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.mail_outline_rounded, size: 20),
              label: Text(
                _resendCooldown > 0
                    ? 'Tunggu ${_resendCooldown}d untuk kirim ulang'
                    : 'Kirim Ulang Email Verifikasi',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),

          const SizedBox(height: 10),
          Text(
            AppLanguage.isId
                ? 'Tidak menerima email? Periksa folder Spam/Promosi.'
                : 'Didn\'t receive the email? Check your Spam/Promotions folder.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          // Tombol Kembali ke Halaman Login
          TextButton(
            onPressed: _navigateToLogin,
            child: Text(
              AppLanguage.isId
                  ? 'Kembali ke Halaman Login'
                  : 'Back to Login Page',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
