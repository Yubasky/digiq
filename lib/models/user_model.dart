class UserRole {
  static const String admin = 'admin';
  static const String customer = 'customer';
}

class UserAccount {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String password;
  final String role;
  final DateTime createdAt;

  UserAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    required this.role,
    required this.createdAt,
  });
}

/// Simple in-memory user store (for prototype, no DB yet)
class UserStore {
  static final List<UserAccount> _users = [];

  // Seed admin (hardcoded for prototype)
  static final UserAccount adminAccount = UserAccount(
    id: 'admin-001',
    name: 'Admin DigiQ',
    email: 'admin',
    phone: '08123456789',
    password: 'admin123',
    role: UserRole.admin,
    createdAt: DateTime(2024, 1, 1),
  );

  static List<UserAccount> get users => _users;

  static void registerUser(UserAccount user) {
    _users.add(user);
  }

  /// Returns [UserAccount] if credentials match, null otherwise.
  static UserAccount? login(String emailOrUsername, String password) {
    // Check admin first
    if ((emailOrUsername == 'admin' || emailOrUsername == adminAccount.email) &&
        password == adminAccount.password) {
      return adminAccount;
    }
    // Check registered customers
    try {
      return _users.firstWhere(
        (u) => (u.email == emailOrUsername || u.phone == emailOrUsername) && u.password == password,
      );
    } catch (_) {
      return null;
    }
  }

  static bool isEmailTaken(String email) {
    return _users.any((u) => u.email == email);
  }

  static bool isPhoneTaken(String phone) {
    return _users.any((u) => u.phone == phone);
  }
}
