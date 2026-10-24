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
  bool _isProcessing = false;

  void _triggerPayment() {
    final double amount = widget.initialAmount ?? widget.baseAmount ?? 50000;
    final String customer = (widget.initialCustomerName != null && widget.initialCustomerName!.isNotEmpty)
        ? widget.initialCustomerName!
        : 'Pelanggan DigiQ';
    final String productName = widget.initialProductName ?? 'Akun Digital DigiQ';

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
    final double totalPay = widget.initialAmount ??
        ((widget.baseAmount ?? 50000) + (widget.feeAmount ?? 0));
    final double basePay = widget.baseAmount ?? totalPay;
    final double feePay = widget.feeAmount ?? (totalPay - basePay);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
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
                      'Pembayaran QRIS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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
              const Divider(height: 22),

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
                        fontSize: 14.5,
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

              const SizedBox(height: 14),

              // QR Code Visual Box (Clean, without center obstruction)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
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
                    // Clean, unobstructed QR code pattern
                    Container(
                      width: 200,
                      height: 200,
                      color: Colors.white,
                      child: CustomPaint(
                        size: const Size(200, 200),
                        painter: _QrisPainter(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.flash_on_rounded, size: 15, color: AppColors.success),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Scan via DANA, GoPay, OVO, ShopeePay, BCA, Mandiri',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Order & Fee breakdown banner
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
                    if (widget.initialProductName != null && widget.initialProductName!.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Produk:', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                          Flexible(
                            child: Text(
                              widget.initialProductName!,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Nominal Tagihan:', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                        Text(
                          formatCurrency(basePay),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Biaya Layanan QRIS (0.7%):', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                        Text(
                          feePay > 0 ? formatCurrency(feePay) : 'Rp 0 (Promo)',
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
                          formatCurrency(totalPay),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.primaryDark),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Instructions
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Setelah transfer berhasil di aplikasi m-Banking/e-wallet, klik tombol konfirmasi di bawah.',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action button to confirm payment
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
                      : const Icon(Icons.check_circle_rounded, size: 20),
                  label: Text(
                    _isProcessing ? 'Memverifikasi Pembayaran...' : 'Saya Sudah Bayar',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

/// Realistic unobstructed QR code painter with complete patterns
class _QrisPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    const int matrixSize = 25;
    final double cellSize = size.width / matrixSize;

    // Corner Finder Patterns
    void drawPositionPattern(double x, double y) {
      canvas.drawRect(Rect.fromLTWH(x, y, 7 * cellSize, 7 * cellSize), paint);
      final whitePaint = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(x + cellSize, y + cellSize, 5 * cellSize, 5 * cellSize), whitePaint);
      canvas.drawRect(Rect.fromLTWH(x + 2 * cellSize, y + 2 * cellSize, 3 * cellSize, 3 * cellSize), paint);
    }

    drawPositionPattern(0, 0);
    drawPositionPattern(size.width - 7 * cellSize, 0);
    drawPositionPattern(0, size.height - 7 * cellSize);

    // Alignment pattern near bottom right
    void drawAlignmentPattern(double x, double y) {
      canvas.drawRect(Rect.fromLTWH(x, y, 5 * cellSize, 5 * cellSize), paint);
      final whitePaint = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(x + cellSize, y + cellSize, 3 * cellSize, 3 * cellSize), whitePaint);
      canvas.drawRect(Rect.fromLTWH(x + 2 * cellSize, y + 2 * cellSize, cellSize, cellSize), paint);
    }
    drawAlignmentPattern(16 * cellSize, 16 * cellSize);

    // Data matrix modules across entire QR (NO center cutout or blocking badge)
    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        // Skip corner finder pattern areas
        if (r < 8 && c < 8) continue;
        if (r < 8 && c >= matrixSize - 8) continue;
        if (r >= matrixSize - 8 && c < 8) continue;
        // Skip alignment pattern area
        if (r >= 16 && r <= 20 && c >= 16 && c <= 20) continue;

        // Timing pattern
        if (r == 6 || c == 6) {
          if ((r + c) % 2 == 0) {
            canvas.drawRect(
              Rect.fromLTWH(c * cellSize + 0.3, r * cellSize + 0.3, cellSize - 0.6, cellSize - 0.6),
              paint,
            );
          }
          continue;
        }

        // Clean pseudo-data pattern
        if ((r * 7 + c * 13 + (r * c)) % 3 == 0 || ((r + c) % 2 == 0 && (r * c) % 4 == 0) || (r + c) % 5 == 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(c * cellSize + 0.3, r * cellSize + 0.3, cellSize - 0.6, cellSize - 0.6),
              const Radius.circular(0.8),
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
