class UserRole {
  static const String admin = 'admin';
  static const String customer = 'customer';
}

class UserAccount {
  final String id;
  final String name;
  final String username;
  final String email;
  final String phone;
  final String password;
  final String role;
  final DateTime createdAt;

  UserAccount({
    required this.id,
    required this.name,
    this.username = '',
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
    username: 'admin',
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
    final query = emailOrUsername.trim().toLowerCase();
    // Check admin first
    if ((query == 'admin' || query == adminAccount.email.toLowerCase()) &&
        password == adminAccount.password) {
      return adminAccount;
    }
    // Check registered customers
    try {
      return _users.firstWhere(
        (u) =>
            (u.email.toLowerCase() == query ||
             u.username.toLowerCase() == query ||
             u.phone == query) &&
            u.password == password,
      );
    } catch (_) {
      return null;
    }
  }

  static bool isUsernameTaken(String username) {
    final clean = username.trim().toLowerCase();
    if (clean == 'admin') return true;
    return _users.any((u) => u.username.toLowerCase() == clean);
  }

  static bool isEmailTaken(String email) {
    return _users.any((u) => u.email.toLowerCase() == email.trim().toLowerCase());
  }

  static bool isPhoneTaken(String phone) {
    return _users.any((u) => u.phone == phone.trim());
  }
}
