// test/profile_and_email_test.dart
//
// Unit tests untuk validasi profil, klasifikasi error email,
// ProfileModel, dan penanganan autentikasi 007.

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:digiq/services/auth_service.dart';
import 'package:digiq/models/profile_model.dart';

void main() {
  group('1. Email Format Validation Tests', () {
    test('Format email valid diterima', () {
      expect(AuthService.validateEmailFormat('user@example.com'), isNull);
      expect(AuthService.validateEmailFormat('user.name+tag@sub.domain.co.id'), isNull);
      expect(AuthService.validateEmailFormat('  test123_45@gmail.com  '), isNull);
    });

    test('Email kosong ditolak', () {
      expect(AuthService.validateEmailFormat(''), 'Email wajib diisi.');
      expect(AuthService.validateEmailFormat('   '), 'Email wajib diisi.');
      expect(AuthService.validateEmailFormat(null), 'Email wajib diisi.');
    });

    test('Email format cacat ditolak', () {
      expect(AuthService.validateEmailFormat('user'), 'Format email tidak valid.');
      expect(AuthService.validateEmailFormat('user@'), 'Format email tidak valid.');
      expect(AuthService.validateEmailFormat('user@domain'), 'Format email tidak valid.');
      expect(AuthService.validateEmailFormat('user@domain.'), 'Format email tidak valid.');
      expect(AuthService.validateEmailFormat('@domain.com'), 'Format email tidak valid.');
      expect(AuthService.validateEmailFormat('user space@domain.com'), 'Format email tidak valid.');
    });

    test('Email lebih dari 254 karakter ditolak', () {
      final longEmail = '${'a' * 245}@gmail.com';
      expect(AuthService.validateEmailFormat(longEmail), 'Email terlalu panjang.');
    });
  });

  group('2. Profile Fields Validation Tests', () {
    test('Validasi Nama Lengkap: 2-60 karakter', () {
      expect(AuthService.validateFullNameFormat('Budi Santoso'), isNull);
      expect(AuthService.validateFullNameFormat('Jo'), isNull); // 2 karakter
      expect(AuthService.validateFullNameFormat('A' * 60), isNull); // 60 karakter
      expect(AuthService.validateFullNameFormat('A'), 'Nama minimal 2 karakter.');
      expect(AuthService.validateFullNameFormat('A' * 61), 'Nama maksimal 60 karakter.');
      expect(AuthService.validateFullNameFormat(''), 'Nama lengkap wajib diisi.');
    });

    test('Validasi Nomor HP: Format Indonesia (08xx, +62xx, 62xx)', () {
      expect(AuthService.validatePhoneFormat('08123456789'), isNull);
      expect(AuthService.validatePhoneFormat('+6281234567890'), isNull);
      expect(AuthService.validatePhoneFormat('628571234567'), isNull);
      expect(AuthService.validatePhoneFormat('021123456'), contains('Format nomor HP tidak valid'));
      expect(AuthService.validatePhoneFormat('123456789'), contains('Format nomor HP tidak valid'));
      expect(AuthService.validatePhoneFormat('08123'), contains('Format nomor HP tidak valid')); // < 9 digit
      expect(AuthService.validatePhoneFormat('081234567890123456'), contains('Format nomor HP tidak valid')); // > 15 digit
      expect(AuthService.validatePhoneFormat(''), 'Nomor HP wajib diisi.');
    });
  });

  group('3. Email Error Classification Tests', () {
    test('TimeoutException diklasifikasikan sebagai networkError', () {
      final timeoutErr = TimeoutException('Upstream timeout');
      expect(AuthService.classifyEmailCheckError(timeoutErr), EmailCheckStatus.networkError);
    });

    test('PGRST202 atau schema cache diklasifikasikan sebagai serverNotReady', () {
      const pgrstErr = PostgrestException(message: 'Could not find the function check_email_available', code: 'PGRST202');
      expect(AuthService.classifyEmailCheckError(pgrstErr), EmailCheckStatus.serverNotReady);

      const cacheErr = PostgrestException(message: 'Schema cache reload required', code: 'PGRST000');
      expect(AuthService.classifyEmailCheckError(cacheErr), EmailCheckStatus.serverNotReady);
    });

    test('401, 403, 42501 atau permission denied diklasifikasikan sebagai permissionDenied', () {
      const permErr = PostgrestException(message: 'permission denied for function', code: '42501');
      expect(AuthService.classifyEmailCheckError(permErr), EmailCheckStatus.permissionDenied);

      const authErr = PostgrestException(message: 'Unauthorized access', code: '401');
      expect(AuthService.classifyEmailCheckError(authErr), EmailCheckStatus.permissionDenied);
    });

    test('Network / Socket / Connection errors diklasifikasikan sebagai networkError', () {
      final socketErr = Exception('SocketException: OS Error: connection refused');
      expect(AuthService.classifyEmailCheckError(socketErr), EmailCheckStatus.networkError);

      final clientErr = Exception('ClientException with XMLHttpRequest error');
      expect(AuthService.classifyEmailCheckError(clientErr), EmailCheckStatus.networkError);
    });

    test('Error tak dikenal diklasifikasikan sebagai unknownError (bukan serverNotReady)', () {
      final weirdErr = Exception('Unexpected internal format parser error');
      expect(AuthService.classifyEmailCheckError(weirdErr), EmailCheckStatus.unknownError);
    });
  });

  group('4. Email Status Messages Tests', () {
    test('Status available tidak menampilkan pesan error', () {
      expect(AuthService.getEmailStatusMessage(EmailCheckStatus.available), isNull);
    });

    test('Status taken menampilkan pesan ramah tanpa bocorkan info sensitif', () {
      final msg = AuthService.getEmailStatusMessage(EmailCheckStatus.taken);
      expect(msg, 'Email ini sudah terdaftar. Silakan masuk atau gunakan Lupa Password.');
    });

    test('Status error server/jaringan bersifat netral dan fail-open', () {
      final netMsg = AuthService.getEmailStatusMessage(EmailCheckStatus.networkError);
      expect(netMsg, contains('Anda tetap dapat melanjutkan pendaftaran'));

      final srvMsg = AuthService.getEmailStatusMessage(EmailCheckStatus.serverNotReady);
      expect(srvMsg, contains('Anda tetap dapat melanjutkan pendaftaran'));
    });
  });

  group('5. ProfileModel copyWith, displayName & usernameChangedAt Tests', () {
    test('displayName fallback berurutan: nama depan -> username -> User', () {
      final p1 = ProfileModel(
        id: '123',
        fullName: 'Ahmad Dahlan',
        username: 'dahlan99',
        phone: '08123456789',
        role: 'customer',
        balance: 10000,
        is2faEnabled: false,
        updatedAt: DateTime.now(),
      );
      expect(p1.displayName, 'Ahmad');

      final p2 = p1.copyWith(fullName: '   ');
      expect(p2.displayName, 'dahlan99');

      final p3 = p2.copyWith(username: '   ');
      expect(p3.displayName, 'User');
    });

    test('copyWith memperbarui semua field termasuk usernameChangedAt', () {
      final now = DateTime.now();
      final p = ProfileModel(
        id: '123',
        fullName: 'Nama Asli',
        username: 'userlama',
        phone: '08123',
        role: 'customer',
        balance: 0,
        is2faEnabled: false,
        updatedAt: now,
      );

      final changedTime = now.subtract(const Duration(days: 10));
      final updated = p.copyWith(
        fullName: 'Nama Baru',
        username: 'userbaru',
        phone: '08999',
        balance: 50000,
        is2faEnabled: true,
        usernameChangedAt: changedTime,
      );

      expect(updated.fullName, 'Nama Baru');
      expect(updated.username, 'userbaru');
      expect(updated.phone, '08999');
      expect(updated.balance, 50000);
      expect(updated.is2faEnabled, isTrue);
      expect(updated.usernameChangedAt, equals(changedTime));
    });

    test('ProfileModel.fromMap membaca username_changed_at dengan tepat', () {
      final map = {
        'id': 'abc-123',
        'full_name': 'Tester',
        'username': 'tester01',
        'phone': '0811111111',
        'role': 'customer',
        'balance': 25000,
        'is_2fa_enabled': true,
        'updated_at': '2026-10-29T10:00:00Z',
        'username_changed_at': '2026-10-20T12:00:00Z',
      };

      final p = ProfileModel.fromMap(map);
      expect(p.username, 'tester01');
      expect(p.usernameChangedAt, isNotNull);
      expect(p.usernameChangedAt!.year, 2026);
      expect(p.usernameChangedAt!.month, 10);
      expect(p.usernameChangedAt!.day, 20);
    });
  });

  group('6. Error Translation Mapping Tests', () {
    test('Translasi error duplikat username pada submit registrasi', () {
      expect(
        AuthService.translateAuthError('Database error saving new user: duplicate key value violates unique constraint "idx_profiles_username_lower"'),
        'Username ini telah digunakan. Silakan pilih username lain.',
      );
    });

    test('Translasi error kegagalan SMTP server/Brevo', () {
      expect(
        AuthService.translateAuthError('Error sending confirmation email: 525 5.7.1 Unauthorized IP address'),
        contains('Layanan email sedang sibuk'),
      );
    });
  });
}

