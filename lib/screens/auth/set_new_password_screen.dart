// lib/screens/auth/set_new_password_screen.dart
//
// Layar pengaturan kata sandi baru setelah verifikasi link recovery berhasil.
// - Dua field password + konfirmasi, toggle tampilkan/sembunyikan.
// - Validasi minimal 8 karakter dan kecocokan.
// - Sukses → signOut → kembali ke login dengan snackbar.
// - Flag isPasswordRecovery di AuthGateScreen mencegah routing ke dashboard
//   selama layar ini aktif.

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../login_screen.dart';

class SetNewPasswordScreen extends StatefulWidget {
  /// Dipanggil oleh AuthGateScreen setelah signOut selesai agar ia
  /// bisa mereset flag _isPasswordRecovery.
  final VoidCallback? onDone;

  const SetNewPasswordScreen({super.key, this.onDone});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pwdCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscurePwd = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMsg;
  bool _success = false;

  @override
  void dispose() {
    if (!_success) {
      // Pastikan sesi recovery ditutup jika user menutup layar tanpa ganti password
      AuthService.signOut();
    }
    // Pastikan password tidak tersimpan di memori lebih lama dari perlu
    _pwdCtrl.clear();
    _confirmCtrl.clear();
    _pwdCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _cancelAndExit() async {
    await AuthService.signOut();
    widget.onDone?.call();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final result = await AuthService.changePassword(_pwdCtrl.text);

    if (!mounted) return;

    if (result.success) {
      // Bersihkan field sebelum signOut agar password tidak tersisa
      _pwdCtrl.clear();
      _confirmCtrl.clear();

      setState(() {
        _isLoading = false;
        _success = true;
      });

      // Tunggu sebentar agar pesan sukses sempat terbaca, lalu signOut
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      await AuthService.signOut();
      widget.onDone?.call();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
            'Kata sandi berhasil diubah. Silakan masuk dengan kata sandi baru Anda.'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ));
    } else {
      setState(() {
        _isLoading = false;
        _errorMsg = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Jangan biarkan user menekan back ke dashboard selama recovery aktif.
      // Jika mencoba pop atau navigasi keluar, lakukan cancel dan sign out.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _cancelAndExit();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
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
                  child: _success ? _buildSuccessCard() : _buildForm(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: AppColors.successLight,
            shape: BoxShape.circle,
            border: Border.all(
                color: AppColors.success.withValues(alpha: 0.35), width: 2.5),
          ),
          child: const Icon(Icons.check_circle_rounded,
              size: 54, color: AppColors.success),
        ),
        const SizedBox(height: 24),
        const Text(
          'Kata Sandi Berhasil Diubah!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Anda akan dialihkan ke halaman login dalam beberapa saat...',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35), width: 2),
              ),
              child: const Icon(Icons.lock_open_rounded,
                  size: 40, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Buat Kata Sandi Baru',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Masukkan kata sandi baru Anda di bawah. Pastikan minimal 8 karakter.',
            style: TextStyle(
                fontSize: 13.5, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),

          // Password baru
          const Text(
            'Kata Sandi Baru',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _pwdCtrl,
            obscureText: _obscurePwd,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(
              hint: 'Minimal 8 karakter',
              icon: Icons.lock_outline_rounded,
              suffixIcon: _toggleIcon(_obscurePwd,
                  () => setState(() => _obscurePwd = !_obscurePwd)),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Kata sandi wajib diisi';
              if (v.length < 8) return 'Kata sandi minimal 8 karakter';
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Konfirmasi
          const Text(
            'Konfirmasi Kata Sandi',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(
              hint: 'Ulangi kata sandi',
              icon: Icons.lock_outline_rounded,
              suffixIcon: _toggleIcon(_obscureConfirm,
                  () => setState(() => _obscureConfirm = !_obscureConfirm)),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Konfirmasi kata sandi wajib diisi';
              if (v != _pwdCtrl.text) return 'Kata sandi tidak cocok';
              return null;
            },
          ),

          // Pesan error
          if (_errorMsg != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.error, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submit,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded, size: 22),
              label: Text(
                _isLoading ? 'Menyimpan...' : 'Simpan Kata Sandi Baru',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tombol Batal & Keluar (Sign Out demi keamanan)
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : _cancelAndExit,
              child: const Text(
                'Batalkan dan Kembali ke Login',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      filled: true,
      fillColor: AppColors.background,
    );
  }

  Widget _toggleIcon(bool obscure, VoidCallback onTap) {
    return IconButton(
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: AppColors.textMuted,
        size: 20,
      ),
      onPressed: onTap,
    );
  }
}
