// test/widget_dispose_lifecycle_test.dart
//
// Lifecycle unmount & dispose test:
// Pumps each core screen, then replaces it with const SizedBox() and advances ticks.
// Asserts that no leaks, unhandled timer exceptions, or setState after dispose occur:
// - LoginScreen
// - RegisterScreen
// - EmailVerificationScreen
// - CustomerDashboardScreen
// - AdminDashboardScreen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:digiq/models/profile_model.dart';
import 'package:digiq/screens/admin_dashboard_screen.dart';
import 'package:digiq/screens/auth/email_verification_screen.dart';
import 'package:digiq/screens/customer_dashboard_screen.dart';
import 'package:digiq/screens/login_screen.dart';
import 'package:digiq/screens/register_screen.dart';
import 'package:digiq/services/app_language.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    AppLanguage.setLanguage(AppLang.id);
    try {
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        publishableKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_token_signature_ok',
      );
    } catch (_) {
      // Supabase already initialized or test environment mock
    }
  });

  final dummyCustomerProfile = ProfileModel(
    id: 'user-uuid-1111-2222-3333',
    fullName: 'Customer Uji',
    username: 'customeruji',
    phone: '08123456789',
    avatarUrl: null,
    role: 'customer',
    balance: 50000,
    is2faEnabled: false,
    updatedAt: DateTime.now(),
  );

  group('Widget Lifecycle & Dispose Verification', () {
    testWidgets('LoginScreen disposes cleanly without pending timers or exceptions',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LoginScreen()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Unmount by replacing with SizedBox
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('RegisterScreen disposes cleanly without pending timers or exceptions',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: RegisterScreen()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Unmount by replacing with SizedBox
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'EmailVerificationScreen disposes cleanly without pending timers or exceptions',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmailVerificationScreen(
            email: 'test@digiq.com',
            initialStatus: VerificationStatus.waiting,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Unmount by replacing with SizedBox
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'CustomerDashboardScreen disposes cleanly without pending timers or exceptions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: CustomerDashboardScreen(profile: dummyCustomerProfile)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Unmount by replacing with SizedBox and flush any Realtime disconnect timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'AdminDashboardScreen disposes cleanly without pending timers or exceptions',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AdminDashboardScreen()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Unmount by replacing with SizedBox and flush any Realtime disconnect timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
      expect(tester.takeException(), isNull);
    });
  });
}

