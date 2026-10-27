// test/auth_otp_test.dart
//
// Unit tests untuk:
//  - AuthService.mapOtpType (semua nilai yang diharapkan + edge cases)
//  - Validasi password (fungsi murni yang dipakai di SetNewPasswordScreen)
//  - Validasi format email (fungsi murni dari register_screen)
//
// Tidak memanggil Supabase; semua purely functional.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:digiq/services/auth_service.dart';

// ─── Fungsi bantu validasi (mirror dari UI) ──────────────────────────────────

/// Validasi password: minimal 8 karakter, tidak boleh kosong.
/// Mengembalikan null jika valid, atau pesan error.
String? validatePassword(String? v) {
  if (v == null || v.isEmpty) return 'Kata sandi wajib diisi';
  if (v.length < 8) return 'Kata sandi minimal 8 karakter';
  return null;
}

/// Validasi email: format RFC-ish sederhana.
String? validateEmail(String? v) {
  if (v == null || v.trim().isEmpty) return 'Email wajib diisi';
  final emailReg =
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
  if (!emailReg.hasMatch(v.trim())) return 'Format email tidak valid';
  return null;
}

void main() {
  // ── mapOtpType ──────────────────────────────────────────────────────────────
  group('AuthService.mapOtpType', () {
    test('email → OtpType.email', () {
      expect(AuthService.mapOtpType('email'), OtpType.email);
    });

    test('signup → OtpType.signup', () {
      expect(AuthService.mapOtpType('signup'), OtpType.signup);
    });

    test('SIGNUP uppercase → OtpType.signup (case-insensitive)', () {
      expect(AuthService.mapOtpType('SIGNUP'), OtpType.signup);
    });

    test('recovery → OtpType.recovery', () {
      expect(AuthService.mapOtpType('recovery'), OtpType.recovery);
    });

    test('magiclink → OtpType.magiclink', () {
      expect(AuthService.mapOtpType('magiclink'), OtpType.magiclink);
    });

    test('email_change → OtpType.emailChange', () {
      expect(AuthService.mapOtpType('email_change'), OtpType.emailChange);
    });

    test('emailchange → OtpType.emailChange', () {
      expect(AuthService.mapOtpType('emailchange'), OtpType.emailChange);
    });

    test('invite → OtpType.invite', () {
      expect(AuthService.mapOtpType('invite'), OtpType.invite);
    });

    test('null → null (tidak dikenal)', () {
      expect(AuthService.mapOtpType(null), isNull);
    });

    test('string kosong → null', () {
      expect(AuthService.mapOtpType(''), isNull);
    });

    test('nilai random → null', () {
      expect(AuthService.mapOtpType('xyz_unknown'), isNull);
    });
  });

  // ── Validasi Password ───────────────────────────────────────────────────────
  group('validatePassword', () {
    test('kosong → error', () {
      expect(validatePassword(''), isNotNull);
      expect(validatePassword(null), isNotNull);
    });

    test('kurang dari 8 karakter → error', () {
      expect(validatePassword('abc1234'), isNotNull);
    });

    test('tepat 8 karakter → valid', () {
      expect(validatePassword('abcd1234'), isNull);
    });

    test('lebih dari 8 karakter → valid', () {
      expect(validatePassword('sangatkuatpassword!'), isNull);
    });
  });

  // ── Validasi Email ───────────────────────────────────────────────────────────
  group('validateEmail', () {
    test('kosong → error', () {
      expect(validateEmail(''), isNotNull);
      expect(validateEmail(null), isNotNull);
    });

    test('tanpa @ → error', () {
      expect(validateEmail('tanpatanda'), isNotNull);
    });

    test('tanpa domain → error', () {
      expect(validateEmail('user@'), isNotNull);
    });

    test('domain tanpa TLD → error', () {
      expect(validateEmail('user@domain'), isNotNull);
    });

    test('format valid gmail → null', () {
      expect(validateEmail('pengguna@gmail.com'), isNull);
    });

    test('format valid dengan subdomain → null', () {
      expect(validateEmail('user@mail.example.co.id'), isNull);
    });

    test('karakter khusus yang diizinkan → null', () {
      expect(validateEmail('user+tag@example.org'), isNull);
    });
  });
}
