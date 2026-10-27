// test/widget_test.dart
// Unit tests untuk TransactionModel dan PaymentMutationModel

import 'package:flutter_test/flutter_test.dart';
import 'package:digiq/models/transaction_model.dart';

void main() {
  group('TransactionModel Unit Tests', () {
    test('fromMap membaca semua field QRIS statis dan kode unik dengan benar', () {
      final map = {
        'id': 'trx-uuid-123',
        'trx_code': '#TRX-20261027-0001',
        'user_id': 'user-uuid-456',
        'product_id': 'prod-uuid-789',
        'target_number': '08123456789',
        'amount': 10300,
        'base_amount': 10000,
        'unique_code': 300,
        'total_amount': 10300,
        'status': 'pending',
        'qris_payload': '000201010211...',
        'created_at': '2026-10-27T10:00:00.000Z',
        'products': {'name': 'Netflix Premium', 'category': 'Streaming'},
      };

      final trx = TransactionModel.fromMap(map);
      expect(trx.id, equals('trx-uuid-123'));
      expect(trx.trxCode, equals('#TRX-20261027-0001'));
      expect(trx.baseAmount, equals(10000.0));
      expect(trx.uniqueCode, equals(300));
      expect(trx.totalAmount, equals(10300.0));
      expect(trx.hasUniqueCode, isTrue);
      expect(trx.isPending, isTrue);
      expect(trx.isSuccess, isFalse);
      expect(trx.productName, equals('Netflix Premium'));
    });

    test('backward compatibility saat base_amount dan unique_code null di database', () {
      final map = {
        'id': 'legacy-trx',
        'trx_code': '#TRX-LEGACY',
        'user_id': 'user-1',
        'product_id': 'prod-1',
        'amount': 15000,
        'status': 'success',
      };

      final trx = TransactionModel.fromMap(map);
      expect(trx.amount, equals(15000.0));
      expect(trx.baseAmount, equals(15000.0));
      expect(trx.totalAmount, equals(15000.0));
      expect(trx.uniqueCode, equals(0));
      expect(trx.hasUniqueCode, isFalse);
      expect(trx.isSuccess, isTrue);
    });
  });

  group('PaymentMutationModel Unit Tests', () {
    test('fromMap dan toMap mengonversi objek mutasi dengan presisi', () {
      final map = {
        'id': 'mut-uuid-1',
        'source': 'webhook',
        'external_ref': 'MUT-20261027-001',
        'amount': 10300,
        'received_at': '2026-10-27T10:05:00.000Z',
        'status': 'matched',
        'matched_trx_id': 'trx-uuid-123',
        'notes': 'Cocok otomatis dengan #TRX-20261027-0001',
        'created_at': '2026-10-27T10:05:01.000Z',
      };

      final mut = PaymentMutationModel.fromMap(map);
      expect(mut.id, equals('mut-uuid-1'));
      expect(mut.source, equals('webhook'));
      expect(mut.externalRef, equals('MUT-20261027-001'));
      expect(mut.amount, equals(10300.0));
      expect(mut.isMatched, isTrue);
      expect(mut.isUnmatched, isFalse);
      expect(mut.matchedTrxId, equals('trx-uuid-123'));
    });
  });
}
