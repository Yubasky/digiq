// test/edit_profile_widget_test.dart
//
// Widget tests untuk Profil & Edit Profile:
// 1. Tampilan tombol "Edit Profil" di tab profil (avatar icon, header button, card edit, menu item)
//    dan navigasi ke EditProfileScreen.
// 2. PopScope: form yang diubah (dirty) memicu dialog konfirmasi saat pop/back.
// 3. Username client-side validator menerima username valid dan menolak <5 karakter atau mengandung spasi/simbol.
// 4. Field email di form utama bersifat read-only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:digiq/models/profile_model.dart';
import 'package:digiq/screens/customer_dashboard_screen.dart';
import 'package:digiq/screens/edit_profile_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_token_signature_ok',
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

  group('Customer Profile Tab - Edit Profile Buttons & Navigation', () {
    testWidgets('Semua tombol Edit Profil muncul pada tab Profil', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: CustomerDashboardScreen(profile: dummyProfile),
        ),
      );
      await tester.pump();

      // Beralih ke tab Profil di bottom nav
      final profileTab = find.text('Profil');
      expect(profileTab, findsOneWidget);
      await tester.tap(profileTab);
      await tester.pump();

      // Verifikasi komponen header & avatar
      expect(find.byKey(const Key('profile_avatar_edit_button')), findsOneWidget);
      expect(find.byKey(const Key('profile_header_edit_button')), findsOneWidget);

      // Verifikasi tombol Edit pada kartu Informasi Akun
      expect(find.byKey(const Key('profile_card_edit_button')), findsOneWidget);

      // Verifikasi tombol Edit Profil pada kartu Menu
      expect(find.byKey(const Key('profile_menu_edit_item')), findsOneWidget);

      // Verifikasi username ditampilkan dengan prefix @
      expect(find.text('@satriauji'), findsWidgets);

      // Clean up widget tree and drain pending timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
    });

    testWidgets('Menekan tombol Edit Profil pada kartu Informasi Akun membuka EditProfileScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: CustomerDashboardScreen(profile: dummyProfile),
        ),
      );
      await tester.pump();

      // Pindah ke tab Profil
      final profileTab = find.text('Profil');
      await tester.tap(profileTab);
      await tester.pump();

      // Tap tombol Edit pada kartu header
      final editHeaderBtn = find.byKey(const Key('profile_header_edit_button'));
      expect(editHeaderBtn, findsOneWidget);
      await tester.tap(editHeaderBtn);
      await tester.pumpAndSettle();

      // Verifikasi layar EditProfileScreen terbuka
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.text('Edit Profil'), findsWidgets);

      // Clean up widget tree and drain pending timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
    });
  });

  group('EditProfileScreen Form Validations & PopScope', () {
    testWidgets('Email field bersifat read-only di form utama', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(profile: dummyProfile),
        ),
      );
      await tester.pumpAndSettle();

      // Cari TextField email (label 'Alamat Email')
      final emailFieldFinder = find.byKey(const Key('edit_profile_email_field'));
      expect(emailFieldFinder, findsOneWidget);

      final textField = tester.widget<TextField>(
        find.descendant(of: emailFieldFinder, matching: find.byType(TextField)),
      );
      expect(textField.readOnly, isTrue);

      // Memastikan ada teks 'Terkunci'
      expect(find.text('Terkunci'), findsOneWidget);
    });

    testWidgets('Validasi klien untuk format username (<5 huruf, spasi, simbol)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(profile: dummyProfile),
        ),
      );
      await tester.pumpAndSettle();

      // Cari input username via Key
      final usernameFinder = find.byKey(const Key('edit_profile_username_field'));
      expect(usernameFinder, findsOneWidget);

      final simpanButton = find.byKey(const Key('edit_profile_save_button'));
      expect(simpanButton, findsOneWidget);

      // Test 1: Username kurang dari 5 karakter
      await tester.enterText(usernameFinder, 'abc');
      await tester.pump();
      await tester.tap(simpanButton);
      await tester.pump();

      expect(find.text('Username minimal 5 karakter.'), findsOneWidget);

      // Test 2: Username mengandung spasi
      await tester.enterText(usernameFinder, 'satria uji');
      await tester.pump();
      await tester.tap(simpanButton);
      await tester.pump();

      expect(find.text('Hanya boleh berisi huruf dan angka tanpa spasi/simbol.'), findsOneWidget);

      // Test 3: Username mengandung karakter khusus / simbol
      await tester.enterText(usernameFinder, 'satria_uji!');
      await tester.pump();
      await tester.tap(simpanButton);
      await tester.pump();

      expect(find.text('Hanya boleh berisi huruf dan angka tanpa spasi/simbol.'), findsOneWidget);
    });

    testWidgets('PopScope: form dirty memicu dialog konfirmasi saat tombol kembali ditekan', (tester) async {
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
                      builder: (_) => EditProfileScreen(profile: dummyProfile),
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
      expect(find.text('Anda memiliki perubahan profil yang belum disimpan. Keluar tanpa menyimpan?'), findsOneWidget);

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
    });
  });
}
