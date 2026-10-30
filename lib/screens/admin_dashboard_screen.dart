import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/product_model.dart';
import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/qris_service.dart';
import '../services/transaction_service.dart';
import '../services/avatar_picker.dart';
import '../theme/app_theme.dart';
import '../widgets/add_product_dialog.dart';
import '../services/app_language.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentNavIndex = 0;
  bool _isBalanceVisible = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Store financial state (dari stream Supabase & RPC)
  List<TransactionModel> _trxModels = [];
  List<QrisTransaction>  _transactions = [];
  List<TransactionModel> _pendingTrxModels = [];

  List<ProductItem>      _products = [];

  StreamSubscription<List<TransactionModel>>? _trxSub;
  StreamSubscription<List<ProductModel>>?     _productSub;

  // Realtime Today Stats (dari RPC admin_today_stats)
  double _todayOmset = 0.0;
  int _todaySuccessCount = 0;
  int _todayPendingCount = 0;
  int _todayTotalCount = 0;
  String? _statsError;

  double get _storeBalance => _todayOmset;

  // Real-time notification banner state
  QrisTransaction? _latestNotification;
  bool _showNotificationBanner = false;

  // Verify payment form
  final TextEditingController _verifyAmountCtrl = TextEditingController();
  final TextEditingController _verifyNoteCtrl   = TextEditingController();
  bool _verifying = false;
  Map<String, dynamic>? _verifyResult;

  // Mutasi Pembayaran Realtime
  List<PaymentMutationModel> _mutations = [];
  StreamSubscription<List<PaymentMutationModel>>? _mutationSub;

  // Pengaturan QRIS & Kode Unik
  final TextEditingController _qrisPayloadCtrl = TextEditingController();
  final TextEditingController _qrisMinCodeCtrl = TextEditingController();
  final TextEditingController _qrisMaxCodeCtrl = TextEditingController();
  final TextEditingController _qrisTtlCtrl     = TextEditingController();
  final TextEditingController _qrisMerchantCtrl = TextEditingController();
  final TextEditingController _qrisNmidCtrl    = TextEditingController();
  bool _savingSettings = false;
  QrisSettings? _currentSettings;

  @override
  void initState() {
    super.initState();
    _startStreams();
    _loadAdminQrisSettings();
    _refreshStats();
  }

  void _startStreams() {
    _trxSub = TransactionService.watchAllTransactionsForAdmin().listen(
      (list) {
        if (mounted) {
          setState(() {
            _trxModels = list;
            _transactions = list
                .map((m) => QrisTransaction.fromTransactionModel(m, m.userId))
                .toList();
            _pendingTrxModels = list.where((t) => t.isPending && !t.isExpired).toList();
          });
        }
        _refreshStats();
      },
      onError: (err) {
        debugPrint('[AdminDashboard] _trxSub stream error: ');
      },
    );
    _productSub = ProductService.watchProducts(activeOnly: false).listen(
      (list) {
        if (mounted) {
          setState(() {
            _products = list.map((m) => ProductItem.fromProductModel(m)).toList();
          });
        }
      },
      onError: (err) {
        debugPrint('[AdminDashboard] _productSub stream error: ');
      },
    );
    _mutationSub = TransactionService.watchPaymentMutations().listen(
      (list) {
        if (mounted) setState(() => _mutations = list);
      },
      onError: (err) {
        debugPrint('[AdminDashboard] _mutationSub stream error: ');
      },
    );
    TransactionService.expirePendingTransactions();
  }

  Future<void> _refreshStats() async {
    try {
      final stats = await TransactionService.getAdminTodayStats();
      if (!mounted) return;
      setState(() {
        _todayOmset = (stats['omset'] as num?)?.toDouble() ?? 0.0;
        _todaySuccessCount = (stats['success_count'] as num?)?.toInt() ?? 0;
        _todayPendingCount = (stats['pending_count'] as num?)?.toInt() ?? 0;
        _todayTotalCount = (stats['total_count'] as num?)?.toInt() ?? 0;
        _statsError = null;
      });
    } catch (e) {
      debugPrint('[AdminDashboard] getAdminTodayStats error: $e');
      if (mounted) {
        setState(() {
          _statsError = AppLanguage.isId ? 'Gagal memuat statistik ringkasan.' : 'Failed to load summary statistics.';
        });
      }
    }
  }

  Future<void> _loadAdminQrisSettings() async {
    final s = await QrisService.loadSettings(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _currentSettings = s;
      _qrisPayloadCtrl.text = s.staticPayload;
      _qrisMinCodeCtrl.text = s.uniqueCodeMin.toString();
      _qrisMaxCodeCtrl.text = s.uniqueCodeMax.toString();
      _qrisTtlCtrl.text = s.pendingTtlMinutes.toString();
      _qrisMerchantCtrl.text = s.merchantName;
      _qrisNmidCtrl.text = s.nmid;
    });
  }

  Future<void> _saveAdminQrisSettings() async {
    final payload = _qrisPayloadCtrl.text.trim();
    if (payload.isNotEmpty && !QrisService.verifyCrc16(payload)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguage.isId ? 'CRC16 QRIS tidak valid! Pastikan string EMVCo lengkap beserta tag 63.' : 'Invalid QRIS CRC16! Ensure complete EMVCo string including tag 63.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final minCode = int.tryParse(_qrisMinCodeCtrl.text.trim()) ?? 1;
    final maxCode = int.tryParse(_qrisMaxCodeCtrl.text.trim()) ?? 300;
    final ttl = int.tryParse(_qrisTtlCtrl.text.trim()) ?? 15;

    setState(() => _savingSettings = true);
    try {
      await TransactionService.updateQrisSettings(
        staticPayload: payload.isNotEmpty ? payload : null,
        uniqueCodeMin: minCode,
        uniqueCodeMax: maxCode,
        pendingTtlMinutes: ttl,
        merchantName: _qrisMerchantCtrl.text.trim(),
        nmid: _qrisNmidCtrl.text.trim(),
      );
      await _loadAdminQrisSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLanguage.isId ? '✓ Pengaturan QRIS & Kode Unik berhasil diperbarui' : '✓ QRIS & Unique Code settings updated successfully'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLanguage.isId ? 'Gagal menyimpan: ' : 'Failed to save: '}${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  @override
  void dispose() {
    _trxSub?.cancel();
    _productSub?.cancel();
    _mutationSub?.cancel();
    _searchController.dispose();
    _verifyAmountCtrl.dispose();
    _verifyNoteCtrl.dispose();
    _qrisPayloadCtrl.dispose();
    _qrisMinCodeCtrl.dispose();
    _qrisMaxCodeCtrl.dispose();
    _qrisTtlCtrl.dispose();
    _qrisMerchantCtrl.dispose();
    _qrisNmidCtrl.dispose();
    super.dispose();
  }



  Future<void> _addNewProduct(ProductModel model, PickedAvatarFile? imageFile) async {
    try {
      String? imageUrl = model.imageUrl;
      if (imageFile != null) {
        imageUrl = await ProductService.uploadProductImage(
          productId: model.id,
          bytes: imageFile.bytes,
          extension: imageFile.extension,
          mimeType: imageFile.mimeType,
        );
      }
      final toInsert = model.copyWith(imageUrl: imageUrl);
      ProductModel created;
      try {
        created = await ProductService.addProduct(toInsert);
      } catch (e) {
        if (imageUrl != null) {
          await ProductService.deleteStorageFile(imageUrl);
        }
        rethrow;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguage.isId ? '✓ Akun "${created.name}" berhasil ditambahkan ke katalog toko!' : '✓ Account "${created.name}" added to store catalog!'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLanguage.isId ? 'Gagal menambahkan produk: ' : 'Failed to add product: '}$e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      rethrow;
    }
  }

  Future<void> _updateProduct(ProductModel model, PickedAvatarFile? imageFile) async {
    try {
      String? imageUrl = model.imageUrl;
      if (imageFile != null) {
        imageUrl = await ProductService.uploadProductImage(
          productId: model.id,
          bytes: imageFile.bytes,
          extension: imageFile.extension,
          mimeType: imageFile.mimeType,
          oldImageUrl: model.imageUrl,
        );
      }
      final toUpdate = model.copyWith(imageUrl: imageUrl);
      final updated = await ProductService.updateProduct(toUpdate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguage.isId ? '✓ Akun "${updated.name}" berhasil diperbarui!' : '✓ Account "${updated.name}" updated successfully!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLanguage.isId ? 'Gagal memperbarui produk: ' : 'Failed to update product: '}$e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      rethrow;
    }
  }

  Future<void> _toggleProductStatus(String id) async {
    final idx = _products.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final item = _products[idx];
    final newStatus = !item.isActive;

    // Optimistic local state update for instant UI feedback
    setState(() {
      _products[idx] = item.copyWith(isActive: newStatus);
    });

    try {
      final updated = await ProductService.setProductActive(id, active: newStatus);
      if (!mounted) return;
      setState(() {
        final currentIdx = _products.indexWhere((p) => p.id == id);
        if (currentIdx != -1) {
          _products[currentIdx] = ProductItem.fromProductModel(updated);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus ? (AppLanguage.isId ? 'Produk "${item.name}" diaktifkan.' : 'Product "${item.name}" activated.') : (AppLanguage.isId ? 'Produk "${item.name}" dinonaktifkan.' : 'Product "${item.name}" deactivated.')),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Revert optimistic update on failure
      setState(() {
        final currentIdx = _products.indexWhere((p) => p.id == id);
        if (currentIdx != -1) {
          _products[currentIdx] = item;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLanguage.isId ? 'Gagal mengubah status produk: ' : 'Failed to change product status: '}$e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _deleteProduct(String id) {
    final item = _products.firstWhere((p) => p.id == id, orElse: () => _products.first);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLanguage.t('admin_delete_product_title')),
        content: Text(AppLanguage.isId ? 'Apakah Anda yakin ingin menghapus "${item.name}" dari katalog toko? Produk yang memiliki riwayat transaksi akan dinonaktifkan secara aman.' : 'Are you sure you want to remove "${item.name}" from the store catalog? Products with transaction history will be safely deactivated.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLanguage.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final hardDeleted = await ProductService.deleteProduct(id, imageUrl: item.imageUrl);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(hardDeleted
                        ? (AppLanguage.isId ? 'Akun "${item.name}" telah dihapus.' : 'Account "${item.name}" deleted.')
                        : (AppLanguage.isId ? 'Akun "${item.name}" dinonaktifkan karena memiliki riwayat transaksi.' : 'Account "${item.name}" deactivated due to transaction history.')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${AppLanguage.isId ? 'Gagal menghapus akun: ' : 'Failed to delete account: '}$e'),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(AppLanguage.t('admin_delete_action')),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog([ProductItem? productToEdit]) {
    showDialog(
      context: context,
      builder: (context) => AddProductDialog(
        initialProduct: productToEdit,
        onProductSaved: (model, imageFile) async {
          if (productToEdit != null) {
            await _updateProduct(model, imageFile);
          } else {
            await _addNewProduct(model, imageFile);
          }
        },
      ),
    );
  }

  List<ProductItem> get _filteredProducts {
    return _products.where((p) {
      final matchesSearch = _searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.provider.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: AppLanguage.current,
      builder: (context, lang, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(62),
            child: _buildTopAppBar(),
          ),
          body: IndexedStack(
            index: _currentNavIndex,
            children: [
              _buildDashboardTab(),
              _buildProductsTab(),
              _buildTransactionsTab(),
              _buildStoreSettingsTab(),
            ],
          ),
          bottomNavigationBar: _buildBottomNavigationBar(),
          floatingActionButton: _currentNavIndex == 0 || _currentNavIndex == 1
              ? FloatingActionButton(
                  onPressed: _showAddProductDialog,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: const CircleBorder(),
                  tooltip: AppLanguage.isId ? 'Tambah Produk Digital' : 'Add Digital Product',
                  child: const Icon(Icons.add_rounded, size: 28),
                )
              : null,
        );
      },
    );
  }

  Widget _buildRealtimePaymentBanner() {
    final trx = _latestNotification!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        AppLanguage.isId ? 'PEMBAYARAN QRIS MASUK!' : 'INCOMING QRIS PAYMENT!',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Baru Saja',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '+${formatCurrency(trx.totalAmount)} dari ${trx.customerName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Item: ${trx.productName} • Saldo otomatis diperbarui',
                    style: TextStyle(color: Colors.grey.shade300, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              onPressed: () => setState(() => _showNotificationBanner = false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopAppBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF06ACDC), Color(0xFF0077B6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Logo DigiQ Putih (seragam dengan customer)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/img/logo digiq putih.png',
                      height: 30,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'DigiQ',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Brand & Admin Panel Pill
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              AppLanguage.t('admin_store_title'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'PANEL ADMIN',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                AppLanguage.t('admin_store_active'),
                                style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Segarkan Data
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 21),
                    tooltip: AppLanguage.isId ? 'Segarkan Data' : 'Refresh Data',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      _refreshStats();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLanguage.isId ? 'Memperbarui data statistik admin...' : 'Refreshing admin stats...'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  // Tombol Logout
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: Text(AppLanguage.t('admin_logout_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
                            content: Text(AppLanguage.t('admin_logout_confirm')),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(AppLanguage.t('cancel')),
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await AuthService.signOut();
                                  if (!mounted) return;
                                  Navigator.of(context).pushAndRemoveUntil(
                                    PageRouteBuilder(
                                      pageBuilder: (_, anim, _) => const LoginScreen(),
                                      transitionsBuilder: (_, anim, _, child) =>
                                          FadeTransition(opacity: anim, child: child),
                                      transitionDuration: const Duration(milliseconds: 400),
                                    ),
                                    (route) => false,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                                child: Text(AppLanguage.t('logout')),
                              ),
                            ],
                          ),
                        );
                      },
                      tooltip: AppLanguage.t('logout'),
                      icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 19),
                      padding: const EdgeInsets.all(7),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 500));
            setState(() {});
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_showNotificationBanner && _latestNotification != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildRealtimePaymentBanner(),
                  ),
                // DANA Bisnis Inspired Revenue & Wallet Card
            _buildWalletCard(),

            const SizedBox(height: 16),

            // Quick Actions Bar
            _buildQuickActionBar(),

            const SizedBox(height: 20),

            // Live Recent Notifications / Transactions
            _buildRecentTransactionsHeader(),
            const SizedBox(height: 10),
            _buildRecentTransactionsList(),

            const SizedBox(height: 24),

            // Digital Products Catalog Section Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLanguage.t('admin_digital_catalog'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${_products.length} ${AppLanguage.t('admin_ready_sale_suffix')}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _currentNavIndex = 1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(AppLanguage.t('admin_manage_all')),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Products Grid
            _buildProductsGrid(limit: 6),
          ],
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildWalletCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Label & Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        AppLanguage.isId ? 'Saldo Toko (DANA Bisnis)' : 'Store Balance (DANA Bisnis)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
                icon: Icon(
                  _isBalanceVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Balance Amount (Compact font size)
          Text(
            _isBalanceVisible ? formatCurrency(_storeBalance) : 'Rp ••••••••',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 10),

          // Metrics divider line
          Container(height: 0.8, color: Colors.white.withValues(alpha: 0.2)),

          const SizedBox(height: 10),

          // Bottom Stats: Today's Transactions & Quick QRIS Trigger
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.t('admin_today_transactions'),
                      style: TextStyle(color: Colors.white70, fontSize: 10.5),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 13),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$_todaySuccessCount Berhasil (QRIS)${_todayPendingCount > 0 ? ' • $_todayPendingCount Pending' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionBar() {
    final actions = [
      {
        'title': AppLanguage.isId ? 'Tambah Akun' : 'Add Account',
        'icon': Icons.add_box_rounded,
        'color': AppColors.primary,
        'onTap': () => _showAddProductDialog(),
      },
      {
        'title': AppLanguage.isId ? 'Katalog Akun' : 'Account Catalog',
        'icon': Icons.inventory_2_rounded,
        'color': const Color(0xFF0284C7),
        'onTap': () => setState(() => _currentNavIndex = 1),
      },
      {
        'title': 'Penjualan',
        'icon': Icons.receipt_long_rounded,
        'color': const Color(0xFF10B981),
        'onTap': () => setState(() => _currentNavIndex = 2),
      },
      {
        'title': 'Toko & CS',
        'icon': Icons.storefront_rounded,
        'color': const Color(0xFF8B5CF6),
        'onTap': () => setState(() => _currentNavIndex = 3),
      },
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: actions.map((item) {
          final color = item['color'] as Color;
          return Expanded(
            child: InkWell(
              onTap: item['onTap'] as VoidCallback,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(item['icon'] as IconData, color: color, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['title'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecentTransactionsHeader() {
    return Row(
      children: [
        const Icon(Icons.history_rounded, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            AppLanguage.t('admin_recent_notif'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Auto-Notasi',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactionsList() {
    if (_transactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Center(
          child: Text(AppLanguage.t('admin_no_trx_today')),
        ),
      );
    }

    return Column(
      children: _transactions.take(5).map((trx) {
        final isSuccess = trx.status == 'SUCCESS';
        final isPending = trx.status == 'PENDING';
        final Color statusColor = isSuccess
            ? AppColors.success
            : isPending
                ? AppColors.warning
                : AppColors.error;
        final Color statusBg = isSuccess
            ? AppColors.successLight
            : isPending
                ? const Color(0xFFFEF3C7)
                : AppColors.errorLight;
        final IconData statusIcon = isSuccess
            ? Icons.check_rounded
            : isPending
                ? Icons.access_time_rounded
                : Icons.close_rounded;
        final String statusLabel = isSuccess
            ? (AppLanguage.isId ? 'QRIS Lunas' : 'QRIS Paid')
            : isPending
                ? (AppLanguage.isId ? 'Menunggu Bayar' : 'Awaiting Payment')
                : (AppLanguage.isId ? 'Batal / Expired' : 'Cancelled / Expired');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPending ? AppColors.warning.withValues(alpha: 0.4) : AppColors.cardBorder,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trx.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${trx.customerName} • ${trx.id}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(trx.totalAmount),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: isSuccess ? AppColors.success : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }



  Widget _buildProductsGrid({int? limit}) {
    final list = limit != null ? _filteredProducts.take(limit).toList() : _filteredProducts;

    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 10),
            const Text(
              'Tidak ada produk ditemukan',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Coba ganti filter kategori atau kata kunci pencarian Anda.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _showAddProductDialog,
              icon: const Icon(Icons.add, size: 16),
              label: Text(AppLanguage.isId ? 'Tambah Produk Sekarang' : 'Add Product Now'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final int crossAxisCount;
        final double childAspectRatio;

        if (width >= 1100) {
          crossAxisCount = 4;
          childAspectRatio = 0.94;
        } else if (width >= 720) {
          crossAxisCount = 3;
          childAspectRatio = 0.92;
        } else {
          crossAxisCount = 2;
          childAspectRatio = 0.88;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: list.length,
          itemBuilder: (context, idx) {
            final product = list[idx];
            return _buildProductCard(product);
          },
        );
      },
    );
  }

  Widget _buildProductCard(ProductItem product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: product.isActive ? AppColors.cardBorder : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 16:9 Banner Image Header with Overlaid Badge and Switch
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.imageUrl != null && product.imageUrl!.isNotEmpty
                      ? Image.network(
                          product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Color(product.colorHex).withValues(alpha: 0.12),
                            child: Center(
                              child: Icon(product.icon, color: Color(product.colorHex), size: 30),
                            ),
                          ),
                        )
                      : Container(
                          color: Color(product.colorHex).withValues(alpha: 0.12),
                          child: Center(
                            child: Icon(product.icon, color: Color(product.colorHex), size: 30),
                          ),
                        ),
                  // Scrim gradient for contrast
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                          Colors.black38,
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                  // Provider Badge Overlay (Top Left)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.5),
                      ),
                      child: Text(
                        product.provider,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Switch Overlay (Top Right)
                  Positioned(
                    top: 2,
                    right: 4,
                    child: Transform.scale(
                      scale: 0.72,
                      child: Switch(
                        value: product.isActive,
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppColors.success,
                        inactiveThumbColor: Colors.white70,
                        inactiveTrackColor: Colors.black45,
                        onChanged: (_) => _toggleProductStatus(product.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Product Details (Title, Description, Price & Stock) - Tight Spacing
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      product.description,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        formatCurrency(product.price),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: product.stock > 0 ? AppColors.successLight : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${AppLanguage.isId ? 'Stok' : 'Stock'}: ${product.stock}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: product.stock > 0 ? AppColors.success : AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Card Footer: Actions (Status, Edit & Delete) - No Spacer!
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFFF9FAFB),
                border: Border(top: BorderSide(color: AppColors.cardBorder, width: 0.8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        product.isActive ? Icons.check_circle_rounded : Icons.pause_circle_outline_rounded,
                        size: 13,
                        color: product.isActive ? AppColors.success : AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        product.isActive ? (AppLanguage.isId ? 'Aktif' : 'Active') : (AppLanguage.isId ? 'Nonaktif' : 'Inactive'),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: product.isActive ? AppColors.success : AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => _showAddProductDialog(product),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(3),
                          child: Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _deleteProduct(product.id),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(3),
                          child: Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsTab() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search input
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: AppLanguage.isId ? 'Cari produk digital, game, pulsa...' : 'Search digital products, games, credit...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${AppLanguage.isId ? 'Menampilkan' : 'Showing'} ${_filteredProducts.length} ${AppLanguage.isId ? 'Produk' : 'Products'}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              TextButton.icon(
                onPressed: _showAddProductDialog,
                icon: const Icon(Icons.add, size: 16),
                label: Text(AppLanguage.isId ? 'Tambah Baru' : 'Add New'),
              ),
            ],
          ),

          const SizedBox(height: 8),

          _buildProductsGrid(),
        ],
      ),
    ),
    ),
    );
  }

  Widget _buildTransactionsTab() {
    final pendingList = _pendingTrxModels;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_statsError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statsError!,
                      style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    onPressed: _refreshStats,
                    child: const Text('Coba Lagi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          // Summary bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(AppLanguage.t('admin_total_omset'), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      formatCurrency(_todayOmset),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primaryDark),
                    ),
                  ],
                ),
                Container(height: 30, width: 1, color: AppColors.cardBorder),
                Column(
                  children: [
                    Text(AppLanguage.isId ? 'Pending' : 'Pending', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      '$_todayPendingCount TRX',
                      style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16,
                        color: _todayPendingCount > 0 ? AppColors.warning : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(height: 30, width: 1, color: AppColors.cardBorder),
                Column(
                  children: [
                    Text(AppLanguage.isId ? 'Total' : 'Total', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      '$_todayTotalCount TRX',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Verifikasi Pembayaran Manual ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryDark, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(AppLanguage.isId ? 'Verifikasi Pembayaran QRIS' : 'QRIS Payment Verification',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  AppLanguage.isId ? 'Masukkan nominal transfer yang masuk persis sesuai mutasi rekening:' : 'Enter exact incoming transfer amount according to account mutation:',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _verifyAmountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
                        decoration: InputDecoration(
                          hintText: AppLanguage.isId ? 'Nominal (misal: 10300)' : 'Amount (e.g. 10300)',
                          prefixText: 'Rp ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _verifying ? null : _doVerifyPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _verifying
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(AppLanguage.isId ? 'Cocokkan' : 'Match', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _verifyNoteCtrl,
                  decoration: InputDecoration(
                    hintText: AppLanguage.isId ? 'Catatan (opsional)' : 'Note (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
                if (_verifyResult != null) ..._buildVerifyResult(),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Mutasi Unmatched (Uang Masuk Belum Tercocokkan) ───────────────────
          _buildUnmatchedMutationsSection(),

          const SizedBox(height: 18),

          // ── Transaksi Pending (butuh perhatian) ───────────────────────────────
          if (pendingList.isNotEmpty) ...[
            Text(AppLanguage.isId ? 'Pending Aktif' : 'Active Pending',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            ...pendingList.map((t) => _buildTrxCard(t, isPending: true)),
            const SizedBox(height: 18),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppLanguage.t('history_title'),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_todaySuccessCount ${AppLanguage.isId ? 'Sukses' : 'Success'}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_trxModels.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text(AppLanguage.t('history_empty_title'), style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _trxModels.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _buildTrxCard(_trxModels[i]),
            ),
        ],
      ),
    ),
    ),
    );
  }

  Future<void> _doVerifyPayment() async {
    if (_verifying) return;
    final amountStr = _verifyAmountCtrl.text.trim();
    if (amountStr.isEmpty) return;
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLanguage.isId ? 'Nominal tidak valid' : 'Invalid amount'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final formatted = QrisService.formatRupiah(amount);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Konfirmasi Verifikasi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Cocokkan nominal $formatted?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLanguage.t('cancel'), style: const TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ya, Cocokkan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() { _verifying = true; _verifyResult = null; });
    try {
      final result = await TransactionService.verifyPaymentByAmount(
        amount: amount,
        note: _verifyNoteCtrl.text.trim(),
      );
      if (mounted) setState(() => _verifyResult = result);
      _refreshStats();
    } catch (e) {
      if (mounted) {
        setState(() => _verifyResult = {
          'status': 'error',
          'message': e.toString().replaceAll('Exception:', '').trim(),
        });
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  List<Widget> _buildVerifyResult() {
    final r = _verifyResult!;
    final status = r['status'] as String? ?? '';
    Color bg; IconData icon; String title; String? subtitle;

    if (status == 'matched') {
      bg    = AppColors.successLight;
      icon  = Icons.check_circle_rounded;
      title = AppLanguage.isId ? 'Cocok! Transaksi ${r['trx_code']} ditandai sukses.' : 'Matched! Transaction ${r['trx_code']} marked success.';
      subtitle = 'Total: Rp${r['total_amount']}';
    } else if (status == 'unmatched') {
      bg    = Colors.orange.shade50;
      icon  = Icons.search_off_rounded;
      title = AppLanguage.isId ? 'Tidak ditemukan transaksi pending.' : 'No pending transaction found.';
      subtitle = r['message']?.toString();
    } else if (status == 'already_processed') {
      bg    = Colors.blue.shade50;
      icon  = Icons.replay_rounded;
      title = AppLanguage.isId ? 'Sudah diproses sebelumnya.' : 'Already processed earlier.';
      subtitle = null;
    } else {
      bg    = Colors.red.shade50;
      icon  = Icons.error_outline_rounded;
      title = 'Terjadi kesalahan.';
      subtitle = r['message']?.toString();
    }

    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: status == 'matched' ? AppColors.success : AppColors.warning, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  if (subtitle != null)
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildTrxCard(TransactionModel t, {bool isPending = false}) {
    final statusColor = t.isSuccess
        ? AppColors.success
        : t.isPending
            ? AppColors.warning
            : AppColors.error;
    final statusText = t.isSuccess ? (AppLanguage.isId ? 'SUKSES' : 'SUCCESS') : t.isPending ? (AppLanguage.isId ? 'MENUNGGU' : 'PENDING') : (AppLanguage.isId ? 'GAGAL' : 'FAILED');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? AppColors.warning.withValues(alpha: 0.5)
              : AppColors.cardBorder,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  t.trxCode,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12,
                      color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
            ],
          ),
          const Divider(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_rounded, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.productName ?? t.productId,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      'ID User: ${t.userId.substring(0, 8)}...',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    if (t.hasUniqueCode)
                      Text(
                        'Kode Unik: +${t.uniqueCode}',
                        style: const TextStyle(fontSize: 11, color: AppColors.primary),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isPending && t.hasUniqueCode) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatCurrency(t.totalAmount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+${t.uniqueCode.toString().padLeft(3, '0')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Base: ${formatCurrency(t.baseAmount)}',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ] else ...[
                    Text(
                      formatCurrency(t.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    if (t.baseAmount != t.totalAmount)
                      Text(
                        '(${formatCurrency(t.baseAmount)} + ${t.uniqueCode})',
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                      ),
                  ],
                ],
              ),
            ],
          ),
          if (isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _adminApproveReject(t, 'success'),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: const Text('Approve', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _adminApproveReject(t, 'failed'),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Reject', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _adminApproveReject(TransactionModel t, String status) async {
    try {
      await TransactionService.updateTransactionStatus(trxId: t.id, status: status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'success'
                ? '✓ Transaksi ${t.trxCode} disetujui'
                : '✗ Transaksi ${t.trxCode} ditolak'),
            backgroundColor: status == 'success' ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }


  Widget _buildStoreSettingsTab() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
      child: Column(
        children: [
          // Store Profile Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primaryLight,
                  child: ClipOval(
                    child: Image.asset(
                      'assets/img/Logo_digiq.png',
                      width: 52,
                      height: 52,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(Icons.store, size: 36, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'DigiQ Official Store',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Pengaturan QRIS Merchant & Kode Unik
          _buildQrisSettingsCard(),
          _buildSettingsTile(
            icon: Icons.language_rounded,
            title: AppLanguage.t('language_tile_title'),
            subtitle: AppLanguage.isId
                ? 'Bahasa Indonesia (Ketuk untuk beralih ke English)'
                : 'English (Tap to switch to Bahasa Indonesia)',
            onTap: () {
              AppLanguage.toggleLanguage();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLanguage.t('language_changed_toast')),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          _buildSettingsTile(
            icon: Icons.security_rounded,
            title: AppLanguage.t('admin_security_title'),
            subtitle: AppLanguage.t('admin_security_sub'),
            onTap: _showSecurityInfoDialog,
          ),
          _buildSettingsTile(
            icon: Icons.info_outline_rounded,
            title: AppLanguage.t('admin_about_title'),
            subtitle: AppLanguage.t('admin_about_sub'),
            onTap: _showAboutAppDialog,
          ),
        ],
      ),
    ),
    ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryDark),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildUnmatchedMutationsSection() {
    final unmatched = _mutations.where((m) => m.isUnmatched).toList();
    if (unmatched.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLanguage.t('admin_unmatched_mutations'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF78350F)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${unmatched.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppLanguage.isId ? 'Mutasi uang masuk berikut tidak menemukan transaksi pending yang cocok secara otomatis. Admin dapat menghubungkan manual ke transaksi atau mengabaikannya:' : 'The following incoming mutations could not be matched with pending transactions. Admin may manually match or dismiss them:',
            style: TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.3),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: unmatched.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final m = unmatched[i];
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatCurrency(m.amount),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primaryDark),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            m.source.toUpperCase(),
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ref: ${m.externalRef}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    if (m.notes != null && m.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          m.notes!,
                          style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: AppColors.warning),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            try {
                              await TransactionService.ignoreMutation(m.id);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Mutasi diabaikan')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Gagal: $e')),
                                );
                              }
                            }
                          },
                          child: const Text('Abaikan', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showLinkMutationDialog(m),
                          icon: const Icon(Icons.link_rounded, size: 14),
                          label: const Text('Hubungkan & Approve', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showLinkMutationDialog(PaymentMutationModel mutation) {
    final pendingList = _trxModels.where((t) => t.isPending).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.link_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Hubungkan Mutasi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nominal Mutasi: ${formatCurrency(mutation.amount)} (Ref: ${mutation.externalRef})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                AppLanguage.isId ? 'Pilih transaksi pending yang sesuai untuk diverifikasi:' : 'Select matching pending transaction to verify:',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              if (pendingList.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(AppLanguage.t('admin_no_pending_trx'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: pendingList.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final trx = pendingList[i];
                      return InkWell(
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await TransactionService.linkMutationToTransaction(
                              mutationId: mutation.id,
                              trxId: trx.id,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ Mutasi berhasil dihubungkan ke ${trx.trxCode} dan disetujui!'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text('${AppLanguage.isId ? 'Gagal menghubungkan: ' : 'Failed to match: '}${e.toString().replaceAll('Exception:', '').trim()}'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(trx.trxCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    Text(trx.productName ?? trx.productId, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              Text(
                                formatCurrency(trx.totalAmount),
                                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLanguage.t('cancel'))),
        ],
      ),
    );
  }

  Widget _buildQrisSettingsCard() {
    final activePayload = _qrisPayloadCtrl.text.trim().isNotEmpty
        ? _qrisPayloadCtrl.text.trim()
        : (_currentSettings?.staticPayload ?? kDefaultStaticQrisPayload);
    final isValidCrc = QrisService.verifyCrc16(activePayload);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.qr_code_2_rounded, color: AppColors.primaryDark, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLanguage.isId ? 'Pengaturan QRIS & Kode Unik' : 'QRIS & Unique Code Settings',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isValidCrc ? AppColors.successLight : AppColors.errorLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isValidCrc ? 'CRC16 VALID' : 'CRC16 INVALID',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: isValidCrc ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Preview QRIS Aktif (kopi sat - ID1026516422080)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                children: [
                  Text(
                    _qrisMerchantCtrl.text.isNotEmpty ? _qrisMerchantCtrl.text : 'kopi sat',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    'NMID: ${_qrisNmidCtrl.text.isNotEmpty ? _qrisNmidCtrl.text : 'ID1026516422080'} • A01',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  QrImageView(
                    data: activePayload,
                    version: QrVersions.auto,
                    size: 140,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                  const SizedBox(height: 4),
                  const Text('Preview QRIS Statis Merchant', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Text('Raw String EMVCo QRIS Statis:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _qrisPayloadCtrl,
            maxLines: 3,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: '000201010211...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(10),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Merchant Name:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _qrisMerchantCtrl,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NMID:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _qrisNmidCtrl,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLanguage.isId ? 'Kode Min:' : 'Min Code:', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _qrisMinCodeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLanguage.isId ? 'Kode Max:' : 'Max Code:', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _qrisMaxCodeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLanguage.isId ? 'TTL (Menit):' : 'TTL (Mins):', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _qrisTtlCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _savingSettings ? null : _saveAdminQrisSettings,
              icon: _savingSettings
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text(AppLanguage.t('admin_save_qris_settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.cardBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.dashboard_rounded, Icons.dashboard_outlined, AppLanguage.t('nav_admin_home')),
              _navItem(1, Icons.inventory_2_rounded, Icons.inventory_2_outlined, AppLanguage.t('nav_admin_catalog')),
              _navItemBadge(2, Icons.receipt_long_rounded, Icons.receipt_long_outlined, AppLanguage.t('nav_admin_trx'), _todayPendingCount),
              _navItem(3, Icons.storefront_rounded, Icons.storefront_outlined, AppLanguage.t('nav_admin_store')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentNavIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : inactiveIcon,
              color: isActive ? AppColors.primary : AppColors.textMuted,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItemBadge(int index, IconData activeIcon, IconData inactiveIcon, String label, int count) {
    final isActive = _currentNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentNavIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : inactiveIcon,
                  color: isActive ? AppColors.primary : AppColors.textMuted,
                  size: 22,
                ),
                if (count > 0)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSecurityInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Keamanan Sistem', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Enkripsi Sesi: Token JWT Supabase diisolasi per pengguna.', style: TextStyle(fontSize: 13)),
            SizedBox(height: 8),
            Text('• Kebijakan Akses: Row Level Security (RLS) PostgreSQL memastikan hanya role admin yang dapat mengelola produk dan mutasi.', style: TextStyle(fontSize: 13)),
            SizedBox(height: 8),
            Text('• Proteksi Data: Perubahan saldo dan role dilindungi trigger basis data.', style: TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLanguage.t('close')),
          ),
        ],
      ),
    );
  }

  void _showAboutAppDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(AppLanguage.isId ? 'Tentang DigiQ' : 'About DigiQ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DigiQ Digital Store & QRIS v1.0.0', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            Text(AppLanguage.isId ? 'Aplikasi toko produk digital berbasis Flutter Web CanvasKit dan Supabase BaaS.' : 'Digital store web app powered by Flutter Web and Supabase BaaS.', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Text(AppLanguage.isId ? '© 2026 Tim DigiQ. Hak cipta dilindungi undang-undang.' : '© 2026 DigiQ Team. All rights reserved.', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLanguage.t('close')),
          ),
        ],
      ),
    );
  }
}
