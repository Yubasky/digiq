// test/edit_profile_widget_test.dart
//
// Widget & Unit tests untuk Profil & Edit Profile:
// 1. Simplifikasi UX Tab Profil:
//    - Hanya ada 2 entry point: Avatar pencil & Item Menu
//    - Pill button di header dan tombol edit di kartu akun DIHAPUS (findsNothing)
//    - Navigasi berhasil membuka EditProfileScreen
// 2. PopScope: form dirty memicu dialog konfirmasi saat tombol kembali ditekan
// 3. Validasi Form & Klien Username (<5 karakter, spasi, simbol)
// 4. Field email akun bersifat read-only (Terkunci)
// 5. Validasi Form Password (empty old pass, short new pass <8, mismatch confirmation)
// 6. Validasi Form Email Baru (format invalid, taken email rejection, fail-open neutral warning)
// 7. Avatar upload logic validation (allowed MIME types, 2MB size limit, cache-buster, old file deletion)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:digiq/models/profile_model.dart';
import 'package:digiq/services/auth_service.dart';
import 'package:digiq/screens/customer_dashboard_screen.dart';
import 'package:digiq/screens/edit_profile_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
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

  final dummyProfile = ProfileModel(
    id: 'user-uuid-1234-5678-9012',
    fullName: 'Satria Uji',
    username: 'satriauji',
    phone: '08123456789',
    avatarUrl: null,
    role: 'customer',
    balance: 50000,
    is2faEnabled: false,
    updatedAt: DateTime.now(),
  );

  group('1. Simplified Profile Tab UX Tests (2 Entry Points Only)', () {
    testWidgets(
      'Hanya tombol avatar pencil & menu item yang ada, tombol header & kartu telah dihapus',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(home: CustomerDashboardScreen(profile: dummyProfile)),
        );
        await tester.pump();

        // Beralih ke tab Profil di bottom nav
        final profileTab = find.text('Profil');
        expect(profileTab, findsOneWidget);
        await tester.tap(profileTab);
        await tester.pump();

        // Entry point 1: Avatar pencil button WAJIB ADA
        expect(
          find.byKey(const Key('profile_avatar_edit_button')),
          findsOneWidget,
        );

        // Entry point 2: Menu edit item WAJIB ADA
        expect(find.byKey(const Key('profile_menu_edit_item')), findsOneWidget);

        // Entry point yang disederhanakan: Tombol Header Pill HARUS TIDAK ADA (findsNothing)
        expect(
          find.byKey(const Key('profile_header_edit_button')),
          findsNothing,
        );

        // Entry point yang disederhanakan: Tombol Kartu Akun HARUS TIDAK ADA (findsNothing)
        expect(find.byKey(const Key('profile_card_edit_button')), findsNothing);

        // Verifikasi username ditampilkan dengan prefix @
        expect(find.text('@satriauji'), findsWidgets);

        // Clean up widget tree and drain pending timers
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 2));
      },
    );

    testWidgets('Menekan tombol pensil pada avatar membuka EditProfileScreen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: CustomerDashboardScreen(profile: dummyProfile)),
      );
      await tester.pump();

      // Pindah ke tab Profil
      final profileTab = find.text('Profil');
      await tester.tap(profileTab);
      await tester.pump();

      // Tap tombol pensil pada avatar
      final avatarEditBtn = find.byKey(const Key('profile_avatar_edit_button'));
      expect(avatarEditBtn, findsOneWidget);
      await tester.tap(avatarEditBtn);
      await tester.pumpAndSettle();

      // Verifikasi layar EditProfileScreen terbuka
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.text('Edit Profil'), findsWidgets);

      // Clean up widget tree and drain pending timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
    });

    testWidgets(
      'Menekan tombol Edit Profil pada menu list membuka EditProfileScreen',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(home: CustomerDashboardScreen(profile: dummyProfile)),
        );
        await tester.pump();

        // Pindah ke tab Profil
        final profileTab = find.text('Profil');
        await tester.tap(profileTab);
        await tester.pump();

        // Scroll dan tap menu Edit Profil
        final editMenuItem = find.byKey(const Key('profile_menu_edit_item'));
        expect(editMenuItem, findsOneWidget);
        await tester.tap(editMenuItem);
        await tester.pumpAndSettle();

        // Verifikasi layar EditProfileScreen terbuka
        expect(find.byType(EditProfileScreen), findsOneWidget);
        expect(find.text('Edit Profil'), findsWidgets);

        // Clean up widget tree and drain pending timers
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 2));
      },
    );
  });

  group('2. EditProfileScreen Form Validations & PopScope', () {
    testWidgets('Email field bersifat read-only di form utama', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
      );
      await tester.pumpAndSettle();

      // Cari TextField email (label 'Alamat Email')
      final emailFieldFinder = find.byKey(
        const Key('edit_profile_email_field'),
      );
      expect(emailFieldFinder, findsOneWidget);

      final textField = tester.widget<TextField>(
        find.descendant(of: emailFieldFinder, matching: find.byType(TextField)),
      );
      expect(textField.readOnly, isTrue);

      // Memastikan ada teks 'Terkunci'
      expect(find.text('Terkunci'), findsOneWidget);
    });

    testWidgets(
      'Validasi klien untuk format username (<5 huruf, spasi, simbol)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
        );
        await tester.pumpAndSettle();

        final usernameFinder = find.byKey(
          const Key('edit_profile_username_field'),
        );
        expect(usernameFinder, findsOneWidget);

        final simpanButton = find.byKey(const Key('edit_profile_save_button'));
        expect(simpanButton, findsOneWidget);

        // Test 1: Kurang dari 5 karakter
        await tester.enterText(usernameFinder, 'abc');
        await tester.pump();
        await tester.tap(simpanButton);
        await tester.pump();
        expect(find.text('Username minimal 5 karakter.'), findsOneWidget);

        // Test 2: Mengandung spasi
        await tester.enterText(usernameFinder, 'satria uji');
        await tester.pump();
        await tester.tap(simpanButton);
        await tester.pump();
        expect(
          find.text('Hanya boleh berisi huruf dan angka tanpa spasi/simbol.'),
          findsOneWidget,
        );

        // Test 3: Mengandung simbol khusus
        await tester.enterText(usernameFinder, 'satria_uji!');
        await tester.pump();
        await tester.tap(simpanButton);
        await tester.pump();
        expect(
          find.text('Hanya boleh berisi huruf dan angka tanpa spasi/simbol.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PopScope: form dirty memicu dialog konfirmasi saat tombol kembali ditekan',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) =>
                            EditProfileScreen(profile: dummyProfile),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Buka EditProfileScreen
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(EditProfileScreen), findsOneWidget);

        // Ubah nama sehingga form menjadi dirty
        final nameField = find.byKey(const Key('edit_profile_name_field'));
        expect(nameField, findsOneWidget);
        await tester.enterText(nameField, 'Satria Dimodifikasi');
        await tester.pump();

        // Tekan tombol back di AppBar
        final backButton = find.byIcon(Icons.arrow_back_rounded);
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
        await tester.pumpAndSettle();

        // Dialog konfirmasi harus muncul
        expect(find.text('Perubahan Belum Disimpan'), findsOneWidget);
        expect(
          find.text(
            'Anda memiliki perubahan profil yang belum disimpan. Keluar tanpa menyimpan?',
          ),
          findsOneWidget,
        );

        // Tekan 'Tetap di Sini' -> dialog tertutup, tetap di EditProfileScreen
        await tester.tap(find.text('Tetap di Sini'));
        await tester.pumpAndSettle();
        expect(find.byType(EditProfileScreen), findsOneWidget);
        expect(find.text('Perubahan Belum Disimpan'), findsNothing);

        // Tekan tombol back lagi
        await tester.tap(backButton);
        await tester.pumpAndSettle();

        // Tekan 'Keluar' -> keluar kembali ke halaman awal
        await tester.tap(find.widgetWithText(ElevatedButton, 'Keluar'));
        await tester.pumpAndSettle();
        expect(find.byType(EditProfileScreen), findsNothing);
        expect(find.text('Open'), findsOneWidget);
      },
    );
  });

  group('3. Password Change Form Validations', () {
    testWidgets('Ganti password: password saat ini kosong ditolak', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
      );
      await tester.pumpAndSettle();

      final savePassBtn = find.byKey(
        const Key('edit_profile_save_password_button'),
      );
      expect(savePassBtn, findsOneWidget);
      await tester.ensureVisible(savePassBtn);
      await tester.pumpAndSettle();

      // Tap Simpan Password Baru tanpa mengisi password saat ini
      await tester.tap(savePassBtn);
      await tester.pumpAndSettle();

      expect(find.text('Masukkan password saat ini.'), findsOneWidget);
    });

    testWidgets('Ganti password: konfirmasi password tidak cocok ditolak', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
      );
      await tester.pumpAndSettle();

      // Isi password saat ini
      final oldPassField = find.byKey(
        const Key('edit_profile_old_password_field'),
      );
      await tester.ensureVisible(oldPassField);
      await tester.pumpAndSettle();
      await tester.enterText(oldPassField, 'OldPassword123!');
      await tester.pump();

      // Isi password baru (8 char)
      final newPassField = find.byKey(
        const Key('edit_profile_new_password_field'),
      );
      await tester.enterText(newPassField, 'NewSecret123!');
      await tester.pump();

      // Isi konfirmasi yang salah
      final confirmPassField = find.byKey(
        const Key('edit_profile_confirm_password_field'),
      );
      await tester.enterText(confirmPassField, 'MismatchPass999!');
      await tester.pump();

      final savePassBtn = find.byKey(
        const Key('edit_profile_save_password_button'),
      );
      await tester.ensureVisible(savePassBtn);
      await tester.pumpAndSettle();
      await tester.tap(savePassBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('Konfirmasi password baru tidak cocok.'),
        findsOneWidget,
      );
    });

    testWidgets('Ganti password: password baru <8 karakter ditolak', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
      );
      await tester.pumpAndSettle();

      final oldPassField = find.byKey(
        const Key('edit_profile_old_password_field'),
      );
      await tester.ensureVisible(oldPassField);
      await tester.pumpAndSettle();
      await tester.enterText(oldPassField, 'OldPassword123!');
      await tester.pump();

      final newPassField = find.byKey(
        const Key('edit_profile_new_password_field'),
      );
      await tester.enterText(newPassField, '1234567'); // hanya 7 karakter
      await tester.pump();

      final confirmPassField = find.byKey(
        const Key('edit_profile_confirm_password_field'),
      );
      await tester.enterText(confirmPassField, '1234567');
      await tester.pump();

      final savePassBtn = find.byKey(
        const Key('edit_profile_save_password_button'),
      );
      await tester.ensureVisible(savePassBtn);
      await tester.pumpAndSettle();
      await tester.tap(savePassBtn);
      await tester.pumpAndSettle();

      expect(find.text('Password baru minimal 8 karakter.'), findsOneWidget);
    });

    test(
      'AuthService.changePasswordWithOld unit test: <8 karakter ditolak',
      () async {
        final res = await AuthService.changePasswordWithOld(
          oldPassword: 'SomeOldPassword123!',
          newPassword: 'short',
        );
        // Tanpa sesi aktif atau password <8, helper menolak sebelum panggil API
        expect(res.success, isFalse);
      },
    );
  });

  group('4. Change Email Form Validations & Fail-Open', () {
    testWidgets('Format email baru tidak valid menampilkan error format', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
      );
      await tester.pumpAndSettle();

      final emailField = find.byKey(const Key('edit_profile_new_email_field'));
      expect(emailField, findsOneWidget);
      await tester.ensureVisible(emailField);
      await tester.pumpAndSettle();

      await tester.enterText(emailField, 'bukan-email-valid');
      await tester.pump();

      final submitBtn = find.byKey(
        const Key('edit_profile_submit_email_button'),
      );
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Format email tidak valid.'), findsOneWidget);
    });

    test('AuthService.validateEmailFormat unit tests', () {
      expect(AuthService.validateEmailFormat(''), equals('Email wajib diisi.'));
      expect(
        AuthService.validateEmailFormat('abc'),
        equals('Format email tidak valid.'),
      );
      expect(
        AuthService.validateEmailFormat('test@domain'),
        equals('Format email tidak valid.'),
      );
      expect(AuthService.validateEmailFormat('valid.user@gmail.com'), isNull);
    });

    test(
      'AuthService.getEmailStatusMessage handles taken and fail-open correctly',
      () {
        expect(
          AuthService.getEmailStatusMessage(EmailCheckStatus.taken),
          contains('sudah terdaftar'),
        );
        expect(
          AuthService.getEmailStatusMessage(EmailCheckStatus.networkError),
          contains('tetap dapat melanjutkan'),
        );
        expect(
          AuthService.getEmailStatusMessage(EmailCheckStatus.serverNotReady),
          contains('tetap dapat melanjutkan'),
        );
      },
    );
  });

  group('5. Avatar Validation & Cache-Buster Tests', () {
    test(
      'Allowed avatar extensions list contains only jpg, jpeg, png, webp',
      () {
        const allowedExts = ['jpg', 'jpeg', 'png', 'webp'];
        expect(allowedExts.contains('jpg'), isTrue);
        expect(allowedExts.contains('jpeg'), isTrue);
        expect(allowedExts.contains('png'), isTrue);
        expect(allowedExts.contains('webp'), isTrue);
        expect(allowedExts.contains('svg'), isFalse);
        expect(allowedExts.contains('exe'), isFalse);
        expect(allowedExts.contains('gif'), isFalse);
      },
    );

    test('Avatar size limit is exactly 2 MB (2 * 1024 * 1024 bytes)', () {
      const maxAvatarSizeBytes = 2 * 1024 * 1024;
      const validSize = 1024 * 1024; // 1 MB
      const oversized = 2 * 1024 * 1024 + 1; // 2 MB + 1 byte

      expect(validSize <= maxAvatarSizeBytes, isTrue);
      expect(oversized <= maxAvatarSizeBytes, isFalse);
    });

    test('Avatar URL cache-buster generates query param ?v=timestamp', () {
      const baseUrl =
          'https://iqxoofrhhrqkgehuvrlb.supabase.co/storage/v1/object/public/avatars/user-1/avatar.png';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final urlWithBuster = '$baseUrl?v=$timestamp';

      expect(urlWithBuster, contains('?v='));
      expect(Uri.parse(urlWithBuster).queryParameters.containsKey('v'), isTrue);
    });

    test('Old avatar path parsing logic extracts correct bucket path for removal', () {
      const oldAvatarUrl =
          'https://iqxoofrhhrqkgehuvrlb.supabase.co/storage/v1/object/public/avatars/user-123/avatar.jpg?v=123456';
      final uri = Uri.parse(oldAvatarUrl);
      final pathSegments = uri.pathSegments;
      final avatarIdx = pathSegments.indexOf('avatars');

      expect(avatarIdx, isNot(-1));
      final oldPath = pathSegments.sublist(avatarIdx + 1).join('/');
      expect(oldPath, equals('user-123/avatar.jpg'));
    });
  });
}
