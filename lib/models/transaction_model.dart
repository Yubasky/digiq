class QrisTransaction {
  final String id;
  final String customerName;
  final String productName;
  final double baseAmount;
  final double feeAmount;
  final double totalAmount;
  final DateTime timestamp;
  final String status; // 'SUCCESS', 'PENDING', 'FAILED'
  final String paymentMethod; // 'QRIS DANA Bisnis'

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
