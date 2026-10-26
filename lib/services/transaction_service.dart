// lib/services/transaction_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import '../models/transaction_model.dart';

class TransactionService {
  static SupabaseClient get _sb => SupabaseConfig.supabase;

  static const _table = 'transactions';

  // ─── Buat transaksi via RPC ──────────────────────────────────────────────────

  /// Panggil RPC atomik `create_purchase_transaction`.
  /// Server memvalidasi stok, menghitung harga, dan membuat QRIS payload.
  static Future<TransactionModel> createTransaction({
    required String productId,
    required String targetNumber,
  }) async {
    final data = await _sb.rpc(
      'create_purchase_transaction',
      params: {
        'p_product_id': productId,
        'p_target_number': targetNumber,
      },
    );
    return TransactionModel.fromMap(data as Map<String, dynamic>);
  }

  /// Stream realtime transaksi milik user yang login.
  /// Karena .stream() tidak mendukung join, kita ambil data produk terpisah.
  static Stream<List<TransactionModel>> watchUserTransactions() {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const Stream.empty();

    return _sb
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
          if (rows.isEmpty) return <TransactionModel>[];
          final productIds = rows
              .map((r) => r['product_id'] as String)
              .toSet()
              .toList();
          try {
            final products = await _sb
                .from('products')
                .select('id, name, category')
                .inFilter('id', productIds);
            final productMap = {
              for (final p in products) p['id'] as String: p,
            };
            return rows.map((r) {
              final enriched = Map<String, dynamic>.from(r);
              enriched['products'] = productMap[r['product_id']];
              return TransactionModel.fromMap(enriched);
            }).toList();
          } catch (_) {
            return rows
                .map((r) => TransactionModel.fromMap(r))
                .toList();
          }
        });
  }

  // ─── Stream: semua transaksi (admin) ────────────────────────────────────────

  /// Stream semua transaksi untuk admin, diperkaya data produk.
  static Stream<List<TransactionModel>> watchAllTransactionsForAdmin() {
    return _sb
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
          if (rows.isEmpty) return <TransactionModel>[];
          final productIds = rows
              .map((r) => r['product_id'] as String)
              .toSet()
              .toList();
          try {
            final products = await _sb
                .from('products')
                .select('id, name, category')
                .inFilter('id', productIds);
            final productMap = {
              for (final p in products) p['id'] as String: p,
            };
            return rows.map((r) {
              final enriched = Map<String, dynamic>.from(r);
              enriched['products'] = productMap[r['product_id']];
              return TransactionModel.fromMap(enriched);
            }).toList();
          } catch (_) {
            return rows
                .map((r) => TransactionModel.fromMap(r))
                .toList();
          }
        });
  }

  // ─── Admin: update status via RPC ────────────────────────────────────────────

  /// Approve atau reject transaksi. Diproteksi RPC di server (is_admin + aal2).
  static Future<TransactionModel> updateTransactionStatus({
    required String trxId,
    required String status, // 'success' | 'failed'
  }) async {
    final data = await _sb.rpc(
      'admin_update_transaction_status',
      params: {
        'p_trx_id': trxId,
        'p_status': status,
      },
    );
    return TransactionModel.fromMap(data as Map<String, dynamic>);
  }

  // ─── Expire pending (bisa dipanggil klien) ───────────────────────────────────

  /// Panggil RPC expire saat user membuka riwayat (fallback jika pg_cron off).
  static Future<int> expirePendingTransactions() async {
    try {
      final count = await _sb.rpc('expire_pending_transactions');
      return (count as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ─── Helper analitik ─────────────────────────────────────────────────────────

  /// Hitung omset hari ini dari list transaksi (status success saja).
  static double todayRevenue(List<TransactionModel> transactions) {
    final today = DateTime.now();
    return transactions
        .where((t) =>
            t.isSuccess &&
            t.createdAt.year == today.year &&
            t.createdAt.month == today.month &&
            t.createdAt.day == today.day)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Jumlah transaksi sukses hari ini.
  static int todaySuccessCount(List<TransactionModel> transactions) {
    final today = DateTime.now();
    return transactions
        .where((t) =>
            t.isSuccess &&
            t.createdAt.year == today.year &&
            t.createdAt.month == today.month &&
            t.createdAt.day == today.day)
        .length;
  }

  /// Jumlah transaksi pending aktif (belum expired).
  static int pendingCount(List<TransactionModel> transactions) {
    return transactions.where((t) => t.isPending && !t.isExpired).length;
  }
}
