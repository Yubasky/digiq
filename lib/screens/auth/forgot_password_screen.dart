// lib/screens/auth/forgot_password_screen.dart
//
// Layar permintaan reset kata sandi.
// Pesan sukses selalu netral untuk mencegah account enumeration.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/app_language.dart';
import '../../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool _isLoading = false;
  bool _sent = false;         // Tampilkan konfirmasi setelah kirim
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cooldown > 0 || _isLoading) return;

    setState(() => _isLoading = true);
    final result = await AuthService.resetPassword(_emailCtrl.text.trim());
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      // Selalu tampilkan pesan netral (tidak bocorkan apakah email terdaftar)
      setState(() => _sent = true);
      _startCooldown();
    } else {
      _showSnack(result.message ?? 'Terjadi kesalahan.');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Widget _buildLanguageSwitch() {
    return ValueListenableBuilder<AppLang>(
      valueListenable: AppLanguage.current,
      builder: (context, currentLang, _) {
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLangChip(
                label: 'ID',
                flag: '🇮🇩',
                isSelected: currentLang == AppLang.id,
                onTap: () => AppLanguage.setLanguage(AppLang.id),
              ),
              const SizedBox(width: 2),
              _buildLangChip(
                label: 'EN',
                flag: '🇬🇧',
                isSelected: currentLang == AppLang.en,
                onTap: () => AppLanguage.setLanguage(AppLang.en),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLangChip({
    required String label,
    required String flag,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: AppLanguage.current,
      builder: (context, lang, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: _buildLanguageSwitch()),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo
                      Center(
                        child: Image.asset(
                          'assets/img/Logo_digiq.png',
                          height: 64,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.bolt_rounded,
                                color: Colors.white, size: 36),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Card
                      Container(
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
                        child: _sent ? _buildSentState() : _buildFormState(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormState() {
    return Form(
      key: _formKey,
      child: Column(
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
              child: const Icon(Icons.lock_reset_rounded,
                  size: 40, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),

          Center(
            child: Text(
              AppLanguage.t('forgot_pwd_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.t('forgot_pwd_desc'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Email field
          Text(
            AppLanguage.t('email_address_label'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'contoh@email.com',
              hintStyle:
                  const TextStyle(color: AppColors.textMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.email_outlined,
                  color: AppColors.textMuted, size: 20),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
              ),
              filled: true,
              fillColor: AppColors.background,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return AppLanguage.t('email_required');
              final emailReg = RegExp(
                  r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
              if (!emailReg.hasMatch(v.trim())) return AppLanguage.t('email_invalid');
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: (_isLoading || _cooldown > 0) ? null : _submit,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(
                _cooldown > 0
                    ? '${AppLanguage.t('resend_in_cooldown')}${_cooldown}s'
                    : AppLanguage.t('send_reset_link'),
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

          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                AppLanguage.t('back_to_login'),
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentState() {
    return Column(
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
          child: const Icon(Icons.mark_email_read_outlined,
              size: 46, color: AppColors.success),
        ),
        const SizedBox(height: 24),
        Text(
          AppLanguage.t('check_email_title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: -0.5),
        ),
        const SizedBox(height: 10),
        Text(
          AppLanguage.t('check_email_desc'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 13.5, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 28),

        // Kirim ulang dengan cooldown
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: (_cooldown > 0 || _isLoading) ? null : _submit,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: Text(
              _cooldown > 0
                  ? '${AppLanguage.t('resend_in_cooldown')}${_cooldown}s'
                  : AppLanguage.t('resend_link_btn'),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                color: _cooldown > 0 ? AppColors.cardBorder : AppColors.primary,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => setState(() => _sent = false),
              child: Text(
                AppLanguage.t('change_email_btn'),
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const Text('•', style: TextStyle(color: AppColors.textMuted)),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                AppLanguage.t('back_to_login'),
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
