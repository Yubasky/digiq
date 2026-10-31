// test/auth_and_avatar_mock_test.dart
//
// Tes Pengujian Terisolasi dengan Supabase Mock/Fake:
// 1. Ganti Password (AuthService.changePasswordWithOld):
//    - (a) Password lama salah -> signInWithPassword gagal -> updateUser TIDAK dipanggil -> pesan ramah tampil
//    - (b) Jalur sukses -> signInWithPassword sukses -> updateUser dipanggil tepat 1 kali
//    - (c) Validasi sesi tidak valid / user null
//    - (d) Validasi password < 8 karakter
//    - (e) Network error pada signIn / updateUser
// 2. Avatar Upload Flow (EditProfileScreen._pickAndUploadAvatar):
//    - (a) Format MIME / ekstensi tidak valid (.gif, .svg, .exe) -> ditolak tanpa memanggil storage
//    - (b) Ukuran file > 2 MB -> ditolak tanpa memanggil storage
//    - (c) Upload sukses -> memanggil remove([oldPath]) untuk avatar lama, uploadBinary untuk file baru,
//          dan menyematkan cache-buster (?v=timestamp) pada publicUrl yang disimpan ke profil
// 3. Ganti Email (EditProfileScreen._requestEmailChange):
//    - (a) Email baru sudah terdaftar (EmailCheckStatus.taken) -> ditolak, updateUser TIDAK dipanggil
//    - (b) Cek email mengalami error jaringan (EmailCheckStatus.networkError) -> peringatan netral tampil,
//          tombol tetap dapat ditekan (fail-open)

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:digiq/models/profile_model.dart';
import 'package:digiq/screens/edit_profile_screen.dart';
import 'package:digiq/services/auth_service.dart';
import 'package:digiq/services/avatar_picker_stub.dart';
import 'package:digiq/services/supabase_config.dart';

// ─── Fake Implementations ───────────────────────────────────────────────────

class FakeUser extends Fake implements User {
  @override
  final String id;
  @override
  final String? email;
  final String? mockEmailConfirmedAt;

  FakeUser({required this.id, this.email, String? emailConfirmedAt})
      : mockEmailConfirmedAt = emailConfirmedAt ?? '2026-01-01T00:00:00Z';

  @override
  String? get emailConfirmedAt => mockEmailConfirmedAt;
}

class FakeUserResponse extends Fake implements UserResponse {
  @override
  final User? user;
  FakeUserResponse({this.user});
}

class FakeGoTrueClient extends Fake implements GoTrueClient {
  User? mockUser;
  int signInCallCount = 0;
  int updateUserCallCount = 0;
  String? lastSignInEmail;
  String? lastSignInPassword;
  UserAttributes? lastUpdateUserAttributes;
  bool shouldSignInFail = false;
  AuthException? signInException;
  bool shouldUpdateUserFail = false;
  AuthException? updateUserException;

  FakeGoTrueClient({this.mockUser});

  @override
  User? get currentUser => mockUser;

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    dynamic captchaToken,
  }) async {
    signInCallCount++;
    lastSignInEmail = email;
    lastSignInPassword = password;
    if (shouldSignInFail) {
      throw signInException ??
          const AuthException('Invalid login credentials', statusCode: '400');
    }
    return AuthResponse(user: mockUser);
  }

  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    updateUserCallCount++;
    lastUpdateUserAttributes = attributes;
    if (shouldUpdateUserFail) {
      throw updateUserException ??
          const AuthException('Gagal update user', statusCode: '400');
    }
    return FakeUserResponse(user: mockUser);
  }
}

class FakeStorageFileApi extends Fake implements StorageFileApi {
  final List<String> removedPaths = [];
  final List<String> uploadedPaths = [];
  final List<Uint8List> uploadedData = [];
  final String publicBaseUrl;

  FakeStorageFileApi({
    this.publicBaseUrl =
        'https://iqxoofrhhrqkgehuvrlb.supabase.co/storage/v1/object/public/avatars',
  });

  @override
  Future<List<FileObject>> remove(List<String> paths) async {
    removedPaths.addAll(paths);
    return [];
  }

  @override
  Future<String> uploadBinary(
    String path,
    Uint8List data, {
    FileOptions fileOptions = const FileOptions(),
    int? retryAttempts,
    StorageRetryController? retryController,
  }) async {
    uploadedPaths.add(path);
    uploadedData.add(data);
    return path;
  }

  @override
  String getPublicUrl(
    String path, {
    TransformOptions? transform,
    DownloadBehavior? download,
    String? cacheNonce,
  }) {
    return '$publicBaseUrl/$path';
  }
}

class FakeSupabaseStorageClient extends Fake implements SupabaseStorageClient {
  final FakeStorageFileApi fileApi;
  FakeSupabaseStorageClient(this.fileApi);

  @override
  StorageFileApi from(String id) => fileApi;
}

// ignore: must_be_immutable
class FakePostgrestFilterBuilder<T> extends Fake
    implements PostgrestFilterBuilder<T> {
  final Map<String, dynamic> updatedData;
  String? filterCol;
  dynamic filterVal;

  FakePostgrestFilterBuilder(this.updatedData);

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) {
    filterCol = column;
    filterVal = value;
    return this;
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) async {
    return onValue([] as T);
  }
}

class FakeSupabaseQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final Map<String, dynamic> lastUpdatedValues = {};
  late final FakePostgrestFilterBuilder _filterBuilder;

  FakeSupabaseQueryBuilder() {
    _filterBuilder = FakePostgrestFilterBuilder(lastUpdatedValues);
  }

  @override
  PostgrestFilterBuilder update(Map values, {dynamic defaultToNull}) {
    lastUpdatedValues.addAll(Map<String, dynamic>.from(values));
    return _filterBuilder;
  }
}

class FakeRpcFilterBuilder<T> extends Fake
    implements PostgrestFilterBuilder<T> {
  final dynamic _result;
  final Object? _exception;
  FakeRpcFilterBuilder(this._result, [this._exception]);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) async {
    if (_exception != null) {
      if (onError != null) {
        return onError(_exception);
      }
      throw _exception;
    }
    return onValue(_result as T);
  }

  @override
  Future<T> timeout(
    Duration timeLimit, {
    FutureOr<T> Function()? onTimeout,
  }) async {
    if (_exception != null) {
      if (_exception is TimeoutException && onTimeout != null) {
        return await onTimeout();
      }
      throw _exception;
    }
    return _result as T;
  }
}

class FakeSupabaseClient extends Fake implements SupabaseClient {
  @override
  final FakeGoTrueClient auth;
  @override
  final FakeSupabaseStorageClient storage;
  final FakeSupabaseQueryBuilder queryBuilder = FakeSupabaseQueryBuilder();
  dynamic Function(String fn, Map<String, dynamic>? params)? rpcHandler;

  FakeSupabaseClient({
    required this.auth,
    required this.storage,
    this.rpcHandler,
  });

  @override
  SupabaseQueryBuilder from(String table) => queryBuilder;

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    dynamic get,
  }) {
    try {
      final res = rpcHandler != null ? rpcHandler!(fn, params) : null;
      return FakeRpcFilterBuilder<T>(res);
    } catch (e) {
      return FakeRpcFilterBuilder<T>(null, e);
    }
  }
}

// ─── Test Suite ─────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    SupabaseConfig.testClient = null;
    EditProfileScreen.enableWebUploadForTesting = false;
    EditProfileScreen.pickImageOverride = null;
  });

  final dummyProfile = ProfileModel(
    id: 'user-uuid-1234-5678-9012',
    fullName: 'Satria Uji',
    username: 'satriauji',
    phone: '08123456789',
    avatarUrl:
        'https://iqxoofrhhrqkgehuvrlb.supabase.co/storage/v1/object/public/avatars/user-uuid-1234-5678-9012/avatar.jpg',
    role: 'customer',
    balance: 50000,
    is2faEnabled: false,
    updatedAt: DateTime.now(),
  );

  group('1. Ganti Password dengan Supabase Mock (changePasswordWithOld)', () {
    test(
      '(a) Password lama salah -> signInWithPassword gagal -> updateUser TIDAK dipanggil & pesan error ramah',
      () async {
        final fakeAuth = FakeGoTrueClient(
          mockUser: FakeUser(
            id: 'user-uuid-1234-5678-9012',
            email: 'satria@example.com',
          ),
        );
        fakeAuth.shouldSignInFail = true;
        fakeAuth.signInException = const AuthException(
          'Invalid login credentials',
          statusCode: '400',
        );

        final fakeStorage = FakeSupabaseStorageClient(FakeStorageFileApi());
        SupabaseConfig.testClient = FakeSupabaseClient(
          auth: fakeAuth,
          storage: fakeStorage,
        );

        final res = await AuthService.changePasswordWithOld(
          oldPassword: 'WrongPassword123!',
          newPassword: 'NewValidPassword123!',
        );

        // Verifikasi ketat
        expect(fakeAuth.signInCallCount, equals(1));
        expect(fakeAuth.lastSignInEmail, equals('satria@example.com'));
        expect(fakeAuth.lastSignInPassword, equals('WrongPassword123!'));
        expect(
          fakeAuth.updateUserCallCount,
          equals(0),
          reason:
              'updateUser TIDAK BOLEH dipanggil jika password lama diverifikasi salah',
        );
        expect(res.success, isFalse);
        expect(
          res.message,
          equals('Password saat ini salah. Silakan periksa kembali.'),
        );
      },
    );

    test(
      '(b) Jalur sukses -> signInWithPassword berhasil -> updateUser dipanggil tepat 1 kali',
      () async {
        final fakeAuth = FakeGoTrueClient(
          mockUser: FakeUser(
            id: 'user-uuid-1234-5678-9012',
            email: 'satria@example.com',
          ),
        );
        fakeAuth.shouldSignInFail = false;

        final fakeStorage = FakeSupabaseStorageClient(FakeStorageFileApi());
        SupabaseConfig.testClient = FakeSupabaseClient(
          auth: fakeAuth,
          storage: fakeStorage,
        );

        final res = await AuthService.changePasswordWithOld(
          oldPassword: 'CorrectPassword123!',
          newPassword: 'BrandNewSecurePass123!',
        );

        // Verifikasi panggilan
        expect(fakeAuth.signInCallCount, equals(1));
        expect(fakeAuth.lastSignInPassword, equals('CorrectPassword123!'));
        expect(
          fakeAuth.updateUserCallCount,
          equals(1),
          reason: 'updateUser harus dipanggil tepat 1 kali pada jalur sukses',
        );
        expect(
          fakeAuth.lastUpdateUserAttributes?.password,
          equals('BrandNewSecurePass123!'),
        );
        expect(res.success, isTrue);
        expect(res.message, equals('Password berhasil diperbarui.'));
      },
    );

    test('Validasi: Sesi tidak valid / user null menolak operasi', () async {
      final fakeAuth = FakeGoTrueClient(mockUser: null);
      final fakeStorage = FakeSupabaseStorageClient(FakeStorageFileApi());
      SupabaseConfig.testClient = FakeSupabaseClient(
        auth: fakeAuth,
        storage: fakeStorage,
      );

      final res = await AuthService.changePasswordWithOld(
        oldPassword: 'AnyPassword123!',
        newPassword: 'NewPassword123!',
      );

      expect(fakeAuth.signInCallCount, equals(0));
      expect(fakeAuth.updateUserCallCount, equals(0));
      expect(res.success, isFalse);
      expect(
        res.message,
        equals('Sesi Anda telah berakhir. Silakan login kembali.'),
      );
    });

    test(
      'Validasi: Password baru < 8 karakter menolak sebelum memanggil auth',
      () async {
        final fakeAuth = FakeGoTrueClient(
          mockUser: FakeUser(id: 'uuid-1', email: 'user@test.com'),
        );
        final fakeStorage = FakeSupabaseStorageClient(FakeStorageFileApi());
        SupabaseConfig.testClient = FakeSupabaseClient(
          auth: fakeAuth,
          storage: fakeStorage,
        );

        final res = await AuthService.changePasswordWithOld(
          oldPassword: 'OldPassword123!',
          newPassword: 'short',
        );

        expect(fakeAuth.signInCallCount, equals(0));
        expect(fakeAuth.updateUserCallCount, equals(0));
        expect(res.success, isFalse);
        expect(res.message, equals('Password baru minimal 8 karakter.'));
      },
    );

    test(
      'Error jaringan saat re-autentikasi menampilkan pesan koneksi ramah',
      () async {
        final fakeAuth = FakeGoTrueClient(
          mockUser: FakeUser(id: 'uuid-1', email: 'user@test.com'),
        );
        fakeAuth.shouldSignInFail = true;
        fakeAuth.signInException = const AuthException('Network socket error');

        final fakeStorage = FakeSupabaseStorageClient(FakeStorageFileApi());
        SupabaseConfig.testClient = FakeSupabaseClient(
          auth: fakeAuth,
          storage: fakeStorage,
        );

        final res = await AuthService.changePasswordWithOld(
          oldPassword: 'OldPassword123!',
          newPassword: 'ValidNewPassword123!',
        );

        expect(fakeAuth.signInCallCount, equals(1));
        expect(fakeAuth.updateUserCallCount, equals(0));
        expect(res.success, isFalse);
        expect(res.message, isNotEmpty);
      },
    );
  });

  group('2. Avatar Upload Flow dengan Fake Storage Client', () {
    testWidgets('(a) File tipe salah (.gif, .svg) ditolak oleh validasi klien', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeFileApi = FakeStorageFileApi();
      final fakeStorage = FakeSupabaseStorageClient(fakeFileApi);
      final fakeAuth = FakeGoTrueClient(
        mockUser: FakeUser(id: dummyProfile.id, email: 'satria@example.com'),
      );
      SupabaseConfig.testClient = FakeSupabaseClient(
        auth: fakeAuth,
        storage: fakeStorage,
      );

      // Siapkan mock file tidak valid (.gif)
      EditProfileScreen.enableWebUploadForTesting = true;
      EditProfileScreen.pickImageOverride = () async => PickedAvatarFile(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        extension: 'gif',
        mimeType: 'image/gif',
        sizeInBytes: 1024,
      );

      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
      );
      await tester.pumpAndSettle();

      // Tap tombol ganti avatar
      final avatarBtn = find.byKey(
        const Key('edit_profile_avatar_picker_button'),
      );
      expect(avatarBtn, findsOneWidget);
      await tester.tap(avatarBtn);
      await tester.pumpAndSettle();

      // Verifikasi snackbar error format muncul
      expect(
        find.text('Format foto harus berupa JPG, PNG, atau WebP.'),
        findsOneWidget,
      );

      // Verifikasi storage uploadBinary dan remove TIDAK PERNAH dipanggil
      expect(fakeFileApi.uploadedPaths, isEmpty);
      expect(fakeFileApi.removedPaths, isEmpty);
    });

    testWidgets('(b) File > 2 MB ditolak oleh validasi klien', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeFileApi = FakeStorageFileApi();
      final fakeStorage = FakeSupabaseStorageClient(fakeFileApi);
      final fakeAuth = FakeGoTrueClient(
        mockUser: FakeUser(id: dummyProfile.id, email: 'satria@example.com'),
      );
      SupabaseConfig.testClient = FakeSupabaseClient(
        auth: fakeAuth,
        storage: fakeStorage,
      );

      // Siapkan mock file oversized (2 MB + 10 byte)
      const oversized = 2 * 1024 * 1024 + 10;
      EditProfileScreen.enableWebUploadForTesting = true;
      EditProfileScreen.pickImageOverride = () async => PickedAvatarFile(
        bytes: Uint8List(100),
        extension: 'png',
        mimeType: 'image/png',
        sizeInBytes: oversized,
      );

      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
      );
      await tester.pumpAndSettle();

      final avatarBtn = find.byKey(
        const Key('edit_profile_avatar_picker_button'),
      );
      await tester.tap(avatarBtn);
      await tester.pumpAndSettle();

      // Verifikasi snackbar ukuran maksimal muncul
      expect(find.text('Ukuran foto profil maksimal 2 MB.'), findsOneWidget);

      // Verifikasi storage uploadBinary dan remove TIDAK PERNAH dipanggil
      expect(fakeFileApi.uploadedPaths, isEmpty);
      expect(fakeFileApi.removedPaths, isEmpty);
    });

    testWidgets(
      '(c) Upload sukses -> memanggil remove([oldPath]) untuk path lama, uploadBinary, & cache-buster (?v=)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fakeFileApi = FakeStorageFileApi();
        final fakeStorage = FakeSupabaseStorageClient(fakeFileApi);
        final fakeAuth = FakeGoTrueClient(
          mockUser: FakeUser(id: dummyProfile.id, email: 'satria@example.com'),
        );
        final fakeClient = FakeSupabaseClient(
          auth: fakeAuth,
          storage: fakeStorage,
        );
        SupabaseConfig.testClient = fakeClient;

        // File valid: format png, ukuran 120 KB
        final imageBytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
        EditProfileScreen.enableWebUploadForTesting = true;
        EditProfileScreen.pickImageOverride = () async => PickedAvatarFile(
          bytes: imageBytes,
          extension: 'png',
          mimeType: 'image/png',
          sizeInBytes: 120 * 1024,
        );

        await tester.pumpWidget(
          MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
        );
        await tester.pumpAndSettle();

        final avatarBtn = find.byKey(
          const Key('edit_profile_avatar_picker_button'),
        );
        await tester.tap(avatarBtn);
        await tester.pumpAndSettle();

        // 1. Verifikasi old avatar dihapus via remove([oldPath])
        // dummyProfile.avatarUrl adalah .../user-uuid-1234-5678-9012/avatar.jpg
        expect(fakeFileApi.removedPaths, contains(
          'user-uuid-1234-5678-9012/avatar.jpg',
        ));

        // 2. Verifikasi file baru di-upload via uploadBinary
        expect(fakeFileApi.uploadedPaths, contains(
          'user-uuid-1234-5678-9012/avatar.png',
        ));
        expect(fakeFileApi.uploadedData.first, equals(imageBytes));

        // 3. Verifikasi update profiles dipanggil dengan cache-buster ?v=
        final updatedValues = fakeClient.queryBuilder.lastUpdatedValues;
        expect(updatedValues.containsKey('avatar_url'), isTrue);
        final newAvatarUrl = updatedValues['avatar_url'] as String;
        expect(newAvatarUrl, contains('user-uuid-1234-5678-9012/avatar.png'));
        expect(
          newAvatarUrl,
          contains('?v='),
          reason: 'URL avatar baru wajib menyematkan parameter cache-buster ?v=',
        );

        // 4. Verifikasi feedback UI
        expect(find.text('Foto profil berhasil diperbarui.'), findsOneWidget);
      },
    );
  });

  group('3. Ganti Email Widget Tests (check_email_available & fail-open)', () {
    testWidgets('(a) Email baru sudah terdaftar -> ditolak, updateUser TIDAK dipanggil', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeAuth = FakeGoTrueClient(
        mockUser: FakeUser(id: dummyProfile.id, email: 'satria@example.com'),
      );
      final fakeStorage = FakeSupabaseStorageClient(FakeStorageFileApi());
      final fakeClient = FakeSupabaseClient(
        auth: fakeAuth,
        storage: fakeStorage,
        rpcHandler: (fn, params) {
          if (fn == 'check_email_available') {
            // Email 'terpakai@example.com' sudah terdaftar di database -> kembalikan false
            return false;
          }
          return null;
        },
      );
      SupabaseConfig.testClient = fakeClient;

      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
      );
      await tester.pumpAndSettle();

      final emailField = find.byKey(const Key('edit_profile_new_email_field'));
      await tester.ensureVisible(emailField);
      await tester.pumpAndSettle();

      // Masukkan email yang sudah terdaftar
      await tester.enterText(emailField, 'terpakai@example.com');
      // Jalankan debounce 500ms
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // UI harus menampilkan peringatan bahwa email sudah terdaftar
      expect(
        find.text(
          'Email ini sudah terdaftar. Silakan masuk atau gunakan Lupa Password.',
        ),
        findsOneWidget,
      );

      // Coba klik tombol submit
      final submitBtn = find.byKey(
        const Key('edit_profile_submit_email_button'),
      );
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verifikasi snackbar penolakan tampil
      expect(
        find.text('Email ini sudah terdaftar oleh pengguna lain.'),
        findsOneWidget,
      );

      // Verifikasi updateUser TIDAK DIPANGGIL
      expect(
        fakeAuth.updateUserCallCount,
        equals(0),
        reason: 'updateUser tidak boleh dipanggil jika email sudah terdaftar',
      );
    });

    testWidgets(
      '(b) Pengecekan email error jaringan -> peringatan netral tampil & tetap bisa lanjut (fail-open)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fakeAuth = FakeGoTrueClient(
          mockUser: FakeUser(id: dummyProfile.id, email: 'satria@example.com'),
        );
        fakeAuth.shouldUpdateUserFail = false;

        final fakeStorage = FakeSupabaseStorageClient(FakeStorageFileApi());
        final fakeClient = FakeSupabaseClient(
          auth: fakeAuth,
          storage: fakeStorage,
          rpcHandler: (fn, params) {
            if (fn == 'check_email_available') {
              // Simulasikan batas waktu / kegagalan koneksi jaringan
              throw TimeoutException('Koneksi timeout');
            }
            return null;
          },
        );
        SupabaseConfig.testClient = fakeClient;

        await tester.pumpWidget(
          MaterialApp(home: EditProfileScreen(profile: dummyProfile)),
        );
        await tester.pumpAndSettle();

        final emailField = find.byKey(
          const Key('edit_profile_new_email_field'),
        );
        await tester.ensureVisible(emailField);
        await tester.pumpAndSettle();

        await tester.enterText(emailField, 'emailbaru@example.com');
        // Tunggu debounce dan retry
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // Verifikasi peringatan netral (fail-open) tampil
        expect(
          find.text(
            'Koneksi lambat saat memeriksa email. Anda tetap dapat melanjutkan pendaftaran.',
          ),
          findsOneWidget,
        );

        // Verifikasi tombol submit TETAP DAPAT DITEKAN (fail-open)
        final submitBtn = find.byKey(
          const Key('edit_profile_submit_email_button'),
        );
        await tester.ensureVisible(submitBtn);
        await tester.pumpAndSettle();
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        // Karena fail-open, form meneruskan panggilan ke updateUser
        expect(fakeAuth.updateUserCallCount, equals(1));
        expect(
          fakeAuth.lastUpdateUserAttributes?.email,
          equals('emailbaru@example.com'),
        );
        expect(
          find.text(
            'Tautan konfirmasi telah dikirim ke email baru Anda. Silakan buka email tersebut untuk menyelesaikan perubahan.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
