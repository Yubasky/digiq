// lib/models/profile_model.dart

class ProfileModel {
  final String id;
  final String fullName;
  final String username;
  final String phone;
  final String? avatarUrl;
  final String role; // 'customer' | 'admin'
  final double balance;
  final bool is2faEnabled;
  final DateTime updatedAt;
  final DateTime? usernameChangedAt;

  const ProfileModel({
    required this.id,
    required this.fullName,
    this.username = '',
    required this.phone,
    this.avatarUrl,
    required this.role,
    required this.balance,
    required this.is2faEnabled,
    required this.updatedAt,
    this.usernameChangedAt,
  });

  bool get isAdmin => role == 'admin';

  /// Nama tampilan dinamis dengan fallback ke 'User'
  String get displayName {
    if (fullName.trim().isNotEmpty) {
      return fullName.trim().split(' ').first;
    }
    if (username.trim().isNotEmpty) {
      return username.trim();
    }
    return 'User';
  }

  factory ProfileModel.fromMap(Map<String, dynamic> m) {
    return ProfileModel(
      id: m['id'] as String,
      fullName: (m['full_name'] as String?) ?? '',
      username: (m['username'] as String?) ?? '',
      phone: (m['phone'] as String?) ?? '',
      avatarUrl: m['avatar_url'] as String?,
      role: (m['role'] as String?) ?? 'customer',
      balance: ((m['balance'] as num?) ?? 0).toDouble(),
      is2faEnabled: (m['is_2fa_enabled'] as bool?) ?? true,
      updatedAt: m['updated_at'] != null
          ? DateTime.parse(m['updated_at'] as String)
          : DateTime.now(),
      usernameChangedAt: m['username_changed_at'] != null
          ? DateTime.tryParse(m['username_changed_at'] as String)
          : null,
    );
  }

  ProfileModel copyWith({
    String? fullName,
    String? username,
    String? phone,
    String? avatarUrl,
    double? balance,
    bool? is2faEnabled,
    DateTime? usernameChangedAt,
  }) {
    return ProfileModel(
      id: id,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role,
      balance: balance ?? this.balance,
      is2faEnabled: is2faEnabled ?? this.is2faEnabled,
      updatedAt: updatedAt,
      usernameChangedAt: usernameChangedAt ?? this.usernameChangedAt,
    );
  }
}
