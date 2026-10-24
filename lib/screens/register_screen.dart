import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_model.dart';
import '../theme/app_theme.dart';
import 'customer_dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _agreed = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _doRegister() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      _showSnack('Harap setujui syarat & ketentuan terlebih dahulu.', isError: true);
      return;
    }

    if (UserStore.isUsernameTaken(_usernameController.text.trim())) {
      _showSnack('Username sudah digunakan. Gunakan username lain.', isError: true);
      return;
    }
    if (UserStore.isEmailTaken(_emailController.text.trim())) {
      _showSnack('Email sudah digunakan. Gunakan email lain.', isError: true);
      return;
    }
    if (UserStore.isPhoneTaken(_phoneController.text.trim())) {
      _showSnack('Nomor HP sudah terdaftar.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 1200));

    final newUser = UserAccount(
      id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      username: _usernameController.text.trim().toLowerCase(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
      role: UserRole.customer,
      createdAt: DateTime.now(),
    );
    UserStore.registerUser(newUser);

    if (!mounted) return;
    setState(() => _isLoading = false);

    _showSnack('Akun berhasil dibuat! Selamat datang, ${newUser.name}.', isError: false);
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => CustomerDashboardScreen(currentUser: newUser),
        ),
        (route) => false,
      );
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Gradient header blob
          Positioned(
            top: -80,
            left: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x4006ACDC), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x3000B4D8), Colors.transparent],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Back button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: AppColors.textSecondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),

                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 480),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Logo + Title
                                    Center(
                                      child: Column(
                                        children: [
                                          Image.asset(
                                            'assets/img/Logo_digiq.png',
                                            height: 74,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, _, _) => Container(
                                              width: 74,
                                              height: 74,
                                              decoration: BoxDecoration(
                                                gradient: AppColors.primaryGradient,
                                                borderRadius: BorderRadius.circular(18),
                                              ),
                                              child: const Icon(Icons.bolt_rounded,
                                                  color: Colors.white, size: 40),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          const Text(
                                            'Buat Akun Baru',
                                            style: TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'Daftar dan nikmati kemudahan belanja produk digital',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 28),

                                    // Form card
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(alpha: 0.07),
                                            blurRadius: 24,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Form(
                                        key: _formKey,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildLabel('Nama Lengkap'),
                                            const SizedBox(height: 6),
                                            _buildTextField(
                                              controller: _nameController,
                                              hint: 'Masukkan nama lengkap',
                                              icon: Icons.person_outline_rounded,
                                              textInputAction: TextInputAction.next,
                                              validator: (v) {
                                                if (v == null || v.trim().isEmpty) return 'Nama wajib diisi';
                                                if (v.trim().length < 3) return 'Nama minimal 3 karakter';
                                                return null;
                                              },
                                            ),

                                            const SizedBox(height: 14),
                                            _buildLabel('Username'),
                                            const SizedBox(height: 6),
                                            _buildTextField(
                                              controller: _usernameController,
                                              hint: 'Contoh: bayup99',
                                              icon: Icons.alternate_email_rounded,
                                              textInputAction: TextInputAction.next,
                                              validator: (v) {
                                                if (v == null || v.trim().isEmpty) return 'Username wajib diisi';
                                                final u = v.trim();
                                                if (u.length < 3) return 'Username minimal 3 karakter';
                                                if (u.length > 20) return 'Username maksimal 20 karakter';
                                                if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(u)) {
                                                  return 'Hanya boleh huruf, angka, titik, atau garis bawah';
                                                }
                                                return null;
                                              },
                                            ),

                                            const SizedBox(height: 14),
                                            _buildLabel('Email'),
                                            const SizedBox(height: 6),
                                            _buildTextField(
                                              controller: _emailController,
                                              hint: 'contoh@email.com',
                                              icon: Icons.email_outlined,
                                              keyboardType: TextInputType.emailAddress,
                                              textInputAction: TextInputAction.next,
                                              validator: (v) {
                                                if (v == null || v.trim().isEmpty) return 'Email wajib diisi';
                                                final email = v.trim();
                                                if (!email.contains('@')) {
                                                  return 'Email harus menyertakan tanda @ (contoh: nama@gmail.com)';
                                                }
                                                final parts = email.split('@');
                                                if (parts.length != 2 || parts[0].isEmpty) {
                                                  return 'Format email tidak valid (contoh: nama@gmail.com)';
                                                }
                                                final domain = parts[1].trim();
                                                if (domain.isEmpty) {
                                                  return 'Masukkan penyedia email setelah @ (contoh: gmail.com, yahoo.com)';
                                                }
                                                if (!domain.contains('.')) {
                                                  return 'Masukkan domain lengkap setelah @ (contoh: gmail.com, yahoo.com)';
                                                }
                                                final domainParts = domain.split('.');
                                                if (domainParts[0].isEmpty || domainParts[1].isEmpty) {
                                                  return 'Format domain email tidak valid (contoh: gmail.com)';
                                                }
                                                final emailReg = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                                                if (!emailReg.hasMatch(email)) {
                                                  return 'Format email tidak valid (contoh: nama@gmail.com)';
                                                }
                                                return null;
                                              },
                                            ),

                                            const SizedBox(height: 14),
                                            _buildLabel('Nomor HP'),
                                            const SizedBox(height: 6),
                                            _buildTextField(
                                              controller: _phoneController,
                                              hint: '08xxxxxxxxxx',
                                              icon: Icons.phone_outlined,
                                              keyboardType: TextInputType.phone,
                                              textInputAction: TextInputAction.next,
                                              inputFormatters: [
                                                FilteringTextInputFormatter.digitsOnly,
                                                LengthLimitingTextInputFormatter(13),
                                              ],
                                              validator: (v) {
                                                if (v == null || v.trim().isEmpty) return 'Nomor HP wajib diisi';
                                                final phone = v.trim();
                                                if (!phone.startsWith('08')) return 'Nomor HP harus diawali 08';
                                                if (phone.length < 10) return 'Nomor HP minimal 10 digit (saat ini ${phone.length})';
                                                if (phone.length > 13) return 'Nomor HP maksimal 13 digit';
                                                return null;
                                              },
                                            ),

                                            const SizedBox(height: 14),
                                            _buildLabel('Password'),
                                            const SizedBox(height: 6),
                                            _buildTextField(
                                              controller: _passwordController,
                                              hint: 'Minimal 8 karakter',
                                              icon: Icons.lock_outline_rounded,
                                              obscure: _obscurePassword,
                                              textInputAction: TextInputAction.next,
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                                  color: AppColors.textMuted,
                                                  size: 20,
                                                ),
                                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                              ),
                                              validator: (v) {
                                                if (v == null || v.isEmpty) return 'Password wajib diisi';
                                                if (v.length < 8) return 'Password minimal 8 karakter';
                                                return null;
                                              },
                                            ),

                                            const SizedBox(height: 14),
                                            _buildLabel('Konfirmasi Password'),
                                            const SizedBox(height: 6),
                                            _buildTextField(
                                              controller: _confirmPasswordController,
                                              hint: 'Ulangi password',
                                              icon: Icons.lock_outline_rounded,
                                              obscure: _obscureConfirm,
                                              textInputAction: TextInputAction.done,
                                              onFieldSubmitted: (_) => _doRegister(),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                                  color: AppColors.textMuted,
                                                  size: 20,
                                                ),
                                                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                              ),
                                              validator: (v) {
                                                if (v == null || v.isEmpty) return 'Konfirmasi password wajib diisi';
                                                if (v != _passwordController.text) return 'Password tidak cocok';
                                                return null;
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // Agree checkbox
                                    GestureDetector(
                                      onTap: () => setState(() => _agreed = !_agreed),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color: _agreed ? AppColors.primary : Colors.white,
                                              borderRadius: BorderRadius.circular(5),
                                              border: Border.all(
                                                color: _agreed ? AppColors.primary : AppColors.cardBorder,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: _agreed
                                                ? const Icon(Icons.check, color: Colors.white, size: 13)
                                                : null,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: RichText(
                                              text: const TextSpan(
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: AppColors.textSecondary,
                                                  height: 1.4,
                                                ),
                                                children: [
                                                  TextSpan(text: 'Saya menyetujui '),
                                                  TextSpan(
                                                    text: 'Syarat & Ketentuan',
                                                    style: TextStyle(
                                                      color: AppColors.primary,
                                                      fontWeight: FontWeight.w600,
                                                      decoration: TextDecoration.underline,
                                                    ),
                                                  ),
                                                  TextSpan(text: ' serta '),
                                                  TextSpan(
                                                    text: 'Kebijakan Privasi',
                                                    style: TextStyle(
                                                      color: AppColors.primary,
                                                      fontWeight: FontWeight.w600,
                                                      decoration: TextDecoration.underline,
                                                    ),
                                                  ),
                                                  TextSpan(text: ' DigiQ.'),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    // Register button
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: ElevatedButton(
                                        onPressed: _isLoading ? null : _doRegister,
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
                                                'Daftar Sekarang',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                      ),
                                    ),

                                    const SizedBox(height: 20),

                                    // Already have account
                                    Center(
                                      child: GestureDetector(
                                        onTap: () => Navigator.of(context).pop(),
                                        child: RichText(
                                          text: const TextSpan(
                                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                            children: [
                                              TextSpan(text: 'Sudah punya akun? '),
                                              TextSpan(
                                                text: 'Masuk di sini',
                                                style: TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
