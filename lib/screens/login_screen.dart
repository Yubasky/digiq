import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/supabase_config.dart';
import '../models/profile_model.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard_screen.dart';
import 'customer_dashboard_screen.dart';
import 'register_screen.dart';
import 'auth/email_verification_screen.dart';
import 'auth/forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;


  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.07),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ─── Supabase Login Flow ─────────────────────────────────────────────────

  Future<void> _doLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final result = await AuthService.signIn(
      email: _identifierController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.success) {
      final msg = result.message ?? 'Login gagal.';
      if (msg.toLowerCase().contains('belum diverifikasi')) {
        final emailInput = _identifierController.text.trim();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          action: SnackBarAction(
            label: 'Verifikasi',
            textColor: Colors.white,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EmailVerificationScreen(
                    email: emailInput.contains('@') ? emailInput : null,
                    initialStatus: VerificationStatus.waiting,
                  ),
                ),
              );
            },
          ),
        ));
      } else {
        _showError(msg);
      }
      return;
    }

    final profile = result.profile;
    if (profile == null) {
      _showError('Gagal memuat profil. Coba login ulang.');
      return;
    }

    // ─── Alur MFA TOTP (Admin Wajib AAL2) ──────────────────────────────────────
    try {
      final factors = await AuthService.listFactors();
      final verifiedTotp = factors.totp
          .where((f) => f.status == FactorStatus.verified)
          .firstOrNull;

      if (profile.isAdmin) {
        bool mfaOk = false;
        if (verifiedTotp != null) {
          mfaOk = await _showTotpVerifyDialog(verifiedTotp.id);
        } else {
          mfaOk = await _showTotpEnrollDialog(profile.id);
        }

        if (!mfaOk) {
          await AuthService.signOut();
          _showError('Admin wajib menyelesaikan verifikasi 2FA (TOTP) untuk masuk.');
          return;
        }

        if (!AuthService.isSessionAal2()) {
          await AuthService.signOut();
          _showError('Sesi admin belum mencapai tingkat keamanan AAL2.');
          return;
        }
      } else if (verifiedTotp != null || profile.is2faEnabled) {
        if (verifiedTotp != null) {
          final mfaOk = await _showTotpVerifyDialog(verifiedTotp.id);
          if (!mfaOk) {
            await AuthService.signOut();
            _showError('Verifikasi 2FA dibatalkan.');
            return;
          }
        }
      }
    } catch (e) {
      if (profile.isAdmin) {
        await AuthService.signOut();
        _showError('Gagal memproses verifikasi 2FA admin: $e');
        return;
      }
    }

    _navigateToHome(profile);
  }

  Future<bool> _showTotpVerifyDialog(String factorId) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TotpVerifyDialog(factorId: factorId),
    );
    return result ?? false;
  }

  Future<bool> _showTotpEnrollDialog(String profileId) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TotpEnrollDialog(profileId: profileId),
    );
    return result ?? false;
  }

  void _navigateToHome(ProfileModel profile) {
    if (!mounted) return;
    final Widget dest = profile.isAdmin
        ? const AdminDashboardScreen()
        : CustomerDashboardScreen(profile: profile);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, anim, secondaryAnim) => dest,
        transitionsBuilder: (_, anim, secondaryAnim, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Decorative background shapes
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 340,
              height: 340,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x3506ACDC), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x2800B4D8), Colors.transparent],
                ),
              ),
            ),
          ),

          // Wave illustration at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CustomPaint(
              painter: _WavePainter(),
              size: Size(size.width, 330),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Hero header section
                      SizedBox(
                        height: 200,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/img/logo digiq putih.png',
                              height: 88,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Text(
                                'DigiQ',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Produk Digital, Bayar via QRIS',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Form card
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selamat Datang 👋',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Masuk ke akun DigiQ Anda',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 22),

                                // Identifier field
                                const Text(
                                  'Email / Username',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _identifierController,
                                  keyboardType: TextInputType.emailAddress,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'email@kamu.com atau username',
                                    hintStyle: const TextStyle(
                                        color: AppColors.textMuted, fontSize: 13),
                                    prefixIcon: const Icon(Icons.person_outline_rounded,
                                        color: AppColors.textMuted, size: 20),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 13),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide:
                                          const BorderSide(color: AppColors.cardBorder),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: AppColors.primary, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.background,
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Email/username wajib diisi';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 14),

                                // Password field
                                const Text(
                                  'Password',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Masukkan password',
                                    hintStyle: const TextStyle(
                                        color: AppColors.textMuted, fontSize: 13),
                                    prefixIcon: const Icon(Icons.lock_outline_rounded,
                                        color: AppColors.textMuted, size: 20),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: AppColors.textMuted,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(
                                          () => _obscurePassword = !_obscurePassword),
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 13),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide:
                                          const BorderSide(color: AppColors.cardBorder),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: AppColors.primary, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.background,
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Password wajib diisi';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 12),

                                // Remember me + forgot password row
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () =>
                                          setState(() => _rememberMe = !_rememberMe),
                                      child: Row(
                                        children: [
                                          AnimatedContainer(
                                            duration:
                                                const Duration(milliseconds: 200),
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: _rememberMe
                                                  ? AppColors.primary
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: _rememberMe
                                                    ? AppColors.primary
                                                    : AppColors.cardBorder,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: _rememberMe
                                                ? const Icon(Icons.check,
                                                    color: Colors.white, size: 11)
                                                : null,
                                          ),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'Ingat saya',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const ForgotPasswordScreen(),
                                          ),
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Lupa password?',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 24),

                                // Login button
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _doLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Masuk',
                                            style: TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Divider
                                Row(
                                  children: [
                                    Expanded(
                                        child: Divider(
                                            color: AppColors.cardBorder,
                                            thickness: 1)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text(
                                        'atau',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                        child: Divider(
                                            color: AppColors.cardBorder,
                                            thickness: 1)),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Register button
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        PageRouteBuilder(
                                          pageBuilder: (_, anim, _) =>
                                              const RegisterScreen(),
                                          transitionsBuilder:
                                              (_, anim, _, child) =>
                                                  SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(1, 0),
                                              end: Offset.zero,
                                            ).animate(anim),
                                            child: child,
                                          ),
                                          transitionDuration:
                                              const Duration(milliseconds: 350),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.person_add_outlined,
                                        size: 18),
                                    label: const Text(
                                      'Daftar Akun Baru',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      side: const BorderSide(
                                          color: AppColors.primary, width: 1.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Info aman
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.lock_outline_rounded,
                                  color: AppColors.primaryDark, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Login aman dan cepat dengan akun DigiQ.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom wave painter for the hero header
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Secondary softer wave in background for depth
    final softPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF00B4D8).withValues(alpha: 0.4),
          const Color(0xFF06ACDC).withValues(alpha: 0.25),
        ],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final softPath = Path();
    softPath.moveTo(0, 0);
    softPath.lineTo(size.width, 0);
    softPath.lineTo(size.width, size.height * 0.90);
    softPath.quadraticBezierTo(
        size.width * 0.65, size.height * 1.05, size.width * 0.35, size.height * 0.88);
    softPath.quadraticBezierTo(
        size.width * 0.15, size.height * 0.78, 0, size.height * 0.94);
    softPath.close();
    canvas.drawPath(softPath, softPaint);

    // Primary vibrant blue wave
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF06ACDC), Color(0xFF0077B6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.80);
    path.quadraticBezierTo(
        size.width * 0.72, size.height * 0.98, size.width * 0.45, size.height * 0.84);
    path.quadraticBezierTo(
        size.width * 0.20, size.height * 0.70, 0, size.height * 0.90);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Modal Dialog Verifikasi 2FA TOTP ────────────────────────────────────────

class _TotpVerifyDialog extends StatefulWidget {
  final String factorId;
  const _TotpVerifyDialog({required this.factorId});

  @override
  State<_TotpVerifyDialog> createState() => _TotpVerifyDialogState();
}

class _TotpVerifyDialogState extends State<_TotpVerifyDialog> {
  final _codeController = TextEditingController();
  bool _verifying = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Masukkan 6 digit kode keamanan');
      return;
    }

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    try {
      await AuthService.challengeAndVerifyTotp(
        factorId: widget.factorId,
        code: code,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _errorMessage = 'Kode 2FA salah atau kedaluwarsa. Silakan coba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF06ACDC).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Color(0xFF06ACDC),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Verifikasi Dua Faktor (2FA)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Buka Google Authenticator atau Authy, lalu masukkan 6 digit kode keamanan akun Anda.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              autofocus: true,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: AppColors.textPrimary,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: TextStyle(
                  color: Colors.grey.shade300,
                  letterSpacing: 8,
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF06ACDC), width: 2),
                ),
              ),
              onSubmitted: (_) => _verify(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _verifying ? null : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _verifying ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF06ACDC),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _verifying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verifikasi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Modal Dialog Setup Enrollment 2FA TOTP (Wajib Admin) ─────────────────────

class _TotpEnrollDialog extends StatefulWidget {
  final String profileId;
  const _TotpEnrollDialog({required this.profileId});

  @override
  State<_TotpEnrollDialog> createState() => _TotpEnrollDialogState();
}

class _TotpEnrollDialogState extends State<_TotpEnrollDialog> {
  final _codeController = TextEditingController();
  AuthMFAEnrollResponse? _enrollData;
  bool _isLoading = true;
  bool _verifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startEnrollment();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startEnrollment() async {
    try {
      final res = await AuthService.enrollTotp(issuer: 'DigiQ');
      if (mounted) {
        setState(() {
          _enrollData = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal inisialisasi 2FA: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _cancel() async {
    if (_enrollData != null) {
      try {
        await AuthService.unenrollFactor(_enrollData!.id);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _verifyAndSave() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Masukkan 6 digit kode keamanan');
      return;
    }
    if (_enrollData == null) return;

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    try {
      await AuthService.challengeAndVerifyTotp(
        factorId: _enrollData!.id,
        code: code,
      );

      // Tandai 2FA aktif pada profil pengguna di database
      try {
        await SupabaseConfig.supabase
            .from('profiles')
            .update({'is_2fa_enabled': true})
            .eq('id', widget.profileId);
      } catch (_) {}

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _errorMessage = 'Kode verifikasi tidak sesuai. Pastikan jam perangkat Anda akurat.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF06ACDC).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF06ACDC), size: 34),
              ),
              const SizedBox(height: 14),
              const Text(
                'Aktivasi 2FA Admin (Wajib)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Pindai QR code ini di aplikasi Google Authenticator atau Authy Anda.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_isLoading) ...[
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              ] else if (_enrollData?.totp != null) ...[
                Builder(
                  builder: (_) {
                    final totp = _enrollData!.totp!;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: totp.uri,
                            size: 160,
                            version: QrVersions.auto,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  totp.secret,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF06ACDC)),
                                tooltip: 'Salin Kunci',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: totp.secret));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Kunci rahasia disalin ke papan klip!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Masukkan 6 digit kode dari aplikasi authenticator:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: AppColors.textPrimary,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    hintStyle: TextStyle(color: Colors.grey.shade300, letterSpacing: 6),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF06ACDC), width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _verifyAndSave(),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _verifying ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_verifying || _isLoading || _enrollData == null) ? null : _verifyAndSave,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: const Color(0xFF06ACDC),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _verifying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Aktifkan & Masuk', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}



