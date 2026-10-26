// lib/models/profile_model.dart

class ProfileModel {
  final String id;
  final String fullName;
  final String phone;
  final String? avatarUrl;
  final String role; // 'customer' | 'admin'
  final double balance;
  final bool is2faEnabled;
  final DateTime updatedAt;

  const ProfileModel({
    required this.id,
    required this.fullName,
    required this.phone,
    this.avatarUrl,
    required this.role,
    required this.balance,
    required this.is2faEnabled,
    required this.updatedAt,
  });

  bool get isAdmin => role == 'admin';

  factory ProfileModel.fromMap(Map<String, dynamic> m) {
    return ProfileModel(
      id: m['id'] as String,
      fullName: (m['full_name'] as String?) ?? '',
      phone: (m['phone'] as String?) ?? '',
      avatarUrl: m['avatar_url'] as String?,
      role: (m['role'] as String?) ?? 'customer',
      balance: ((m['balance'] as num?) ?? 0).toDouble(),
      is2faEnabled: (m['is_2fa_enabled'] as bool?) ?? true,
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }

  ProfileModel copyWith({
    String? fullName,
    String? phone,
    String? avatarUrl,
    double? balance,
    bool? is2faEnabled,
  }) {
    return ProfileModel(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role,
      balance: balance ?? this.balance,
      is2faEnabled: is2faEnabled ?? this.is2faEnabled,
      updatedAt: updatedAt,
    );
  }
}
