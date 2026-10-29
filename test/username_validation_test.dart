// test/username_validation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:digiq/services/auth_service.dart';

void main() {
  group('Username Format Validation Unit Tests', () {
    test('Valid username (5 karakter alfanumerik)', () {
      expect(AuthService.validateUsernameFormat('user1'), isNull);
    });

    test('Valid username (20 karakter alfanumerik campuran besar/kecil)', () {
      expect(AuthService.validateUsernameFormat('User1234567890abcdef'), isNull);
    });

    test('Ditolak jika kurang dari 5 karakter (4 karakter)', () {
      expect(AuthService.validateUsernameFormat('user'), 'Username minimal 5 karakter.');
    });

    test('Ditolak jika lebih dari 20 karakter (21 karakter)', () {
      expect(AuthService.validateUsernameFormat('user12345678901234567'), 'Username maksimal 20 karakter.');
    });

    test('Ditolak jika mengandung simbol titik atau underscore', () {
      expect(AuthService.validateUsernameFormat('user.name'), contains('Hanya boleh berisi huruf dan angka'));
      expect(AuthService.validateUsernameFormat('user_name'), contains('Hanya boleh berisi huruf dan angka'));
      expect(AuthService.validateUsernameFormat('user@name'), contains('Hanya boleh berisi huruf dan angka'));
    });

    test('Ditolak jika mengandung spasi di tengah atau ujung', () {
      expect(AuthService.validateUsernameFormat('user 123'), contains('Hanya boleh berisi huruf dan angka'));
      expect(AuthService.validateUsernameFormat(' user123 '), isNull); // auto trim di depan/belakang
    });

    test('Normalisasi case-insensitive via AuthService.normalizeUsername', () {
      expect(AuthService.normalizeUsername('  Bayu99  '), equals('bayu99'));
      expect(AuthService.normalizeUsername('DARZKINE'), equals('darzkine'));
    });
  });
}

