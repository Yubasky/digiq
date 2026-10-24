import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class QrisModal extends StatefulWidget {
  final double currentBalance;
  final Function(double amount, String customerName, String productName) onPaymentSimulated;
  final double? initialAmount;
  final String? initialCustomerName;
  final String? initialProductName;
  final double? baseAmount;
  final double? feeAmount;

  const QrisModal({
    super.key,
    required this.currentBalance,
    required this.onPaymentSimulated,
    this.initialAmount,
    this.initialCustomerName,
    this.initialProductName,
    this.baseAmount,
    this.feeAmount,
  });

  @override
  State<QrisModal> createState() => _QrisModalState();
}

class _QrisModalState extends State<QrisModal> {
  late final TextEditingController _amountController;
  late final TextEditingController _customerController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: (widget.initialAmount ?? 50000).toInt().toString(),
    );
    _customerController = TextEditingController(
      text: widget.initialCustomerName ?? 'Bayu Prayoga',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _customerController.dispose();
    super.dispose();
  }

  void _triggerPayment() {
    final double amount = double.tryParse(_amountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? (widget.initialAmount ?? 50000);
    final String customer = _customerController.text.trim().isEmpty ? (widget.initialCustomerName ?? 'Pelanggan DigiQ') : _customerController.text.trim();
    final String productName = widget.initialProductName ?? 'Top Up & Pembayaran Digital';

    setState(() {
      _isProcessing = true;
    });

    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      Navigator.of(context).pop();
      widget.onPaymentSimulated(amount, customer, productName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with QRIS official style banner
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'QRIS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Pembayaran Cepat',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Merchant Info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    const Text(
                      'DIGIQ STORE OFFICIAL',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'NMID: ID102026889901 • Dana Bisnis Terintegrasi',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // QR Code Visual Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Simulated high fidelity QR code pattern
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(200, 200),
                            painter: _QrisPainter(),
                          ),
                          // Center badge
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.primaryGradient,
                              ),
                              child: const Center(
                                child: Text(
                                  'Q',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.flash_on_rounded, size: 16, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          'Mendukung DANA, GoPay, OVO, ShopeePay, BCA, Mandiri',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Auto sum cost breakdown banner (Konsep Dana Bisnis)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primaryDark),
                        SizedBox(width: 6),
                        Text(
                          'Fitur DANA Bisnis: Auto-Notasi Biaya',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Nominal Tagihan:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text(
                          formatCurrency(widget.baseAmount ?? (double.tryParse(_amountController.text) ?? 50000)),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Biaya Layanan QRIS (0.7%):', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text(
                          widget.feeAmount != null ? formatCurrency(widget.feeAmount!) : 'Rp 0 (Promo)',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.success),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Pembayaran:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                        ),
                        Text(
                          formatCurrency(double.tryParse(_amountController.text) ?? (widget.initialAmount ?? 50000)),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primaryDark),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Simulation trigger (Allows Admin to test real-time payment receiving)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚡ Test Simulasi Notifikasi Pembayaran:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.brown),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customerController,
                            decoration: const InputDecoration(
                              labelText: 'Nama Pembeli',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Nominal (Rp)',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action button to simulate payment
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _triggerPayment,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(_isProcessing ? 'Memverifikasi Pembayaran...' : 'Simulasikan Pembayaran QRIS Sukses'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrisPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    const int matrixSize = 25;
    final double cellSize = size.width / matrixSize;

    // Outer framing box function
    void drawPositionPattern(double x, double y) {
      canvas.drawRect(Rect.fromLTWH(x, y, 7 * cellSize, 7 * cellSize), paint);
      final whitePaint = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(x + cellSize, y + cellSize, 5 * cellSize, 5 * cellSize), whitePaint);
      canvas.drawRect(Rect.fromLTWH(x + 2 * cellSize, y + 2 * cellSize, 3 * cellSize, 3 * cellSize), paint);
    }

    drawPositionPattern(0, 0);
    drawPositionPattern(size.width - 7 * cellSize, 0);
    drawPositionPattern(0, size.height - 7 * cellSize);

    // Decorative pseudorandom QR matrix blocks
    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        if (r < 8 && c < 8) continue;
        if (r < 8 && c >= matrixSize - 8) continue;
        if (r >= matrixSize - 8 && c < 8) continue;
        if (r >= 10 && r <= 14 && c >= 10 && c <= 14) continue;

        if ((r * 7 + c * 13 + (r * c)) % 3 == 0 || (r + c) % 2 == 0 && (r * c) % 5 == 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(c * cellSize + 0.5, r * cellSize + 0.5, cellSize - 1, cellSize - 1),
              const Radius.circular(1),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
