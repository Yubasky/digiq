// lib/widgets/qris_modal.dart
// Modal Pembayaran QRIS Resmi "kopi sat" dengan Kode Unik & Realtime Verification.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/transaction_model.dart';
import '../services/qris_service.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';

class QrisModal extends StatefulWidget {
  /// Transaksi awal — akan di-update via realtime stream.
  final TransactionModel transaction;

  /// Callback saat pembayaran sukses dikonfirmasi.
  final VoidCallback? onSuccess;

  /// Callback saat transaksi dibatalkan atau expired.
  final VoidCallback? onCancelled;

  const QrisModal({
    super.key,
    required this.transaction,
    this.onSuccess,
    this.onCancelled,
  });

  @override
  State<QrisModal> createState() => _QrisModalState();
}

class _QrisModalState extends State<QrisModal>
    with SingleTickerProviderStateMixin {
  late TransactionModel _trx;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _cancelling = false;
  bool _useDynamicQr = true; // Toggle: true = QR Dinamis, false = QR Statis Asli
  String? _dynamicPayload;
  QrisSettings? _settings;
  StreamSubscription<List<TransactionModel>>? _trxSub;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _trx = widget.transaction;
    _updateRemaining();
    _startCountdown();
    _loadSettings();
    _listenRealtime();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  void _updateRemaining() {
    if (_trx.expiredAt == null) {
      _remaining = Duration.zero;
      return;
    }
    final diff = _trx.expiredAt!.difference(DateTime.now());
    _remaining = diff.isNegative ? Duration.zero : diff;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_updateRemaining);
      if (_remaining == Duration.zero && _trx.isPending) {
        _countdownTimer?.cancel();
        _handleExpired();
      }
    });
  }

  Future<void> _loadSettings() async {
    final s = await QrisService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _dynamicPayload = QrisService.buildDynamicQris(
        s.staticPayload,
        _trx.totalAmount.toInt(),
      );
    });
  }

  void _listenRealtime() {
    _trxSub = TransactionService.watchUserTransactions().listen((list) {
      final updated = list.where((t) => t.id == _trx.id).toList();
      if (updated.isNotEmpty && mounted) {
        final latest = updated.first;
        if (latest.status != _trx.status) {
          setState(() => _trx = latest);
          if (latest.isSuccess) {
            _countdownTimer?.cancel();
            _showSuccessAndClose();
          } else if (latest.isFailed) {
            _countdownTimer?.cancel();
            _showFailedAndClose();
          }
        } else {
          setState(() => _trx = latest);
        }
      }
    });
  }

  void _handleExpired() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Waktu Habis'),
        content: const Text(
          'Waktu pembayaran transaksi ini telah kedaluwarsa. Silakan lakukan pemesanan ulang.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
              widget.onCancelled?.call();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessAndClose() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Pembayaran berhasil diverifikasi secara otomatis!'),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
    widget.onSuccess?.call();
  }

  void _showFailedAndClose() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transaksi telah dibatalkan atau kedaluwarsa.'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
    widget.onCancelled?.call();
  }

  Future<void> _cancelTransaction() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batalkan Pesanan?'),
        content: const Text(
          'Transaksi ini akan dibatalkan, kode unik dilepaskan, dan stok produk dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tidak'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya, Batalkan', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _cancelling = true);
    try {
      await TransactionService.cancelMyPendingTransaction(_trx.id);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onCancelled?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membatalkan: ${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label berhasil disalin ke clipboard!'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _trxSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining == Duration.zero;
    final minutes = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    // QR Payload untuk dirender
    final staticPayload = _settings?.staticPayload ?? kDefaultStaticQrisPayload;
    final qrDataToRender = _useDynamicQr
        ? (_dynamicPayload ?? QrisService.buildDynamicQris(staticPayload, _trx.totalAmount.toInt()))
        : staticPayload;

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
              // ── Header Modal ────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error, // Rose #E11D48
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'QRIS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 15,
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
                    ),
                  ),
                  // Countdown chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: expired
                          ? AppColors.error.withValues(alpha: 0.1)
                          : AppColors.primaryLight.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_rounded,
                          size: 14,
                          color: expired ? AppColors.error : AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          expired ? 'Kedaluwarsa' : '$minutes:$seconds',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: expired ? AppColors.error : AppColors.primary,
                          ),
                        ),
                      ],
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

              // ── IDENTITAS RESMI QRIS PROYEK (kopi sat) ──────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    const Text(
                      'kopi sat',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'NMID: ID1026516422080 • A01',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _trx.trxCode,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── TOGGLE: QR Dinamis (Otomatis) vs QR Statis Asli ─────────────
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _useDynamicQr = true),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _useDynamicQr ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _useDynamicQr
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.flash_on_rounded,
                                  size: 14,
                                  color: _useDynamicQr ? AppColors.primary : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'QR Otomatis (Nominal)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _useDynamicQr ? FontWeight.bold : FontWeight.normal,
                                    color: _useDynamicQr ? AppColors.primaryDark : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _useDynamicQr = false),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !_useDynamicQr ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: !_useDynamicQr
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 14,
                                  color: !_useDynamicQr ? AppColors.error : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'QR Statis Asli (Manual)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: !_useDynamicQr ? FontWeight.bold : FontWeight.normal,
                                    color: !_useDynamicQr ? AppColors.error : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── QR Code View (Render via QrImageView dari qr_flutter) ────────
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: expired
                          ? AppColors.error.withValues(alpha: 0.4)
                          : AppColors.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (expired ? AppColors.error : AppColors.primary)
                            .withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      if (expired)
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.timer_off_rounded, size: 44, color: AppColors.error),
                                SizedBox(height: 8),
                                Text(
                                  'QR Kedaluwarsa',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (!_useDynamicQr)
                        // QR Statis Asli: render QR statis atau fallback ke asset visual
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            QrImageView(
                              data: qrDataToRender,
                              version: QrVersions.auto,
                              size: 200.0,
                              backgroundColor: Colors.white,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                            ),
                            Positioned(
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Input Nominal Manual',
                                  style: TextStyle(color: Colors.white, fontSize: 10),
                                ),
                              ),
                            )
                          ],
                        )
                      else
                        // QR Dinamis (Tag 54 Total Amount terinjeksi)
                        QrImageView(
                          data: qrDataToRender,
                          version: QrVersions.auto,
                          size: 200.0,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        _useDynamicQr
                            ? 'Scan dengan BCA, DANA, GoPay, OVO, ShopeePay dll.\nNominal otomatis terisi.'
                            : 'Scan QR statis lalu ketik nominal bayar persis Rp${_trx.totalAmount.toInt()}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── RINCIAN BIAYA & KODE UNIK ────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Harga Produk',
                            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        Text(
                          QrisService.formatRupiah(_trx.baseAmount),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text('Kode Unik Pembayaran',
                                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Auto',
                                style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '+Rp${_trx.uniqueCode}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL HARUS DIBAYAR',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          QrisService.formatRupiah(_trx.totalAmount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── BADGE PERINGATAN KODE UNIK ──────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warningLight.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF78350F), height: 1.3),
                          children: [
                            const TextSpan(text: 'PENTING: Bayar TEPAT '),
                            TextSpan(
                              text: QrisService.formatRupiah(_trx.totalAmount),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const TextSpan(
                              text: ' hingga 3 digit terakhir agar sistem dapat memverifikasi transaksi secara otomatis.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── ACTION BUTTONS ──────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(
                        _trx.totalAmount.toInt().toString(),
                        'Nominal Rp${_trx.totalAmount.toInt()}',
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Salin Nominal'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryDark,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cancelling ? null : _cancelTransaction,
                      icon: _cancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
                            )
                          : const Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
                      label: const Text('Batalkan', style: TextStyle(color: AppColors.error)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
