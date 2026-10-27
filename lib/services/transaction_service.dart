// lib/services/transaction_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import '../models/transaction_model.dart';
import 'qris_service.dart';

class TransactionService {
  static SupabaseClient get _sb => SupabaseConfig.supabase;

  static const _table = 'transactions';
  static const _mutationsTable = 'payment_mutations';

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

  // ─── Batalkan transaksi pending (customer) ───────────────────────────────────

  /// Batalkan transaksi pending milik customer yang sedang login.
  /// Memanggil RPC `cancel_my_pending_transaction` di server.
  static Future<TransactionModel> cancelMyPendingTransaction(String trxId) async {
    final data = await _sb.rpc(
      'cancel_my_pending_transaction',
      params: {'p_transaction_id': trxId},
    );
    return TransactionModel.fromMap(data as Map<String, dynamic>);
  }

  /// Alias backwards compatibility
  static Future<TransactionModel> cancelTransaction(String trxId) =>
      cancelMyPendingTransaction(trxId);

  // ─── Stream: transaksi customer ──────────────────────────────────────────────

  /// Stream realtime transaksi milik user yang login.
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
            return rows.map((r) => TransactionModel.fromMap(r)).toList();
          }
        });
  }

  /// Stream transaksi pending user yang login, diurutkan terbaru dulu.
  static Stream<List<TransactionModel>> watchPendingTransactions() {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const Stream.empty();

    return _sb
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .where((r) => r['status'] == 'pending')
            .map((r) => TransactionModel.fromMap(r))
            .toList());
  }

  // ─── Stream: semua transaksi (admin) ────────────────────────────────────────

  static final Map<String, Map<String, dynamic>> _productCache = {};

  /// Stream semua transaksi untuk admin, diperkaya data produk (dibatasi 100 transaksi terbaru).
  static Stream<List<TransactionModel>> watchAllTransactionsForAdmin() {
    return _sb
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100)
        .asyncMap((rows) async {
          if (rows.isEmpty) return <TransactionModel>[];
          final uncachedIds = rows
              .map((r) => r['product_id'] as String)
              .where((id) => !_productCache.containsKey(id))
              .toSet()
              .toList();

          if (uncachedIds.isNotEmpty) {
            try {
              final products = await _sb
                  .from('products')
                  .select('id, name, category')
                  .inFilter('id', uncachedIds);
              for (final p in products) {
                _productCache[p['id'] as String] = p;
              }
            } catch (_) {}
          }

          return rows.map((r) {
            final enriched = Map<String, dynamic>.from(r);
            enriched['products'] = _productCache[r['product_id']];
            return TransactionModel.fromMap(enriched);
          }).toList();
        });
  }

  /// Memuat riwayat transaksi lama sebelum tanggal tertentu (pagination).
  static Future<List<TransactionModel>> loadOlderTransactions({
    required DateTime before,
    int limit = 50,
  }) async {
    try {
      final rows = await _sb
          .from(_table)
          .select('*, products(id, name, category)')
          .lt('created_at', before.toIso8601String())
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((r) => TransactionModel.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Mengambil agregat statistik riil hari ini via RPC database (zona waktu Asia/Jakarta).
  static Future<Map<String, dynamic>> getAdminTodayStats() async {
    try {
      final res = await _sb.rpc('admin_today_stats');
      if (res is Map<String, dynamic>) {
        return res;
      }
      return {
        'omset': 0.0,
        'success_count': 0,
        'pending_count': 0,
        'total_count': 0,
      };
    } catch (_) {
      return {
        'omset': 0.0,
        'success_count': 0,
        'pending_count': 0,
        'total_count': 0,
      };
    }
  }

  // ─── Stream: Mutasi Pembayaran (admin) ───────────────────────────────────────

  /// Stream realtime mutasi pembayaran untuk admin dashboard.
  static Stream<List<PaymentMutationModel>> watchPaymentMutations() {
    return _sb
        .from(_mutationsTable)
        .stream(primaryKey: ['id'])
        .order('received_at', ascending: false)
        .map((rows) => rows.map((r) => PaymentMutationModel.fromMap(r)).toList());
  }

  // ─── Admin: Verifikasi & Update Status ────────────────────────────────────────

  /// Admin mencocokkan mutasi masuk ke transaksi pending secara manual.
  static Future<Map<String, dynamic>> verifyPaymentManually(
    int amount, {
    String? notes,
    String? externalRef,
    String source = 'manual',
  }) async {
    final data = await _sb.rpc(
      'verify_payment_by_amount',
      params: {
        'p_amount': amount,
        'p_source': source,
        'p_external_ref': externalRef ?? '',
        'p_received_at': DateTime.now().toIso8601String(),
        'p_raw': {'notes': notes ?? ''},
      },
    );
    return (data as Map<String, dynamic>?) ?? {};
  }

  /// Alias backwards compatibility
  static Future<Map<String, dynamic>> verifyPaymentByAmount({
    required double amount,
    String source = 'manual',
    String externalRef = '',
    String note = '',
  }) =>
      verifyPaymentManually(
        amount.toInt(),
        notes: note,
        externalRef: externalRef.isNotEmpty ? externalRef : null,
        source: source,
      );

  /// Approve atau reject transaksi oleh admin.
  /// Mendukung pengaitan opsional dengan `mutationId`.
  static Future<TransactionModel> updateTransactionStatus({
    required String trxId,
    required String status, // 'success' | 'failed'
    String? mutationId,
  }) async {
    final data = await _sb.rpc(
      'admin_update_transaction_status',
      params: {
        'p_transaction_id': trxId,
        'p_new_status': status,
        'p_mutation_id': ?mutationId,
      },
    );
    return TransactionModel.fromMap(data as Map<String, dynamic>);
  }

  /// Hubungkan mutasi unmatched ke transaksi tertentu dan setujui transaksi.
  static Future<TransactionModel> linkMutationToTransaction({
    required String mutationId,
    required String trxId,
  }) async {
    return updateTransactionStatus(
      trxId: trxId,
      status: 'success',
      mutationId: mutationId,
    );
  }

  /// Ubah status mutasi menjadi ignored (diabaikan oleh admin).
  static Future<void> ignoreMutation(String mutationId) async {
    await _sb.from(_mutationsTable).update({
      'status': 'ignored',
      'notes': 'Diabaikan oleh admin pada ${DateTime.now().toLocal()}',
    }).eq('id', mutationId);
  }

  /// Ambil daftar mutasi via RPC untuk keperluan pagination / audit.
  static Future<List<PaymentMutationModel>> listMutations({
    bool unmatchedOnly = false,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final data = await _sb.rpc(
        'admin_list_mutations',
        params: {
          'p_unmatched_only': unmatchedOnly,
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      return (data as List<dynamic>? ?? [])
          .map((e) => PaymentMutationModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Fallback query langsung jika RPC belum tersedia
      var query = _sb.from(_mutationsTable).select();
      if (unmatchedOnly) {
        query = query.eq('status', 'unmatched');
      }
      final rows = await query
          .order('received_at', ascending: false)
          .range(offset, offset + limit - 1);
      return (rows as List<dynamic>)
          .map((e) => PaymentMutationModel.fromMap(e as Map<String, dynamic>))
          .toList();
    }
  }

  // ─── Settings: QRIS & Unique Code ────────────────────────────────────────────

  /// Ambil pengaturan QRIS dari database (bisa dipanggil customer & admin).
  static Future<QrisSettings> getQrisSettings() async {
    return QrisService.loadSettings(forceRefresh: true);
  }

  /// Update pengaturan QRIS dan kode unik oleh admin (Wajib AAL2).
  static Future<void> updateQrisSettings({
    String? staticPayload,
    int? uniqueCodeMin,
    int? uniqueCodeMax,
    int? pendingTtlMinutes,
    String? merchantName,
    String? nmid,
  }) async {
    final updates = <Map<String, dynamic>>[];
    final now = DateTime.now().toIso8601String();

    if (staticPayload != null) {
      updates.add({
        'key': 'qris_static_payload',
        'value': staticPayload.trim(),
        'updated_at': now,
      });
    }
    if (uniqueCodeMin != null) {
      updates.add({
        'key': 'unique_code_min',
        'value': uniqueCodeMin.toString(),
        'updated_at': now,
      });
    }
    if (uniqueCodeMax != null) {
      updates.add({
        'key': 'unique_code_max',
        'value': uniqueCodeMax.toString(),
        'updated_at': now,
      });
    }
    if (pendingTtlMinutes != null) {
      updates.add({
        'key': 'pending_ttl_minutes',
        'value': pendingTtlMinutes.toString(),
        'updated_at': now,
      });
    }
    if (merchantName != null) {
      updates.add({
        'key': 'qris_merchant_name',
        'value': merchantName.trim(),
        'updated_at': now,
      });
    }
    if (nmid != null) {
      updates.add({
        'key': 'qris_nmid',
        'value': nmid.trim(),
        'updated_at': now,
      });
    }

    if (updates.isNotEmpty) {
      await _sb.from('app_settings').upsert(updates);
      QrisService.clearCache();
    }
  }

  // ─── Expire pending ──────────────────────────────────────────────────────────

  /// Panggil RPC expire saat membuka riwayat/dashboard.
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
        .fold(0.0, (sum, t) => sum + t.totalAmount);
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
