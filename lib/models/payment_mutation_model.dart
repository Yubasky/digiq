// lib/models/payment_mutation_model.dart
// Model untuk mencatat mutasi pembayaran masuk ke rekening/e-wallet merchant.

class PaymentMutationModel {
  final String id;
  final String source;
  final String externalRef;
  final double amount;
  final DateTime receivedAt;
  final Map<String, dynamic>? raw;
  final String status; // 'unmatched' | 'matched' | 'ignored'
  final String? matchedTrxId;
  final String? notes;
  final DateTime createdAt;

  // Joined / helper field
  final String? trxCode;

  const PaymentMutationModel({
    required this.id,
    required this.source,
    required this.externalRef,
    required this.amount,
    required this.receivedAt,
    this.raw,
    required this.status,
    this.matchedTrxId,
    this.notes,
    required this.createdAt,
    this.trxCode,
  });

  bool get isMatched   => status == 'matched';
  bool get isUnmatched => status == 'unmatched';
  bool get isIgnored   => status == 'ignored';

  factory PaymentMutationModel.fromMap(Map<String, dynamic> m) {
    return PaymentMutationModel(
      id:           m['id'] as String,
      source:       (m['source'] as String?) ?? 'manual',
      externalRef: (m['external_ref'] as String?) ?? '',
      amount:       ((m['amount'] as num?) ?? 0).toDouble(),
      receivedAt: m['received_at'] == null
          ? DateTime.now()
          : DateTime.parse(m['received_at'] as String),
      raw: m['raw'] is Map<String, dynamic>
          ? m['raw'] as Map<String, dynamic>
          : null,
      status:       (m['status'] as String?) ?? 'unmatched',
      matchedTrxId: m['matched_trx_id'] as String?,
      notes:        m['notes'] as String? ?? m['note'] as String?,
      createdAt: m['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(m['created_at'] as String),
      trxCode:      m['trx_code'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source': source,
      'external_ref': externalRef,
      'amount': amount,
      'received_at': receivedAt.toIso8601String(),
      'raw': raw,
      'status': status,
      'matched_trx_id': matchedTrxId,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
