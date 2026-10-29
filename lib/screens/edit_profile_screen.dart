import 'package:flutter/foundation.dart';
// lib/screens/edit_profile_screen.dart
//
// Halaman Edit Profil Pelanggan DigiQ:
// - Edit Nama, No. HP, dan Username (via RPC update_my_profile aman)
// - Avatar upload ke bucket avatars (validasi ukuran <= 2MB, format jpg/png/webp)
// - Ganti Password & Ganti Email dengan alur konfirmasi
// - Dialog konfirmasi perubahan yang belum disimpan (PopScope)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../services/auth_service.dart';
import '../services/avatar_picker.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final ProfileModel profile;

  @visibleForTesting
  static bool enableWebUploadForTesting = false;

  @visibleForTesting
  static Future<PickedAvatarFile?> Function()? pickImageOverride;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late ProfileModel _currentProfile;

  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _phoneController;

  // Password controllers
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureOldPass = true;
  bool _obscureNewPass = true;
  bool _obscureConfirmPass = true;
  bool _isSavingPassword = false;

  // Email change controllers
  final _newEmailController = TextEditingController();
  bool _isUpdatingEmail = false;
  Timer? _debounceEmailTimer;
  EmailCheckStatus? _emailCheckStatus;
  bool _isCheckingEmail = false;

  // Username availability check
  Timer? _debounceUsernameTimer;
  int _usernameSeq = 0;
  bool _isCheckingUsername = false;
  UsernameCheckStatus? _usernameStatus;
  String? _usernameErrorText;

  bool _isSavingProfile = false;
  bool _isUploadingAvatar = false;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    _nameController = TextEditingController(text: _currentProfile.fullName);
    _usernameController = TextEditingController(text: _currentProfile.username);
    _phoneController = TextEditingController(text: _currentProfile.phone);

    _nameController.addListener(_markDirty);
    _phoneController.addListener(_markDirty);
    _usernameController.addListener(_onUsernameChanged);
    _newEmailController.addListener(_onEmailChanged);
  }

  void _markDirty() {
    final nameChanged = _nameController.text.trim() != _currentProfile.fullName.trim();
    final phoneChanged = _phoneController.text.trim() != _currentProfile.phone.trim();
    final usernameChanged = _usernameController.text.trim().toLowerCase() != _currentProfile.username.trim().toLowerCase();
    final isDirty = nameChanged || phoneChanged || usernameChanged;

    if (isDirty != _hasUnsavedChanges && mounted) {
      setState(() => _hasUnsavedChanges = isDirty);
    }
  }

  void _onUsernameChanged() {
    _markDirty();
    final input = _usernameController.text.trim().toLowerCase();
    _debounceUsernameTimer?.cancel();

    // Jika username sama persis dengan username saat ini, anggap valid dan skip RPC
    if (input == _currentProfile.username.trim().toLowerCase()) {
      setState(() {
        _isCheckingUsername = false;
        _usernameStatus = UsernameCheckStatus.available;
        _usernameErrorText = null;
      });
      return;
    }

    if (input.isEmpty) {
      setState(() {
        _isCheckingUsername = false;
        _usernameStatus = null;
        _usernameErrorText = null;
      });
      return;
    }

    final formatErr = AuthService.validateUsernameFormat(input);
    if (formatErr != null) {
      setState(() {
        _isCheckingUsername = false;
        _usernameStatus = UsernameCheckStatus.invalidFormat;
        _usernameErrorText = formatErr;
      });
      return;
    }

    final seq = ++_usernameSeq;
    setState(() {
      _isCheckingUsername = true;
      _usernameErrorText = null;
    });

    _debounceUsernameTimer = Timer(const Duration(milliseconds: 500), () async {
      final status = await AuthService.checkUsernameStatus(input);
      if (!mounted || seq != _usernameSeq) return;

      setState(() {
        _isCheckingUsername = false;
        _usernameStatus = status;
        _usernameErrorText = AuthService.getUsernameStatusMessage(status);
      });
    });
  }

  void _onEmailChanged() {
    final input = _newEmailController.text.trim().toLowerCase();
    _debounceEmailTimer?.cancel();

    if (input.isEmpty) {
      setState(() {
        _isCheckingEmail = false;
        _emailCheckStatus = null;
      });
      return;
    }

    final formatErr = AuthService.validateEmailFormat(input);
    if (formatErr != null) {
      setState(() {
        _isCheckingEmail = false;
        _emailCheckStatus = EmailCheckStatus.invalidFormat;
      });
      return;
    }

    setState(() => _isCheckingEmail = true);

    _debounceEmailTimer = Timer(const Duration(milliseconds: 500), () async {
      final status = await AuthService.checkEmailStatus(input);
      if (!mounted) return;
      setState(() {
        _isCheckingEmail = false;
        _emailCheckStatus = status;
      });
    });
  }

  @override
  void dispose() {
    _debounceUsernameTimer?.cancel();
    _debounceEmailTimer?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newEmailController.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_isUploadingAvatar) return;

    if (!kIsWeb && !EditProfileScreen.enableWebUploadForTesting) {
      _showSnack('Fitur upload foto profil saat ini hanya tersedia di versi web.', isError: true);
      return;
    }

    try {
      final picked = await (EditProfileScreen.pickImageOverride != null
          ? EditProfileScreen.pickImageOverride!()
          : pickAvatarImage());
      if (picked == null) return; // User cancel

      // Validasi format/ekstensi (jpg, jpeg, png, webp)
      const allowedExts = ['jpg', 'jpeg', 'png', 'webp'];
      if (!allowedExts.contains(picked.extension.toLowerCase())) {
        _showSnack('Format foto harus berupa JPG, PNG, atau WebP.', isError: true);
        return;
      }

      // Validasi ukuran maksimal 2 MB
      const maxBytes = 2 * 1024 * 1024;
      if (picked.sizeInBytes > maxBytes) {
        _showSnack('Ukuran foto profil maksimal 2 MB.', isError: true);
        return;
      }

      setState(() => _isUploadingAvatar = true);
      final uid = _currentProfile.id;
      final newFilePath = '$uid/avatar.${picked.extension.toLowerCase()}';

      // Hapus avatar lama di bucket jika format sebelumnya berbeda
      final oldAvatar = _currentProfile.avatarUrl;
      if (oldAvatar != null && oldAvatar.contains('/avatars/')) {
        try {
          final uri = Uri.parse(oldAvatar);
          final pathSegments = uri.pathSegments;
          final avatarIdx = pathSegments.indexOf('avatars');
          if (avatarIdx != -1 && avatarIdx + 1 < pathSegments.length) {
            final oldPath = pathSegments.sublist(avatarIdx + 1).join('/');
            if (oldPath != newFilePath && oldPath.isNotEmpty) {
              await SupabaseConfig.supabase.storage.from('avatars').remove([oldPath]);
            }
          }
        } catch (_) {
          // Abaikan kegagalan hapus file lama agar upload tetap berjalan
        }
      }

      // Upload binary dengan upsert ke bucket avatars
      await SupabaseConfig.supabase.storage.from('avatars').uploadBinary(
            newFilePath,
            picked.bytes,
            fileOptions: FileOptions(
              contentType: picked.mimeType,
              upsert: true,
            ),
          );

      // Ambil public url dengan cache buster (?v=timestamp)
      final baseUrl = SupabaseConfig.supabase.storage.from('avatars').getPublicUrl(newFilePath);
      final publicUrlWithTimestamp = '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      // Simpan URL ke tabel profiles
      await SupabaseConfig.supabase
          .from('profiles')
          .update({'avatar_url': publicUrlWithTimestamp})
          .eq('id', uid);

      setState(() {
        _currentProfile = _currentProfile.copyWith(avatarUrl: publicUrlWithTimestamp);
        _isUploadingAvatar = false;
      });

      _showSnack('Foto profil berhasil diperbarui.');
    } catch (_) {
      setState(() => _isUploadingAvatar = false);
      _showSnack('Gagal mengunggah foto profil. Periksa koneksi Anda.', isError: true);
    }
  }

  Future<void> _saveProfileChanges() async {
    if (_isSavingProfile || _isCheckingUsername) return;

    final newUsername = _usernameController.text.trim().toLowerCase();
    final isUsernameChanged = newUsername != _currentProfile.username.trim().toLowerCase();

    if (isUsernameChanged && _usernameStatus == UsernameCheckStatus.taken) {
      _showSnack('Username ini telah digunakan pengguna lain.', isError: true);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingProfile = true);

    final res = await AuthService.updateMyProfile(
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      username: newUsername,
    );

    if (!mounted) return;
    setState(() => _isSavingProfile = false);

    if (res.success && res.profile != null) {
      setState(() {
        _currentProfile = res.profile!;
        _hasUnsavedChanges = false;
      });
      _showSnack(res.message ?? 'Profil berhasil diperbarui.');
    } else {
      _showSnack(res.message ?? 'Gagal memperbarui profil.', isError: true);
    }
  }

  Future<void> _saveNewPassword() async {
    final oldPass = _oldPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (oldPass.isEmpty) {
      _showSnack('Masukkan password saat ini.', isError: true);
      return;
    }
    if (newPass.isEmpty) {
      _showSnack('Masukkan password baru.', isError: true);
      return;
    }
    if (newPass.length < 8) {
      _showSnack('Password baru minimal 8 karakter.', isError: true);
      return;
    }
    if (newPass != confirmPass) {
      _showSnack('Konfirmasi password baru tidak cocok.', isError: true);
      return;
    }

    setState(() => _isSavingPassword = true);
    final res = await AuthService.changePasswordWithOld(
      oldPassword: oldPass,
      newPassword: newPass,
    );
    if (!mounted) return;
    setState(() => _isSavingPassword = false);

    if (res.success) {
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _showSnack(res.message ?? 'Password berhasil diperbarui.');
    } else {
      _showSnack(res.message ?? 'Gagal mengubah password.', isError: true);
    }
  }

  Future<void> _requestEmailChange() async {
    final newEmail = _newEmailController.text.trim().toLowerCase();
    final err = AuthService.validateEmailFormat(newEmail);
    if (err != null) {
      _showSnack(err, isError: true);
      return;
    }

    if (_emailCheckStatus == EmailCheckStatus.taken) {
      _showSnack('Email ini sudah terdaftar oleh pengguna lain.', isError: true);
      return;
    }

    setState(() => _isUpdatingEmail = true);
    final res = await AuthService.updateEmailAddress(newEmail);
    if (!mounted) return;
    setState(() => _isUpdatingEmail = false);

    if (res.success) {
      _newEmailController.clear();
      _showSnack(res.message ?? 'Tautan konfirmasi telah dikirim.');
    } else {
      _showSnack(res.message ?? 'Gagal mengajukan perubahan email.', isError: true);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Perubahan Belum Disimpan'),
        content: const Text('Anda memiliki perubahan profil yang belum disimpan. Keluar tanpa menyimpan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tetap di Sini'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    return shouldLeave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = SupabaseConfig.supabase.auth.currentUser?.email ?? 'Tidak diketahui';

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _onWillPop();
        if (leave && context.mounted) {
          Navigator.pop(context, _currentProfile);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(
            'Edit Profil',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          centerTitle: true,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (await _onWillPop() && context.mounted) {
                Navigator.pop(context, _currentProfile);
              }
            },
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Header Avatar
                  _buildAvatarSection(),
                  const SizedBox(height: 24),

                  // 2. Form Profil Utama
                  _buildMainProfileCard(userEmail),
                  const SizedBox(height: 20),

                  // 3. Bagian Ganti Password
                  _buildPasswordCard(),
                  const SizedBox(height: 20),

                  // 4. Bagian Ganti Email
                  _buildEmailChangeCard(userEmail),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    final hasAvatar = _currentProfile.avatarUrl != null && _currentProfile.avatarUrl!.isNotEmpty;
    final initials = _currentProfile.fullName.isNotEmpty
        ? _currentProfile.fullName[0].toUpperCase()
        : (_currentProfile.username.isNotEmpty ? _currentProfile.username[0].toUpperCase() : '?');

    return Center(
      child: Stack(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryLight,
              border: Border.all(color: AppColors.primary, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: hasAvatar
                  ? Image.network(
                      _currentProfile.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Text(
                          initials,
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        initials,
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ),
            ),
          ),
          if (_isUploadingAvatar)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.4),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            right: 0,
            child: InkWell(
              key: const Key('edit_profile_avatar_picker_button'),
              onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainProfileCard(String userEmail) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informasi Pribadi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),

            // Nama Lengkap
            _buildLabel('Nama Lengkap'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('edit_profile_name_field'),
              controller: _nameController,
              decoration: _inputDecoration(
                hint: 'Nama Lengkap Anda',
                icon: Icons.person_outline_rounded,
              ),
              validator: AuthService.validateFullNameFormat,
            ),
            const SizedBox(height: 16),

            // Username
            _buildLabel('Username'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('edit_profile_username_field'),
              controller: _usernameController,
              decoration: _inputDecoration(
                hint: 'username (5-20 alfanumerik)',
                icon: Icons.alternate_email_rounded,
                suffixIcon: _isCheckingUsername
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      )
                    : (_usernameStatus == UsernameCheckStatus.available
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                        : (_usernameStatus == UsernameCheckStatus.taken
                            ? const Icon(Icons.cancel_rounded, color: AppColors.error, size: 20)
                            : null)),
              ),
              validator: (v) {
                final formatErr = AuthService.validateUsernameFormat(v);
                if (formatErr != null) return formatErr;
                final input = v!.trim().toLowerCase();
                if (input != _currentProfile.username.trim().toLowerCase() &&
                    _usernameStatus == UsernameCheckStatus.taken) {
                  return 'Username ini telah digunakan';
                }
                return null;
              },
            ),
            if (_usernameErrorText != null && _usernameStatus == UsernameCheckStatus.taken) ...[
              const SizedBox(height: 6),
              Text(
                _usernameErrorText!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),

            // No. HP
            _buildLabel('Nomor HP'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('edit_profile_phone_field'),
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d+]')),
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: _inputDecoration(
                hint: '08xxxxxxxxxx atau +628xxxxxxxxxx',
                icon: Icons.phone_outlined,
              ),
              validator: AuthService.validatePhoneFormat,
            ),
            const SizedBox(height: 16),

            // Email (Read-only)
            _buildLabel('Alamat Email (Akun)'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('edit_profile_email_field'),
              initialValue: userEmail,
              readOnly: true,
              style: const TextStyle(color: AppColors.textSecondary),
              decoration: _inputDecoration(
                hint: userEmail,
                icon: Icons.email_outlined,
                suffixIcon: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textSecondary),
                      SizedBox(width: 4),
                      Text('Terkunci', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Tombol Simpan Profil
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('edit_profile_save_button'),
                onPressed: (_isSavingProfile || !_hasUnsavedChanges) ? null : _saveProfileChanges,
                icon: _isSavingProfile
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: Text(
                  _isSavingProfile ? 'Menyimpan...' : 'Simpan Perubahan Profil',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.security_rounded, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Keamanan: Ubah Password',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildLabel('Password Saat Ini'),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('edit_profile_old_password_field'),
            controller: _oldPasswordController,
            obscureText: _obscureOldPass,
            decoration: _inputDecoration(
              hint: 'Password akun Anda saat ini',
              icon: Icons.lock_clock_outlined,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureOldPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscureOldPass = !_obscureOldPass),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildLabel('Password Baru (Minimal 8 Karakter)'),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('edit_profile_new_password_field'),
            controller: _newPasswordController,
            obscureText: _obscureNewPass,
            decoration: _inputDecoration(
              hint: 'Minimal 8 karakter',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNewPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscureNewPass = !_obscureNewPass),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildLabel('Konfirmasi Password Baru'),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('edit_profile_confirm_password_field'),
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPass,
            decoration: _inputDecoration(
              hint: 'Ulangi password baru',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscureConfirmPass = !_obscureConfirmPass),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              key: const Key('edit_profile_save_password_button'),
              onPressed: _isSavingPassword ? null : _saveNewPassword,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSavingPassword
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Text('Simpan Password Baru', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailChangeCard(String currentEmail) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mark_email_read_outlined, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Perbarui Alamat Email',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Tautan konfirmasi akan dikirimkan ke email baru Anda. Alamat email akun hanya akan berubah setelah Anda mengklik tautan konfirmasi tersebut.',
              style: TextStyle(fontSize: 12.5, color: AppColors.primaryDark, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          _buildLabel('Alamat Email Baru'),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('edit_profile_new_email_field'),
            controller: _newEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDecoration(
              hint: 'emailbaru@contoh.com',
              icon: Icons.alternate_email_rounded,
              suffixIcon: _isCheckingEmail
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      ),
                    )
                  : (_emailCheckStatus == EmailCheckStatus.available
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                      : (_emailCheckStatus == EmailCheckStatus.taken
                          ? const Icon(Icons.cancel_rounded, color: AppColors.error, size: 20)
                          : (_emailCheckStatus == EmailCheckStatus.networkError
                              ? const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 20)
                              : null))),
            ),
          ),
          if (_emailCheckStatus != null &&
              _emailCheckStatus != EmailCheckStatus.available &&
              _emailCheckStatus != EmailCheckStatus.invalidFormat) ...[
            const SizedBox(height: 6),
            Text(
              AuthService.getEmailStatusMessage(_emailCheckStatus!) ?? '',
              style: TextStyle(
                color: _emailCheckStatus == EmailCheckStatus.taken ? AppColors.error : AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              key: const Key('edit_profile_submit_email_button'),
              onPressed: _isUpdatingEmail ? null : _requestEmailChange,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isUpdatingEmail
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Text('Kirim Tautan Perubahan Email', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
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
      prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }
}
