class QrisTransaction {
  final String id;
  final String customerName;
  final String productName;
  final double baseAmount;
  final double feeAmount;
  final double totalAmount;
  final DateTime timestamp;
  final String status; // 'SUCCESS', 'PENDING', 'FAILED'
  final String paymentMethod; // 'QRIS Instant'

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
}

class TransactionStore {
  static final List<QrisTransaction> _transactions = [
    QrisTransaction(
      id: 'TRX-98214',
      customerName: 'Ahmad Faiz',
      productName: 'ChatGPT Plus (GPT-4o)',
      baseAmount: 75000,
      feeAmount: 525,
      totalAmount: 75525,
      timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
      status: 'SUCCESS',
    ),
    QrisTransaction(
      id: 'TRX-98213',
      customerName: 'Siti Rahma',
      productName: 'Netflix Premium 4K UHD',
      baseAmount: 35000,
      feeAmount: 245,
      totalAmount: 35245,
      timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 20)),
      status: 'SUCCESS',
    ),
    QrisTransaction(
      id: 'TRX-98212',
      customerName: 'Bayu Pratama',
      productName: 'Spotify Premium 3 Bulan',
      baseAmount: 25000,
      feeAmount: 175,
      totalAmount: 25175,
      timestamp: DateTime.now().subtract(const Duration(hours: 3)),
      status: 'SUCCESS',
    ),
  ];

  static List<QrisTransaction> get transactions => _transactions;

  static void addTransaction(QrisTransaction tx) {
    _transactions.insert(0, tx);
  }
}
