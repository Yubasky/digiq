// test/auth_backdoor_regression_test.dart
//
// Regression tests for hardcoded backdoor elimination:
// (a) Widget test: Entering "admin"/"admin123" NEVER navigates to AdminDashboardScreen
//     or CustomerDashboardScreen, and routes exclusively through normal Supabase auth.
// (b) Static analysis test: Scans all Dart files under lib/ to guarantee no occurrences
//     of "admin123", "admin-mock", "mock-id", or hardcoded password equality checks.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:digiq/screens/admin_dashboard_screen.dart';
import 'package:digiq/screens/auth/email_verification_screen.dart';
import 'package:digiq/screens/customer_dashboard_screen.dart';
import 'package:digiq/screens/login_screen.dart';
import 'package:digiq/screens/register_screen.dart';
import 'package:digiq/services/app_language.dart';
import 'package:digiq/services/auth_service.dart';
import 'package:digiq/services/supabase_config.dart';

// ─── Fake Implementations for Backdoor Test ──────────────────────────────────

class _FakeUser extends Fake implements User {
  @override
  final String id;
  @override
  final String? email;
  @override
  final String? emailConfirmedAt;
  @override
  final List<UserIdentity>? identities;

  _FakeUser({
    required this.id,
    this.email,
    this.emailConfirmedAt,
    this.identities,
  });
}

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  int signInCallCount = 0;
  int signOutCallCount = 0;
  String? lastSignInEmail;
  String? lastSignInPassword;
  bool returnUnconfirmedUserOnSignIn = false;

  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    signOutCallCount++;
  }

  @override
  Future<AuthResponse> signUp({
    required String password,
    String? email,
    String? phone,
    String? emailRedirectTo,
    Map<String, dynamic>? data,
    String? captchaToken,
    OtpChannel channel = OtpChannel.sms,
  }) async {
    return AuthResponse(
      user: _FakeUser(
        id: 'new-user-123',
        email: email,
        emailConfirmedAt: null,
        identities: [
          const UserIdentity(
            id: 'ident-1',
            identityId: 'ident-1',
            userId: 'new-user-123',
            identityData: {},
            provider: 'email',
            createdAt: '2026-01-01',
            lastSignInAt: '2026-01-01',
          ),
        ],
      ),
    );
  }

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    signInCallCount++;
    lastSignInEmail = email;
    lastSignInPassword = password;
    if (returnUnconfirmedUserOnSignIn) {
      return AuthResponse(
        user: _FakeUser(
          id: 'unconfirmed-user-456',
          email: email,
          emailConfirmedAt: null,
        ),
      );
    }
    throw const AuthException('Invalid login credentials', statusCode: '400');
  }
}

class _FakeRpcFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final dynamic _result;
  _FakeRpcFilterBuilder(this._result);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) async {
    return onValue(_result as T);
  }

  @override
  Future<T> timeout(
    Duration timeLimit, {
    FutureOr<T> Function()? onTimeout,
  }) async {
    return _result as T;
  }
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  final _FakeGoTrueClient fakeAuth = _FakeGoTrueClient();
  int rpcCallCount = 0;
  String? lastRpcFn;
  Map<String, dynamic>? lastRpcParams;

  @override
  GoTrueClient get auth => fakeAuth;

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    dynamic get,
  }) {
    rpcCallCount++;
    lastRpcFn = fn;
    lastRpcParams = params;
    // resolve_login_email for "admin" returns null to simulate unmapped username
    return _FakeRpcFilterBuilder<T>(null);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    AppLanguage.setLanguage(AppLang.id);
  });

  group('Backdoor Remediation & Route Guard Regression Tests', () {
    late _FakeSupabaseClient fakeClient;

    setUp(() {
      fakeClient = _FakeSupabaseClient();
      SupabaseConfig.testClient = fakeClient;
      AuthService.clearUsernameCache();
    });

    tearDown(() {
      SupabaseConfig.testClient = null;
    });

    testWidgets(
      'admin/admin123 does NOT bypass to AdminDashboardScreen and routes through normal auth',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const MaterialApp(
            home: LoginScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify LoginScreen is shown
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(AdminDashboardScreen), findsNothing);
        expect(find.byType(CustomerDashboardScreen), findsNothing);

        // 2. Input 'admin' and 'admin123'
        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(2));

        await tester.enterText(textFields.at(0), 'admin');
        await tester.enterText(textFields.at(1), 'admin123');
        await tester.pumpAndSettle();

        // 3. Find and tap login button
        final loginButton = find.byType(ElevatedButton);
        expect(loginButton, findsOneWidget);
        await tester.tap(loginButton);
        await tester.pumpAndSettle();

        // 4. Assert that NO backdoor navigation occurred
        expect(find.byType(AdminDashboardScreen), findsNothing);
        expect(find.byType(CustomerDashboardScreen), findsNothing);
        expect(find.byType(LoginScreen), findsOneWidget);

        // 5. Assert that normal auth pipeline was invoked (resolve_login_email RPC called)
        expect(fakeClient.rpcCallCount, greaterThanOrEqualTo(1));
        expect(fakeClient.lastRpcFn, equals('resolve_login_email'));
        expect(fakeClient.lastRpcParams?['p_identifier'], equals('admin'));

        // 6. Assert error message was shown
        expect(find.text('Email atau password salah.'), findsOneWidget);
      },
    );

    test('Static scan of lib/ verifies NO hardcoded backdoor credentials exist', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final backdoorRegex = RegExp(r"admin123|admin-mock|mock-id", caseSensitive: false);
      final hardcodedPasswordRegex = RegExp(r'''password\s*==\s*['"][^'"]+['"]''', caseSensitive: false);

      final violations = <String>[];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (backdoorRegex.hasMatch(line)) {
            violations.add('${file.path}:${i + 1} matches backdoor keyword: ${line.trim()}');
          }
          if (hardcodedPasswordRegex.hasMatch(line)) {
            violations.add('${file.path}:${i + 1} matches hardcoded password check: ${line.trim()}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Hardcoded backdoor credentials detected in lib/:\n${violations.join('\n')}',
      );
    });

    test('AuthService.signIn blocks unverified accounts and triggers signOut', () async {
      fakeClient.fakeAuth.returnUnconfirmedUserOnSignIn = true;

      final res = await AuthService.signIn(
        email: 'unconfirmed@digiq.com',
        password: 'PasswordValid123',
      );

      expect(res.success, isFalse);
      expect(res.isConfirmed, isFalse);
      expect(res.message, contains('belum diverifikasi'));
      expect(fakeClient.fakeAuth.signOutCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets('RegisterScreen navigates exclusively to EmailVerificationScreen and never to CustomerDashboardScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: RegisterScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.byType(CustomerDashboardScreen), findsNothing);
      expect(find.byType(EmailVerificationScreen), findsNothing);

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(5));

      // Fill registration form: name, email, phone, password, confirmPassword
      await tester.enterText(textFields.at(0), 'Pelanggan Baru');
      await tester.enterText(textFields.at(1), 'newuser@digiq.com');
      await tester.enterText(textFields.at(2), '081234567890');
      await tester.enterText(textFields.at(3), 'SecurePass123!');
      await tester.enterText(textFields.at(4), 'SecurePass123!');
      await tester.pumpAndSettle();

      final registerButton = find.byType(ElevatedButton);
      expect(registerButton, findsOneWidget);
      await tester.tap(registerButton);
      await tester.pumpAndSettle();

      // STRICT ASSERTION:
      // Must NOT navigate to CustomerDashboardScreen or AdminDashboardScreen
      expect(find.byType(CustomerDashboardScreen), findsNothing);
      expect(find.byType(AdminDashboardScreen), findsNothing);

      // Must navigate strictly to EmailVerificationScreen
      expect(find.byType(EmailVerificationScreen), findsOneWidget);
    });
  });
}

