// test/audit_hardening_test.dart
// Pengujian unit terverifikasi langsung memanggil fungsi implementasi nyata pada lib/.
// Tidak ada fungsi buatan/mock sintetis di dalam file tes ini.

import 'package:flutter_test/flutter_test.dart';
import 'package:digiq/models/profile_model.dart';
import 'package:digiq/services/auth_service.dart';
import 'package:digiq/services/qris_service.dart';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 1: ProfileModel.displayName Fallback
  // Memanggil fungsi implementasi: lib/models/profile_model.dart:29 (get displayName)
  // ───────────────────────────────────────────────────────────────────────────
  group('1. ProfileModel.displayName (Target: lib/models/profile_model.dart:29)', () {
    test('Mengambil nama depan saat full_name tersedia', () {
      final p = ProfileModel(
        id: 'user-1',
        fullName: 'Satria Darzkine',
        username: 'satriad',
        phone: '08123456789',
        role: 'customer',
        balance: 10000,
        is2faEnabled: false,
        updatedAt: DateTime.now(),
      );
      // Memanggil getter: lib/models/profile_model.dart:29
      expect(p.displayName, equals('Satria'));
    });

    test('Fallback ke username saat full_name kosong', () {
      final p = ProfileModel(
        id: 'user-2',
        fullName: '',
        username: 'digiq_user',
        phone: '08123456789',
        role: 'customer',
        balance: 0,
        is2faEnabled: false,
        updatedAt: DateTime.now(),
      );
      // Memanggil getter: lib/models/profile_model.dart:29
      expect(p.displayName, equals('digiq_user'));
    });

    test('Fallback ke username saat full_name hanya berisi spasi whitespace', () {
      final p = ProfileModel(
        id: 'user-3',
        fullName: '   ',
        username: 'myuser',
        phone: '08123456789',
        role: 'customer',
        balance: 0,
        is2faEnabled: false,
        updatedAt: DateTime.now(),
      );
      // Memanggil getter: lib/models/profile_model.dart:29
      expect(p.displayName, equals('myuser'));
    });

    test('Fallback ke "User" saat full_name dan username kosong', () {
      final p = ProfileModel(
        id: 'user-4',
        fullName: '',
        username: '',
        phone: '08123456789',
        role: 'customer',
        balance: 0,
        is2faEnabled: false,
        updatedAt: DateTime.now(),
      );
      // Memanggil getter: lib/models/profile_model.dart:29
      expect(p.displayName, equals('User'));
    });

    test('Fallback ke "User" saat full_name dan username hanya spasi', () {
      final p = ProfileModel(
        id: 'user-5',
        fullName: '   ',
        username: '  ',
        phone: '08123456789',
        role: 'customer',
        balance: 0,
        is2faEnabled: false,
        updatedAt: DateTime.now(),
      );
      // Memanggil getter: lib/models/profile_model.dart:29
      expect(p.displayName, equals('User'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 2: AuthService.translateAuthError Mapping
  // Memanggil fungsi implementasi: lib/services/auth_service.dart:479 (translateAuthError)
  // ───────────────────────────────────────────────────────────────────────────
  group('2. AuthService.translateAuthError (Target: lib/services/auth_service.dart:479)', () {
    test('Mapping "Database error saving new user" ke pesan ramah pengguna', () {
      const err = 'Database error saving new user';
      // Memanggil: lib/services/auth_service.dart:479
      final msg = AuthService.translateAuthError(err);
      expect(msg, contains('Gagal menyimpan profil pengguna baru'));
    });

    test('Mapping upstream timeout dan gateway timeout', () {
      // Memanggil: lib/services/auth_service.dart:479
      expect(
        AuthService.translateAuthError('upstream request timeout'),
        contains('Layanan autentikasi sedang mengalami batas waktu (timeout)'),
      );
      expect(
        AuthService.translateAuthError('504 Gateway Timeout from Kong'),
        contains('Layanan autentikasi sedang mengalami batas waktu (timeout)'),
      );
    });

    test('Mapping rate limit pengiriman email', () {
      // Memanggil: lib/services/auth_service.dart:479
      final msg = AuthService.translateAuthError('over_email_send_rate_limit');
      expect(msg, contains('Terlalu banyak permintaan pengiriman email'));
    });

    test('Mapping kredensial login salah', () {
      // Memanggil: lib/services/auth_service.dart:479
      final msg = AuthService.translateAuthError('Invalid login credentials');
      expect(msg, equals('Email atau password salah.'));
    });

    test('Mapping email belum terverifikasi', () {
      // Memanggil: lib/services/auth_service.dart:479
      final msg = AuthService.translateAuthError('Email not confirmed');
      expect(msg, contains('Email belum diverifikasi'));
    });

    test('Mapping email sudah terdaftar', () {
      // Memanggil: lib/services/auth_service.dart:479
      final msg = AuthService.translateAuthError('User already registered');
      expect(msg, contains('Email sudah terdaftar'));
    });

    test('Mapping password lemah / kurang karakter', () {
      // Memanggil: lib/services/auth_service.dart:479
      final msg = AuthService.translateAuthError('Password should be at least 8 characters');
      expect(msg, contains('Password terlalu lemah'));
    });

    test('Pesan error yang tidak dikenal tetap dipertahankan aslinya', () {
      const customErr = 'Error server custom 998';
      // Memanggil: lib/services/auth_service.dart:479
      expect(AuthService.translateAuthError(customErr), equals(customErr));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 3: QrisService Edge Cases & Validation
  // Memanggil fungsi implementasi:
  // - lib/services/qris_service.dart:165 (buildDynamicQris)
  // - lib/services/qris_service.dart:108 (verifyCrc16)
  // - lib/services/qris_service.dart:124 (extractMerchantInfo)
  // ───────────────────────────────────────────────────────────────────────────
  group('3. QrisService (Target: lib/services/qris_service.dart:108, 124, 165)', () {
    test('buildDynamicQris dengan nominal 0 ditolak melempar ArgumentError', () {
      // Memanggil: lib/services/qris_service.dart:165
      expect(
        () => QrisService.buildDynamicQris(kDefaultStaticQrisPayload, 0),
        throwsArgumentError,
      );
    });

    test('buildDynamicQris dengan nominal negatif (-500) ditolak melempar ArgumentError', () {
      // Memanggil: lib/services/qris_service.dart:165
      expect(
        () => QrisService.buildDynamicQris(kDefaultStaticQrisPayload, -500),
        throwsArgumentError,
      );
    });

    test('buildDynamicPayload dengan nominal <= 0 mengembalikan null', () {
      // Memanggil: lib/services/qris_service.dart:211
      expect(
        QrisService.buildDynamicPayload(staticPayload: kDefaultStaticQrisPayload, totalAmount: 0),
        isNull,
      );
      expect(
        QrisService.buildDynamicPayload(staticPayload: kDefaultStaticQrisPayload, totalAmount: -100),
        isNull,
      );
    });

    test('buildDynamicQris dengan nominal besar (999.999.999) menghasilkan tag 540999999999 dan CRC valid', () {
      // Memanggil: lib/services/qris_service.dart:165 & 108
      final qris = QrisService.buildDynamicQris(kDefaultStaticQrisPayload, 999999999);
      expect(qris.contains('540999999999'), isTrue);
      expect(QrisService.verifyCrc16(qris), isTrue);
    });

    test('verifyCrc16 menolak payload yang rusak atau dipotong (malformed/truncated)', () {
      // Memanggil: lib/services/qris_service.dart:108
      expect(QrisService.verifyCrc16(''), isFalse);
      expect(QrisService.verifyCrc16('000201010211'), isFalse);
      expect(QrisService.verifyCrc16('INVALID_QRIS_STRING_WITHOUT_TAG63'), isFalse);
      expect(QrisService.verifyCrc16('0002016304'), isFalse);
      final corrupted = '${kDefaultStaticQrisPayload.substring(0, kDefaultStaticQrisPayload.length - 4)}0000';
      expect(QrisService.verifyCrc16(corrupted), isFalse);
    });

    test('extractMerchantInfo menangani payload kosong dan rusak dengan fallback', () {
      // Memanggil: lib/services/qris_service.dart:124
      final emptyInfo = QrisService.extractMerchantInfo('');
      expect(emptyInfo['merchant_name'], equals('kopi sat'));
      expect(emptyInfo['nmid'], equals('ID1026516422080'));

      final garbageInfo = QrisService.extractMerchantInfo('XYZ99999NONTLV');
      expect(garbageInfo['merchant_name'], equals('kopi sat'));
    });
  });
}
