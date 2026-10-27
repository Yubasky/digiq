// test/qris_service_test.dart
// Unit test untuk QrisService (CRC16 + TLV EMVCo dynamic builder)
// Jalankan: flutter test test/qris_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:digiq/services/qris_service.dart';

void main() {
  group('QRIS kopi sat — Static Payload Verification', () {
    test('kDefaultStaticQrisPayload harus valid CRC16 (F95A)', () {
      expect(kDefaultStaticQrisPayload.endsWith('6304F95A'), isTrue);
      expect(QrisService.verifyCrc16(kDefaultStaticQrisPayload), isTrue);
    });

    test('extractMerchantInfo harus mengekstrak nama merchant kopi sat dan NMID ID1026516422080', () {
      final info = QrisService.extractMerchantInfo(kDefaultStaticQrisPayload);
      expect(info['merchant_name'], equals('kopi sat'));
      expect(info['nmid'], equals('ID1026516422080'));
    });
  });

  group('QRIS Dynamic Injection (buildDynamicQris)', () {
    test('buildDynamicQris(10300) menghasilkan tag 010212, tag 540510300, dan CRC16 valid', () {
      final dynamicQris = QrisService.buildDynamicQris(kDefaultStaticQrisPayload, 10300);

      // Pastikan bukan null atau kosong
      expect(dynamicQris, isNotEmpty);

      // Tag 01 harus dinamis (010212) bukan statis (010211)
      expect(dynamicQris.contains('010212'), isTrue);
      expect(dynamicQris.contains('010211'), isFalse);

      // Tag 54 harus memuat nominal 10300 dengan panjang 5 digit
      expect(dynamicQris.contains('540510300'), isTrue);

      // Nama merchant 'kopi sat' harus tetap utuh
      expect(dynamicQris.contains('5908kopi sat'), isTrue);

      // NMID ID1026516422080 harus tetap ada
      expect(dynamicQris.contains('ID1026516422080'), isTrue);

      // Hasil dynamic QRIS harus lolos verifikasi CRC16
      expect(QrisService.verifyCrc16(dynamicQris), isTrue);

      // Tag 54 harus berada tepat sebelum Tag 58
      final idx54 = dynamicQris.indexOf('540510300');
      final idx58 = dynamicQris.indexOf('5802ID');
      expect(idx54, isNonNegative);
      expect(idx58, isNonNegative);
      expect(idx54 < idx58, isTrue);
    });

    test('buildDynamicQris untuk nominal lain menghasilkan tag 54 yang tepat dan CRC valid', () {
      const amounts = [1500, 25750, 100000];
      for (final amt in amounts) {
        final dynamicQris = QrisService.buildDynamicQris(kDefaultStaticQrisPayload, amt);
        final amtStr = amt.toString();
        final lenStr = amtStr.length.toString().padLeft(2, '0');
        final expectedTag54 = '54$lenStr$amtStr';

        expect(dynamicQris.contains(expectedTag54), isTrue);
        expect(QrisService.verifyCrc16(dynamicQris), isTrue);
      }
    });
  });

  group('CRC16 & Validation Helpers', () {
    test('verifyCrc16 menolak payload yang rusak atau dimodifikasi tanpa hitung ulang', () {
      // Ubah satu karakter di payload statis tanpa update CRC
      final tampered = kDefaultStaticQrisPayload.replaceFirst('kopi sat', 'kopi sot');
      expect(QrisService.verifyCrc16(tampered), isFalse);
    });

    test('verifyCrc16 menolak string kosong atau tidak memiliki tag 63', () {
      expect(QrisService.verifyCrc16(''), isFalse);
      expect(QrisService.verifyCrc16('1234'), isFalse);
      expect(QrisService.verifyCrc16('000201010211'), isFalse);
    });

    test('formatRupiah memformat angka ke format mata uang Indonesia yang tepat', () {
      expect(QrisService.formatRupiah(10000), equals('Rp10.000'));
      expect(QrisService.formatRupiah(10300), equals('Rp10.300'));
      expect(QrisService.formatRupiah(1000000), equals('Rp1.000.000'));
      expect(QrisService.formatRupiah(500), equals('Rp500'));
    });
  });

  group('QrisSettings Model', () {
    test('fromMap menggunakan fallback kopi sat jika payload kosong', () {
      final s = QrisSettings.fromMap({});
      expect(s.staticPayload, equals(kDefaultStaticQrisPayload));
      expect(s.merchantName, equals('kopi sat'));
      expect(s.nmid, equals('ID1026516422080'));
      expect(s.uniqueCodeMin, equals(1));
      expect(s.uniqueCodeMax, equals(300));
      expect(s.pendingTtlMinutes, equals(15));
      expect(s.hasPayload, isTrue);
    });
  });
}
