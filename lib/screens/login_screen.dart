import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard_screen.dart';
import 'customer_dashboard_screen.dart';
import 'register_screen.dart';

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

  Future<void> _doLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 1000));

    final user = UserStore.login(
      _identifierController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Email/username atau password salah.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // Navigate based on role
    Widget destination;
    if (user.role == UserRole.admin) {
      destination = const AdminDashboardScreen();
    } else {
      destination = CustomerDashboardScreen(currentUser: user);
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, anim, _) => destination,
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
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
              size: Size(size.width, 220),
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
                              'assets/img/Logo_digiq.png',
                              height: 60,
                              errorBuilder: (_, _, _) => Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(Icons.bolt_rounded,
                                    color: Colors.white, size: 36),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'DigiQ',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                            const Text(
                              'Produk Digital, Bayar via QRIS',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.white70,
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
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                                'Fitur lupa password akan segera hadir.'),
                                            backgroundColor: AppColors.primary,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            margin: const EdgeInsets.all(16),
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

                      // Hint for admin
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
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: AppColors.primaryDark, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: const TextSpan(
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primaryDark,
                                    ),
                                    children: [
                                      TextSpan(text: 'Admin: gunakan '),
                                      TextSpan(
                                        text: 'admin / admin123',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace'),
                                      ),
                                    ],
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
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF06ACDC), Color(0xFF0077B6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.72);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.95, size.width * 0.5, size.height * 0.78);
    path.quadraticBezierTo(
        size.width * 0.25, size.height * 0.62, 0, size.height * 0.82);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
