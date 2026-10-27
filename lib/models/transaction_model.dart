// lib/models/transaction_model.dart
// Model Supabase TransactionModel + legacy QrisTransaction & TransactionStore.

export 'payment_mutation_model.dart';

class TransactionModel {
  final String id;
  final String trxCode;
  final String userId;
  final String productId;
  final String targetNumber;
  final double amount;       // base_amount (harga produk)
  final double baseAmount;   // sama dengan amount, untuk keterbacaan
  final int uniqueCode;      // kode unik 1-300 (0 = transaksi lama)
  final double totalAmount;  // base_amount + unique_code = yang harus dibayar
  final String status;       // 'pending' | 'success' | 'failed'
  final String? qrisPayload; // payload QRIS statis dari server
  final DateTime? expiredAt;
  final DateTime? paidAt;
  final String? verifiedBy;       // UUID admin yang verifikasi
  final String? matchedMutationId; // UUID payment_mutations
  final DateTime createdAt;

  // Join fields (nullable — dari query with join)
  final String? productName;
  final String? productCategory;

  const TransactionModel({
    required this.id,
    required this.trxCode,
    required this.userId,
    required this.productId,
    required this.targetNumber,
    required this.amount,
    double? baseAmount,
    int? uniqueCode,
    double? totalAmount,
    required this.status,
    this.qrisPayload,
    this.expiredAt,
    this.paidAt,
    this.verifiedBy,
    this.matchedMutationId,
    required this.createdAt,
    this.productName,
    this.productCategory,
  })  : baseAmount  = baseAmount  ?? amount,
        uniqueCode  = uniqueCode  ?? 0,
        totalAmount = totalAmount ?? amount;

  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isFailed  => status == 'failed';

  /// Apakah sudah kedaluwarsa berdasarkan waktu lokal.
  bool get isExpired =>
      expiredAt != null && DateTime.now().isAfter(expiredAt!);

  /// Sisa waktu hingga expired (null jika sudah expired).
  Duration? get timeLeft {
    if (expiredAt == null) return null;
    final diff = expiredAt!.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  /// Apakah transaksi ini menggunakan sistem kode unik baru.
  bool get hasUniqueCode => uniqueCode > 0;

  factory TransactionModel.fromMap(Map<String, dynamic> m) {
    final prodMap = m['products'] as Map<String, dynamic>?;
    final amountVal = ((m['amount'] as num?) ?? 0).toDouble();
    return TransactionModel(
      id:           m['id'] as String,
      trxCode:      (m['trx_code'] as String?) ?? '',
      userId:       m['user_id'] as String,
      productId:    m['product_id'] as String,
      targetNumber: (m['target_number'] as String?) ?? '',
      amount:       amountVal,
      baseAmount:   ((m['base_amount'] as num?) ?? amountVal).toDouble(),
      uniqueCode:   (m['unique_code'] as int?) ?? 0,
      totalAmount:  ((m['total_amount'] as num?) ?? amountVal).toDouble(),
      status:       (m['status'] as String?) ?? 'pending',
      qrisPayload:  m['qris_payload'] as String?,
      expiredAt: m['expired_at'] == null
          ? null
          : DateTime.parse(m['expired_at'] as String),
      paidAt: m['paid_at'] == null
          ? null
          : DateTime.parse(m['paid_at'] as String),
      verifiedBy:        m['verified_by'] as String?,
      matchedMutationId: m['matched_mutation_id'] as String?,
      createdAt: DateTime.parse(
          (m['created_at'] as String?) ?? DateTime.now().toIso8601String()),
      productName:     prodMap?['name'] as String?,
      productCategory: prodMap?['category'] as String?,
    );
  }
}

// ── Legacy model (kompatibilitas UI lama) ────────────────────────────────────

class QrisTransaction {
  final String id;
  final String customerName;
  final String productName;
  final double baseAmount;
  final double feeAmount;
  final double totalAmount;
  final DateTime timestamp;
  final String status; // 'SUCCESS', 'PENDING', 'FAILED'
  final String paymentMethod;

  const QrisTransaction({
    required this.id,
    required this.customerName,
    required this.productName,
    required this.baseAmount,
    this.feeAmount = 0.0,
    required this.totalAmount,
    required this.timestamp,
    this.status = 'SUCCESS',
    this.paymentMethod = 'QRIS Instant',
  });

  /// Konversi dari Supabase TransactionModel ke legacy QrisTransaction.
  factory QrisTransaction.fromTransactionModel(
      TransactionModel m, String customerName) {
    return QrisTransaction(
      id:           m.trxCode,
      customerName: customerName,
      productName:  m.productName ?? m.productId,
      baseAmount:   m.baseAmount,
      feeAmount:    m.uniqueCode.toDouble(), // kode unik sebagai "biaya unik"
      totalAmount:  m.totalAmount,
      timestamp:    m.createdAt,
      status:       m.status.toUpperCase(),
    );
  }
}

class TransactionStore {
  static final List<QrisTransaction> _transactions = [];
  static List<QrisTransaction> get transactions => _transactions;

  static void addTransaction(QrisTransaction tx) =>
      _transactions.insert(0, tx);

  static void clear() => _transactions.clear();

  static void syncFromModels(
      List<TransactionModel> models, String customerName) {
    _transactions
      ..clear()
      ..addAll(models
          .map((m) => QrisTransaction.fromTransactionModel(m, customerName)));
  }
}
