import 'package:flutter/material.dart';
import '../models/profile_model.dart';
import '../services/auth_service.dart';
import '../services/app_language.dart';
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

  // Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡ Supabase Login Flow with Fallback Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡

  Future<void> _doLogin() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;


    setState(() => _isLoading = true);

    try {
      final result = await AuthService.signIn(
        email: identifier,
        password: password,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!result.success) {
        final msg = result.message ?? AppLanguage.t('login_failed');
        if (msg.toLowerCase().contains('belum diverifikasi') ||
            msg.toLowerCase().contains('unverified') ||
            msg.toLowerCase().contains('not confirmed') ||
            msg.toLowerCase().contains('email_not_confirmed')) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EmailVerificationScreen(
                email: identifier.contains('@') ? identifier : null,
                initialStatus: VerificationStatus.waiting,
                errorMessage: msg,
              ),
            ),
          );
          return;
        } else {
          _showError(msg);
        }
        return;
      }

      ProfileModel? profile = result.profile;
      if (profile == null) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        profile = await AuthService.getCurrentProfile();
      }
      if (profile == null) {
        _showError(AppLanguage.t('profile_load_failed'));
        return;
      }

      _navigateToHome(profile);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(e.toString());
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡ Language Switch Widget Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡

  Widget _buildLanguageSwitch({bool inCard = false}) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: AppLanguage.current,
      builder: (context, currentLang, _) {
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: inCard
                ? AppColors.background
                : Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: inCard
                  ? AppColors.cardBorder
                  : Colors.white.withValues(alpha: 0.55),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: inCard ? 0.04 : 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLangOption(
                label: 'ID',
                flag: '🇮🇩',
                isSelected: currentLang == AppLang.id,
                inCard: inCard,
                onTap: () => AppLanguage.setLanguage(AppLang.id),
              ),
              const SizedBox(width: 2),
              _buildLangOption(
                label: 'EN',
                flag: '🇬🇧',
                isSelected: currentLang == AppLang.en,
                inCard: inCard,
                onTap: () => AppLanguage.setLanguage(AppLang.en),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLangOption({
    required String label,
    required String flag,
    required bool isSelected,
    required VoidCallback onTap,
    bool inCard = false,
  }) {
    final activeBg = inCard ? AppColors.primary : Colors.white;
    final activeText = inCard ? Colors.white : AppColors.primary;
    final inactiveText = inCard ? AppColors.textSecondary : Colors.white;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeText : inactiveText,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡ Build Screen Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡Î“Ã¶Ã‡

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return ValueListenableBuilder<AppLang>(
      valueListenable: AppLanguage.current,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              // Decorative background radial circles
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

              // Responsive wave illustration matching backup proportions
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: CustomPaint(
                  painter: _WavePainter(),
                  size: Size(size.width, (size.height * 0.42).clamp(300.0, 390.0)),
                ),
              ),

              SafeArea(
                child: Stack(
                  children: [
                    // Main Content ScrollView with Zero Gaps on all devices (including iPhone 16)
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isKeyboardOpen =
                                MediaQuery.of(context).viewInsets.bottom > 0;
                            return ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(scrollbars: false),
                              child: SingleChildScrollView(
                                physics: isKeyboardOpen
                                    ? const ClampingScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: IntrinsicHeight(
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 420),
                                        child: Column(
                                          children: [
                                            // Top spacer (dynamically adjusts for iPhone 16 / Galaxy A55)
                                            const Spacer(),

                                            // Hero Header: Logo & Subtitle
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Image.asset(
                                                  'assets/img/logo_digiq_putih.png',
                                                  height: 48,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (_, _, _) =>
                                                      const Text(
                                                    'DigiQ',
                                                    style: TextStyle(
                                                      fontSize: 26,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                      letterSpacing: 1,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  AppLanguage.t('tagline'),
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w400,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ],
                                            ),

                                            // Breathing room between logo and card
                                            const Spacer(),

                                            // Form card (elongated for mobile proportions from backup)
                                            Padding(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 20),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        22, 26, 22, 22),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(22),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppColors.primary
                                                          .withValues(alpha: 0.12),
                                                      blurRadius: 28,
                                                      offset: const Offset(0, 10),
                                                    ),
                                                  ],
                                                ),
                                                child: Form(
                                                  key: _formKey,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        AppLanguage.t('welcome_title'),
                                                        style: const TextStyle(
                                                          fontSize: 20,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppColors.textPrimary,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        AppLanguage.t('welcome_subtitle'),
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                          color: AppColors.textSecondary,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 18),

                                                      // Identifier field
                                                      Text(
                                                        AppLanguage.t('email_username_label'),
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: AppColors
                                                              .textPrimary,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      TextFormField(
                                                        controller:
                                                            _identifierController,
                                                        keyboardType:
                                                            TextInputType
                                                                .emailAddress,
                                                        textInputAction:
                                                            TextInputAction.next,
                                                        style: const TextStyle(
                                                            fontSize: 13.5),
                                                        decoration:
                                                            InputDecoration(
                                                          hintText:
                                                              AppLanguage.t('email_username_hint'),
                                                          hintStyle:
                                                              const TextStyle(
                                                            color: AppColors
                                                                .textMuted,
                                                            fontSize: 12.5,
                                                          ),
                                                          prefixIcon: const Icon(
                                                              Icons
                                                                  .person_outline_rounded,
                                                              color: AppColors
                                                                  .textMuted,
                                                              size: 18),
                                                          isDense: true,
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 14,
                                                                  vertical: 12),
                                                          border: OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          10)),
                                                          enabledBorder:
                                                              OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10),
                                                            borderSide:
                                                                const BorderSide(
                                                                    color: AppColors
                                                                        .cardBorder),
                                                          ),
                                                          focusedBorder:
                                                              OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10),
                                                            borderSide:
                                                                const BorderSide(
                                                                    color: AppColors
                                                                        .primary,
                                                                    width: 2),
                                                          ),
                                                          filled: true,
                                                          fillColor: AppColors
                                                              .background,
                                                        ),
                                                        validator: (v) {
                                                          if (v == null ||
                                                              v.trim().isEmpty) {
                                                            return AppLanguage.t('email_required');
                                                          }
                                                          return null;
                                                        },
                                                      ),

                                                      const SizedBox(height: 14),

                                                      // Password field
                                                      Text(
                                                        AppLanguage.t('password_label'),
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: AppColors
                                                              .textPrimary,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      TextFormField(
                                                        controller:
                                                            _passwordController,
                                                        obscureText:
                                                            _obscurePassword,
                                                        textInputAction:
                                                            TextInputAction.done,
                                                        onFieldSubmitted: (_) =>
                                                            _doLogin(),
                                                        style: const TextStyle(
                                                            fontSize: 13.5),
                                                        decoration:
                                                            InputDecoration(
                                                          hintText:
                                                              AppLanguage.t('password_hint'),
                                                          hintStyle:
                                                              const TextStyle(
                                                            color: AppColors
                                                                .textMuted,
                                                            fontSize: 12.5,
                                                          ),
                                                          prefixIcon: const Icon(
                                                              Icons
                                                                  .lock_outline_rounded,
                                                              color: AppColors
                                                                  .textMuted,
                                                              size: 18),
                                                          suffixIcon: IconButton(
                                                            icon: Icon(
                                                              _obscurePassword
                                                                  ? Icons
                                                                      .visibility_outlined
                                                                  : Icons
                                                                      .visibility_off_outlined,
                                                              color: AppColors
                                                                  .textMuted,
                                                              size: 18,
                                                            ),
                                                            onPressed: () =>
                                                                setState(() =>
                                                                    _obscurePassword =
                                                                        !_obscurePassword),
                                                          ),
                                                          isDense: true,
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 14,
                                                                  vertical: 12),
                                                          border: OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          10)),
                                                          enabledBorder:
                                                              OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10),
                                                            borderSide:
                                                                const BorderSide(
                                                                    color: AppColors
                                                                        .cardBorder),
                                                          ),
                                                          focusedBorder:
                                                              OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10),
                                                            borderSide:
                                                                const BorderSide(
                                                                    color: AppColors
                                                                        .primary,
                                                                    width: 2),
                                                          ),
                                                          filled: true,
                                                          fillColor: AppColors
                                                              .background,
                                                        ),
                                                        validator: (v) {
                                                          if (v == null ||
                                                              v.isEmpty) {
                                                            return AppLanguage.t('password_required');
                                                          }
                                                          return null;
                                                        },
                                                      ),

                                                      const SizedBox(height: 10),

                                                      // Remember me + forgot password row
                                                      Row(
                                                        children: [
                                                          GestureDetector(
                                                            onTap: () => setState(
                                                                () =>
                                                                    _rememberMe =
                                                                        !_rememberMe),
                                                            child: Row(
                                                              children: [
                                                                AnimatedContainer(
                                                                  duration:
                                                                      const Duration(
                                                                          milliseconds:
                                                                              200),
                                                                  width: 16,
                                                                  height: 16,
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: _rememberMe
                                                                        ? AppColors
                                                                            .primary
                                                                        : Colors
                                                                            .white,
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                                4),
                                                                    border:
                                                                        Border.all(
                                                                      color: _rememberMe
                                                                          ? AppColors
                                                                              .primary
                                                                          : AppColors
                                                                              .cardBorder,
                                                                      width:
                                                                          1.5,
                                                                    ),
                                                                  ),
                                                                  child: _rememberMe
                                                                      ? const Icon(
                                                                          Icons
                                                                              .check,
                                                                          color: Colors
                                                                              .white,
                                                                          size:
                                                                              10)
                                                                      : null,
                                                                ),
                                                                const SizedBox(
                                                                    width: 6),
                                                                Text(
                                                                  AppLanguage.t('remember_me'),
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        11.5,
                                                                    color: AppColors
                                                                        .textSecondary,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          const Spacer(),
                                                          TextButton(
                                                            onPressed: () {
                                                              Navigator.of(
                                                                      context)
                                                                  .push(
                                                                MaterialPageRoute(
                                                                  builder: (_) =>
                                                                      const ForgotPasswordScreen(),
                                                                ),
                                                              );
                                                            },
                                                            style: TextButton
                                                                .styleFrom(
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              minimumSize:
                                                                  Size.zero,
                                                              tapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                            ),
                                                            child: Text(
                                                              AppLanguage.t('forgot_password'),
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11.5,
                                                                color: AppColors
                                                                    .primary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),

                                                      const SizedBox(height: 16),

                                                      // Login button
                                                      SizedBox(
                                                        width: double.infinity,
                                                        height: 46,
                                                        child: ElevatedButton(
                                                          onPressed: _isLoading
                                                              ? null
                                                              : _doLogin,
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                AppColors
                                                                    .primary,
                                                            foregroundColor:
                                                                Colors.white,
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12),
                                                            ),
                                                            elevation: 0,
                                                          ),
                                                          child: _isLoading
                                                              ? const SizedBox(
                                                                  width: 20,
                                                                  height: 20,
                                                                  child:
                                                                      CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2.5,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                )
                                                              : Text(
                                                                  AppLanguage.t('login_btn'),
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        14.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                        ),
                                                      ),

                                                      const SizedBox(height: 12),

                                                      // Divider
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                              child: Divider(
                                                                  color: AppColors
                                                                      .cardBorder,
                                                                  thickness:
                                                                      1)),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        10),
                                                            child: Text(
                                                              AppLanguage.t('or_divider'),
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11,
                                                                color: AppColors
                                                                    .textMuted,
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                              child: Divider(
                                                                  color: AppColors
                                                                      .cardBorder,
                                                                  thickness:
                                                                      1)),
                                                        ],
                                                      ),

                                                      const SizedBox(height: 12),

                                                      // Register button
                                                      SizedBox(
                                                        width: double.infinity,
                                                        height: 42,
                                                        child: OutlinedButton
                                                            .icon(
                                                          onPressed: () {
                                                            Navigator.of(
                                                                    context)
                                                                .push(
                                                              PageRouteBuilder(
                                                                pageBuilder: (_,
                                                                        anim,
                                                                        _) =>
                                                                    const RegisterScreen(),
                                                                transitionsBuilder:
                                                                    (_,
                                                                        anim,
                                                                        _,
                                                                        child) =>
                                                                        SlideTransition(
                                                                  position: Tween<
                                                                          Offset>(
                                                                    begin: const Offset(
                                                                        1, 0),
                                                                    end: Offset
                                                                        .zero,
                                                                  ).animate(
                                                                      anim),
                                                                  child: child,
                                                                ),
                                                                transitionDuration:
                                                                    const Duration(
                                                                        milliseconds:
                                                                            350),
                                                              ),
                                                            );
                                                          },
                                                          icon: const Icon(
                                                              Icons
                                                                  .person_add_outlined,
                                                              size: 16),
                                                          label: Text(
                                                            AppLanguage.t('create_account_btn'),
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                          style: OutlinedButton
                                                              .styleFrom(
                                                            foregroundColor:
                                                                AppColors
                                                                    .primary,
                                                            side: const BorderSide(
                                                                color: AppColors
                                                                    .primary,
                                                                width: 1.5),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Bottom spacer balancing the card to center
                                            const Spacer(),

                                            // Bottom subtle branding
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: Text(
                                                AppLanguage.t('footer_branding'),
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: AppColors.textMuted,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Top-right language switch pill floating on top of hero wave
                    Positioned(
                      top: 12,
                      right: 16,
                      child: _buildLanguageSwitch(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
