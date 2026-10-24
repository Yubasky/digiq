import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/customer_preview_sheet.dart';
import '../widgets/qris_modal.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentNavIndex = 0;
  bool _isBalanceVisible = true;
  ProductCategory _selectedCategory = ProductCategory.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Store financial state
  double _storeBalance = 3850000;
  int _todayTransactionCount = 28;

  // Real-time notification banner state
  QrisTransaction? _latestNotification;
  bool _showNotificationBanner = false;

  // Initial Digital Products for Indonesian market
  late List<ProductItem> _products;

  // Transaction history
  late List<QrisTransaction> _transactions;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initializeData() {
    _products = [
      const ProductItem(
        id: 'prod_1',
        name: 'Mobile Legends 86 Diamonds',
        category: ProductCategory.games,
        price: 22500,
        provider: 'Moonton',
        description: 'Topup cepat via User ID & Zone ID. Otomatis masuk 1 detik.',
        icon: Icons.sports_esports_rounded,
        colorHex: 0xFF0284C7,
      ),
      const ProductItem(
        id: 'prod_2',
        name: 'Free Fire 140 Diamonds',
        category: ProductCategory.games,
        price: 20000,
        provider: 'Garena',
        description: 'Topup instant Free Fire resmi dan legal 100%.',
        icon: Icons.sports_esports_rounded,
        colorHex: 0xFFEF4444,
      ),
      const ProductItem(
        id: 'prod_3',
        name: 'Pulsa Telkomsel 50.000',
        category: ProductCategory.pulsaData,
        price: 51200,
        provider: 'Telkomsel',
        description: 'Masa aktif bertambah 30 hari. Pengiriman nomor nasional.',
        icon: Icons.signal_cellular_alt_rounded,
        colorHex: 0xFFDC2626,
      ),
      const ProductItem(
        id: 'prod_4',
        name: 'Paket Data Indosat 30GB',
        category: ProductCategory.pulsaData,
        price: 65000,
        provider: 'Indosat Ooredoo',
        description: 'Kuota utama 30GB 24 Jam berlaku 30 hari.',
        icon: Icons.wifi_rounded,
        colorHex: 0xFFF59E0B,
      ),
      const ProductItem(
        id: 'prod_5',
        name: 'Top Up DANA 100.000',
        category: ProductCategory.ewallet,
        price: 101500,
        provider: 'DANA Bisnis',
        description: 'Transfer instan ke akun DANA. Bebas biaya admin.',
        icon: Icons.account_balance_wallet_rounded,
        colorHex: 0xFF06ACDC,
      ),
      const ProductItem(
        id: 'prod_6',
        name: 'Spotify Premium 1 Bulan',
        category: ProductCategory.streaming,
        price: 54900,
        provider: 'Spotify',
        description: 'Akun Individual resmi. Musik tanpa iklan & offline download.',
        icon: Icons.movie_filter_rounded,
        colorHex: 0xFF10B981,
      ),
      const ProductItem(
        id: 'prod_7',
        name: 'Token Listrik PLN 50.000',
        category: ProductCategory.plnTagihan,
        price: 52000,
        provider: 'PLN Indonesia',
        description: 'Stroom kode token 20 digit instan via SMS dan invoice.',
        icon: Icons.bolt_rounded,
        colorHex: 0xFF8B5CF6,
      ),
      const ProductItem(
        id: 'prod_8',
        name: 'Top Up GoPay 50.000',
        category: ProductCategory.ewallet,
        price: 51000,
        provider: 'GoTo',
        description: 'Saldo langsung aktif untuk GoFood, GoRide, dan GoCar.',
        icon: Icons.account_balance_wallet_rounded,
        colorHex: 0xFF059669,
      ),
    ];

    _transactions = [
      QrisTransaction(
        id: 'TRX-98214',
        customerName: 'Ahmad Faiz',
        productName: 'Mobile Legends 86 Diamonds',
        baseAmount: 22500,
        feeAmount: 0,
        totalAmount: 22500,
        timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
      ),
      QrisTransaction(
        id: 'TRX-98213',
        customerName: 'Siti Rahma',
        productName: 'Pulsa Telkomsel 50.000',
        baseAmount: 51200,
        feeAmount: 0,
        totalAmount: 51200,
        timestamp: DateTime.now().subtract(const Duration(minutes: 27)),
      ),
      QrisTransaction(
        id: 'TRX-98212',
        customerName: 'Rian Saputra',
        productName: 'Spotify Premium 1 Bulan',
        baseAmount: 54900,
        feeAmount: 0,
        totalAmount: 54900,
        timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 12)),
      ),
    ];
  }

  void _onPaymentSimulated(double amount, String customerName, String productName) {
    final newTrx = QrisTransaction(
      id: 'TRX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      customerName: customerName,
      productName: productName,
      baseAmount: amount,
      feeAmount: 0,
      totalAmount: amount,
      timestamp: DateTime.now(),
    );

    setState(() {
      _storeBalance += amount;
      _todayTransactionCount += 1;
      _transactions.insert(0, newTrx);
      _latestNotification = newTrx;
      _showNotificationBanner = true;
    });

    // Auto dismiss notification banner after 6 seconds
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() {
          _showNotificationBanner = false;
        });
      }
    });

    // Show instant snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pembayaran QRIS ${formatCurrency(amount)} dari $customerName otomatis dijumlahkan!',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _addNewProduct(ProductItem item) {
    setState(() {
      _products.insert(0, item);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Produk "${item.name}" berhasil ditambahkan ke katalog toko!'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleProductStatus(String id) {
    setState(() {
      final index = _products.indexWhere((p) => p.id == id);
      if (index != -1) {
        final current = _products[index];
        _products[index] = current.copyWith(isActive: !current.isActive);
      }
    });
  }

  void _deleteProduct(String id) {
    final item = _products.firstWhere((p) => p.id == id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Produk?'),
        content: Text('Apakah Anda yakin ingin menghapus "${item.name}" dari katalog toko?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _products.removeWhere((p) => p.id == id);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Produk "${item.name}" telah dihapus.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _showQrisModal() {
    showDialog(
      context: context,
      builder: (context) => QrisModal(
        currentBalance: _storeBalance,
        onPaymentSimulated: _onPaymentSimulated,
      ),
    );
  }

  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (context) => AddProductDialog(onProductAdded: _addNewProduct),
    );
  }

  void _showCustomerPreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomerPreviewSheet(
        products: _products,
        onCheckoutSuccess: (amount, customer, product) {
          _onPaymentSimulated(amount, customer, product);
        },
      ),
    );
  }

  List<ProductItem> get _filteredProducts {
    return _products.where((p) {
      final matchesCategory = _selectedCategory == ProductCategory.all || p.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.provider.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            children: [
              // Real-time Payment Notification Banner (DANA Bisnis Style)
              if (_showNotificationBanner && _latestNotification != null)
                _buildRealtimePaymentBanner(),

              // Top App Bar
              _buildTopAppBar(),

              // Body content based on selected bottom navigation index
              Expanded(
                child: IndexedStack(
                  index: _currentNavIndex,
                  children: [
                    _buildDashboardTab(),
                    _buildProductsTab(),
                    _buildTransactionsTab(),
                    _buildStoreSettingsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
      floatingActionButton: _currentNavIndex == 0 || _currentNavIndex == 1
          ? FloatingActionButton(
              onPressed: _showAddProductDialog,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              tooltip: 'Tambah Produk Digital',
              child: const Icon(Icons.add_rounded, size: 28),
            )
          : null,
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
                      const Text(
                        'PEMBAYARAN QRIS MASUK!',
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
      padding: const EdgeInsets.only(top: 14, left: 16, right: 16, bottom: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Logo DigiQ
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/img/Logo_digiq.png',
                height: 38,
                width: 38,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        'DQ',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            // Brand and Admin tag
            // Brand and Admin tag
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'DigiQ Store',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ADMIN',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Flexible(
                        child: Text(
                          'Toko Aktif • QRIS',
                          style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Simulation Mode Switcher Button (View as Buyer)
            Tooltip(
              message: 'Simulasi Mode Pelanggan / User',
              child: InkWell(
                onTap: _showCustomerPreview,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.remove_red_eye_rounded, size: 13, color: AppColors.primaryDark),
                      SizedBox(width: 3),
                      Text(
                        'Mode User',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            // QRIS Quick Header Icon
            IconButton(
              onPressed: _showQrisModal,
              tooltip: 'Tampilkan QRIS Toko',
              icon: const Icon(Icons.qr_code_2_rounded, color: AppColors.primary, size: 24),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 2),
            // Logout Button
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Keluar', style: TextStyle(fontWeight: FontWeight.bold)),
                    content: const Text('Yakin ingin keluar dari akun Admin?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Batal'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
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
                        child: const Text('Keluar'),
                      ),
                    ],
                  ),
                );
              },
              tooltip: 'Keluar',
              icon: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 22),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return RefreshIndicator(
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
                      const Text(
                        'Katalog Produk Digital',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${_products.length} produk siap dijual via QRIS',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _currentNavIndex = 1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Kelola Semua'),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Category Filter Pills
            _buildCategoryFilterPills(),

            const SizedBox(height: 14),

            // Products Grid
            _buildProductsGrid(limit: 6),
          ],
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
                    const Expanded(
                      child: Text(
                        'Saldo Toko (DANA Bisnis)',
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
                    const Text(
                      'Transaksi Masuk Hari Ini',
                      style: TextStyle(color: Colors.white70, fontSize: 10.5),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 13),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$_todayTransactionCount Berhasil (QRIS)',
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
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showQrisModal,
                icon: const Icon(Icons.qr_code_rounded, size: 14, color: AppColors.primaryDark),
                label: const Text(
                  'QRIS Toko',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        'title': 'Tambah Produk',
        'icon': Icons.add_box_rounded,
        'color': AppColors.primary,
        'onTap': _showAddProductDialog,
      },
      {
        'title': 'QRIS Bisnis',
        'icon': Icons.qr_code_scanner_rounded,
        'color': const Color(0xFF0284C7),
        'onTap': _showQrisModal,
      },
      {
        'title': 'Test Pembayaran',
        'icon': Icons.flash_on_rounded,
        'color': const Color(0xFFF59E0B),
        'onTap': () => _onPaymentSimulated(50000, 'Bagas Pratama', 'Voucher Game DigiQ'),
      },
      {
        'title': 'Mode User',
        'icon': Icons.shopping_bag_rounded,
        'color': const Color(0xFF10B981),
        'onTap': _showCustomerPreview,
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
        const Expanded(
          child: Text(
            'Notifikasi Transaksi Terakhir',
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
        child: const Center(
          child: Text('Belum ada transaksi QRIS hari ini.'),
        ),
      );
    }

    return Column(
      children: _transactions.take(2).map((trx) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_rounded, color: AppColors.success, size: 18),
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
                    '+${formatCurrency(trx.totalAmount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.success,
                    ),
                  ),
                  const Text(
                    'QRIS Lunas',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryFilterPills() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ProductCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final cat = ProductCategory.values[idx];
          final isSelected = _selectedCategory == cat;

          return InkWell(
            onTap: () => setState(() => _selectedCategory = cat),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.cardBorder,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  cat.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
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
              label: const Text('Tambah Produk Sekarang'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.68,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (context, idx) {
        final product = list[idx];
        return _buildProductCard(product);
      },
    );
  }

  Widget _buildProductCard(ProductItem product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: product.isActive ? AppColors.cardBorder : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Category tag + toggle
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 6, top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(product.colorHex).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      product.provider,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Color(product.colorHex),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.65,
                  child: Switch(
                    value: product.isActive,
                    activeThumbColor: AppColors.primary,
                    onChanged: (_) => _toggleProductStatus(product.id),
                  ),
                ),
              ],
            ),
          ),

          // Product Icon Graphic Box
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(product.colorHex).withValues(alpha: 0.85),
                    Color(product.colorHex),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(product.colorHex).withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                product.icon,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),

          // Name and Price
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  formatCurrency(product.price),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Card Footer: Stock & delete action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.cardBorder, width: 0.8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      product.isActive ? Icons.check_circle : Icons.pause_circle,
                      size: 13,
                      color: product.isActive ? AppColors.success : AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      product.isActive ? 'Aktif' : 'Nonaktif',
                      style: TextStyle(
                        fontSize: 11,
                        color: product.isActive ? AppColors.success : AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => _deleteProduct(product.id),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search input
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Cari produk digital, game, pulsa...',
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
          const SizedBox(height: 14),

          // Categories
          _buildCategoryFilterPills(),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Menampilkan ${_filteredProducts.length} Produk',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              TextButton.icon(
                onPressed: _showAddProductDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Tambah Baru'),
              ),
            ],
          ),

          const SizedBox(height: 8),

          _buildProductsGrid(),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    const Text('Total Pendapatan', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      formatCurrency(_storeBalance),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primaryDark),
                    ),
                  ],
                ),
                Container(height: 30, width: 1, color: AppColors.cardBorder),
                Column(
                  children: [
                    const Text('Total Transaksi', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      '$_todayTransactionCount TRX',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Riwayat Transaksi QRIS',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              ElevatedButton.icon(
                onPressed: _showQrisModal,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Simulasi Baru', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _transactions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final trx = _transactions[idx];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          trx.id,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'LUNAS - QRIS DANA',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
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
                                trx.productName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                'Pelanggan: ${trx.customerName}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatCurrency(trx.totalAmount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: AppColors.primaryDark,
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

  Widget _buildStoreSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
                const SizedBox(height: 4),
                const Text(
                  'Merchant Partner Terverifikasi QRIS & DANA Bisnis',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Status Toko: Buka 24 Jam',
                    style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Settings options
          _buildSettingsTile(
            icon: Icons.qr_code_rounded,
            title: 'Pengaturan QRIS Merchant',
            subtitle: 'ID: ID102026889901 • Auto-Notasi Biaya Aktif',
            onTap: _showQrisModal,
          ),
          _buildSettingsTile(
            icon: Icons.support_agent_rounded,
            title: 'Hubungi Customer Support Toko',
            subtitle: 'Admin siap melayani pertanyaan pembeli',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Membuka kontak CS DigiQ...')),
              );
            },
          ),
          _buildSettingsTile(
            icon: Icons.security_rounded,
            title: 'Keamanan & Autentikasi 2-User',
            subtitle: 'Akun Admin terlindungi enkripsi',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.info_outline_rounded,
            title: 'Tentang Aplikasi DigiQ',
            subtitle: 'Versi 1.0.0 (Prototype Preview)',
            onTap: () {},
          ),
        ],
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

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          onTap: (index) => setState(() => _currentNavIndex = index),
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Beranda',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_rounded),
              label: 'Katalog',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_rounded),
              label: 'Transaksi',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_rounded),
              label: 'Toko Admin',
            ),
          ],
        ),
      ),
    );
  }
}
