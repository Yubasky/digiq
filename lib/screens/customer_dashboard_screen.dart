import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';
import '../widgets/qris_modal.dart';
import 'login_screen.dart';

/// Sample shared products list (same as admin's seed data so the catalog is consistent)
List<ProductItem> _sharedProducts = [
  ProductItem(
    id: 'p-001',
    name: 'Pulsa 10.000',
    category: ProductCategory.pulsaData,
    price: 11500,
    provider: 'Telkomsel',
    description: 'Pulsa Telkomsel 10.000 aktif 30 hari',
    stock: 999,
    isActive: true,
    icon: Icons.signal_cellular_alt_rounded,
    colorHex: 0xFFEF4444,
  ),
  ProductItem(
    id: 'p-002',
    name: 'Pulsa 25.000',
    category: ProductCategory.pulsaData,
    price: 26500,
    provider: 'Telkomsel',
    description: 'Pulsa Telkomsel 25.000 aktif 30 hari',
    stock: 999,
    isActive: true,
    icon: Icons.signal_cellular_alt_rounded,
    colorHex: 0xFFEF4444,
  ),
  ProductItem(
    id: 'p-003',
    name: 'Paket Data 1GB',
    category: ProductCategory.pulsaData,
    price: 15000,
    provider: 'Indosat',
    description: 'Data Indosat 1GB 7 hari',
    stock: 999,
    isActive: true,
    icon: Icons.wifi_rounded,
    colorHex: 0xFFFFAA00,
  ),
  ProductItem(
    id: 'p-004',
    name: 'Paket Data 5GB',
    category: ProductCategory.pulsaData,
    price: 35000,
    provider: 'XL Axiata',
    description: 'Data XL 5GB 30 hari',
    stock: 999,
    isActive: true,
    icon: Icons.wifi_rounded,
    colorHex: 0xFF0077FF,
  ),
  ProductItem(
    id: 'p-005',
    name: 'Mobile Legends 86 Diamond',
    category: ProductCategory.games,
    price: 19000,
    provider: 'Moonton',
    description: '86 Diamond Mobile Legends',
    stock: 999,
    isActive: true,
    icon: Icons.sports_esports_rounded,
    colorHex: 0xFF7C3AED,
  ),
  ProductItem(
    id: 'p-006',
    name: 'Free Fire 70 Diamond',
    category: ProductCategory.games,
    price: 15000,
    provider: 'Garena',
    description: '70 Diamond Free Fire',
    stock: 999,
    isActive: true,
    icon: Icons.local_fire_department_rounded,
    colorHex: 0xFFFF6B00,
  ),
  ProductItem(
    id: 'p-007',
    name: 'Top Up OVO',
    category: ProductCategory.ewallet,
    price: 50000,
    provider: 'OVO',
    description: 'Isi saldo OVO Rp 50.000',
    stock: 999,
    isActive: true,
    icon: Icons.account_balance_wallet_rounded,
    colorHex: 0xFF4C1D95,
  ),
  ProductItem(
    id: 'p-008',
    name: 'Top Up GoPay',
    category: ProductCategory.ewallet,
    price: 100000,
    provider: 'GoPay',
    description: 'Isi saldo GoPay Rp 100.000',
    stock: 999,
    isActive: true,
    icon: Icons.account_balance_wallet_rounded,
    colorHex: 0xFF00AA5B,
  ),
  ProductItem(
    id: 'p-009',
    name: 'Netflix 1 Bulan',
    category: ProductCategory.streaming,
    price: 65000,
    provider: 'Netflix',
    description: 'Voucher Netflix Premium 1 Bulan',
    stock: 50,
    isActive: true,
    icon: Icons.movie_filter_rounded,
    colorHex: 0xFFDC2626,
  ),
  ProductItem(
    id: 'p-010',
    name: 'Spotify Premium',
    category: ProductCategory.streaming,
    price: 49000,
    provider: 'Spotify',
    description: 'Spotify Premium Individual 1 Bulan',
    stock: 100,
    isActive: true,
    icon: Icons.music_note_rounded,
    colorHex: 0xFF16A34A,
  ),
  ProductItem(
    id: 'p-011',
    name: 'Token PLN 50.000',
    category: ProductCategory.plnTagihan,
    price: 50500,
    provider: 'PLN',
    description: 'Token Listrik PLN Rp 50.000',
    stock: 999,
    isActive: true,
    icon: Icons.bolt_rounded,
    colorHex: 0xFFCA8A04,
  ),
  ProductItem(
    id: 'p-012',
    name: 'Token PLN 100.000',
    category: ProductCategory.plnTagihan,
    price: 101500,
    provider: 'PLN',
    description: 'Token Listrik PLN Rp 100.000',
    stock: 999,
    isActive: true,
    icon: Icons.bolt_rounded,
    colorHex: 0xFFCA8A04,
  ),
];

class CartItem {
  final ProductItem product;
  int qty;
  CartItem({required this.product, this.qty = 1});
}

class CustomerDashboardScreen extends StatefulWidget {
  final UserAccount currentUser;
  const CustomerDashboardScreen({super.key, required this.currentUser});

  @override
  State<CustomerDashboardScreen> createState() => _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen>
    with TickerProviderStateMixin {
  int _currentTab = 0; // 0=Beranda, 1=Keranjang, 2=Riwayat, 3=Profil
  ProductCategory _selectedCategory = ProductCategory.all;
  final List<CartItem> _cart = [];
  final List<QrisTransaction> _transactions = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late TabController _categoryTabController;

  @override
  void initState() {
    super.initState();
    _categoryTabController = TabController(
      length: ProductCategory.values.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _categoryTabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─── Cart helpers ───────────────────────────────────────────────────────────

  void _addToCart(ProductItem product) {
    final idx = _cart.indexWhere((c) => c.product.id == product.id);
    setState(() {
      if (idx >= 0) {
        _cart[idx].qty++;
      } else {
        _cart.add(CartItem(product: product));
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${product.name} ditambahkan ke keranjang',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        action: SnackBarAction(
          label: 'Lihat',
          textColor: Colors.white,
          onPressed: () => setState(() => _currentTab = 1),
        ),
      ),
    );
  }

  void _removeFromCart(String productId) {
    setState(() => _cart.removeWhere((c) => c.product.id == productId));
  }

  void _changeQty(String productId, int delta) {
    final idx = _cart.indexWhere((c) => c.product.id == productId);
    if (idx < 0) return;
    setState(() {
      _cart[idx].qty += delta;
      if (_cart[idx].qty <= 0) _cart.removeAt(idx);
    });
  }

  int get _cartCount => _cart.fold(0, (s, c) => s + c.qty);
  double get _cartTotal =>
      _cart.fold(0.0, (s, c) => s + c.product.price * c.qty);
  double get _cartFee => _cartTotal * 0.007; // 0.7% QRIS fee
  double get _cartGrandTotal => _cartTotal + _cartFee;

  // ─── Filtered products ──────────────────────────────────────────────────────

  List<ProductItem> get _filteredProducts {
    var list = _sharedProducts.where((p) => p.isActive).toList();
    if (_selectedCategory != ProductCategory.all) {
      list = list.where((p) => p.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              p.provider.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    return list;
  }

  // ─── Checkout ───────────────────────────────────────────────────────────────

  void _openCheckout() {
    if (_cart.isEmpty) return;
    _openQrisPayment();
  }

  void _openQrisPayment() {
    final double grandTotal = _cartGrandTotal > 0 ? _cartGrandTotal : 50000;
    final double baseAmount = _cartTotal > 0 ? _cartTotal : 50000;
    final double feeAmount = _cartFee;
    final String prodSummary = _cart.isNotEmpty
        ? _cart.map((c) => '${c.product.name} (x${c.qty})').join(', ')
        : 'Top Up Digital DigiQ';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => QrisModal(
        currentBalance: 999999,
        initialAmount: grandTotal,
        initialCustomerName: widget.currentUser.name,
        initialProductName: prodSummary,
        baseAmount: baseAmount,
        feeAmount: feeAmount,
        onPaymentSimulated: (amount, customerName, productName) {
          final tx = QrisTransaction(
            id: 'TRX-${DateTime.now().millisecondsSinceEpoch}',
            customerName: customerName,
            productName: prodSummary,
            baseAmount: baseAmount,
            feeAmount: feeAmount,
            totalAmount: amount,
            timestamp: DateTime.now(),
            status: 'SUCCESS',
          );
          setState(() {
            _transactions.insert(0, tx);
            _cart.clear();
          });
          _showPaymentSuccess(tx);
        },
      ),
    );
  }

  void _showPaymentSuccess(QrisTransaction tx) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 44),
              ),
              const SizedBox(height: 16),
              const Text('Pembayaran Berhasil!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  )),
              const SizedBox(height: 6),
              Text(
                formatCurrency(tx.totalAmount),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ID: ${tx.id}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _infoRow('Produk', tx.productName),
                    const SizedBox(height: 6),
                    _infoRow('Nama', tx.customerName),
                    const SizedBox(height: 6),
                    _infoRow('Biaya Admin',
                        formatCurrency(tx.feeAmount), color: AppColors.textMuted),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _currentTab = 2); // go to history
                  },
                  child: const Text('Lihat Riwayat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textSecondary)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildBerandaTab(),
          _buildKeranjangTab(),
          _buildRiwayatTab(),
          _buildProfilTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
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
              _navItem(0, Icons.home_rounded, Icons.home_outlined, 'Beranda'),
              _navItemBadge(1, Icons.shopping_cart_rounded,
                  Icons.shopping_cart_outlined, 'Keranjang', _cartCount),
              _navItem(2, Icons.receipt_long_rounded,
                  Icons.receipt_long_outlined, 'Riwayat'),
              _navItem(3, Icons.person_rounded, Icons.person_outlined, 'Profil'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
      int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isActive = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
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
            Icon(isActive ? activeIcon : inactiveIcon,
                color: isActive ? AppColors.primary : AppColors.textMuted,
                size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItemBadge(int index, IconData activeIcon, IconData inactiveIcon,
      String label, int count) {
    final isActive = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isActive ? activeIcon : inactiveIcon,
                    color: isActive ? AppColors.primary : AppColors.textMuted,
                    size: 22),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (count > 0)
            Positioned(
              top: -2,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── BERANDA TAB ────────────────────────────────────────────────────────────

  Widget _buildBerandaTab() {
    return CustomScrollView(
      slivers: [
        // App Bar
        SliverAppBar(
          expandedHeight: 220,
          floating: false,
          pinned: true,
          elevation: 0,
          backgroundColor: const Color(0xFF0077B6),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF06ACDC), Color(0xFF0077B6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 74),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/img/Logo_digiq.png',
                            height: 32,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.bolt_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'DigiQ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.notifications_outlined,
                                      color: Colors.white, size: 22),
                                  onPressed: () {},
                                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.warning,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Halo, ${widget.currentUser.name.split(' ').first} 👋',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mau beli produk digital apa hari ini?',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(62),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Cari produk, provider...',
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textMuted, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: AppColors.textMuted, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
          ),
        ),

        // Promo Banner
        SliverToBoxAdapter(
          child: _buildPromoBanner(),
        ),

        // Category chips
        SliverPersistentHeader(
          pinned: true,
          delegate: _CategoryHeaderDelegate(
            selectedCategory: _selectedCategory,
            onSelect: (cat) => setState(() => _selectedCategory = cat),
          ),
        ),

        // Product Grid
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          sliver: _filteredProducts.isEmpty
              ? SliverToBoxAdapter(
                  child: _buildEmptyState(),
                )
              : SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.67,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildProductCard(_filteredProducts[i]),
                    childCount: _filteredProducts.length,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      height: 110,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0093E9), Color(0xFF80D0C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: -30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '🎉 PROMO HARI INI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Bayar via QRIS,\nHemat Lebih Banyak!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _openQrisPayment,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(ProductItem product) {
    final color = Color(product.colorHex);
    return GestureDetector(
      onTap: () => _showProductDetail(product),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon area
            Container(
              width: double.infinity,
              height: 74,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(product.icon, color: color, size: 24),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.provider,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    Text(
                      formatCurrency(product.price),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: () => _addToCart(product),
                        icon: const Icon(Icons.add_shopping_cart_rounded,
                            size: 14),
                        label: const Text('Beli',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductDetail(ProductItem product) {
    final color = Color(product.colorHex);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    // Icon
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(product.icon, color: color, size: 44),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      product.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          product.category.label,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: color,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Info rows
                    _detailRow('Provider', product.provider),
                    _detailRow('Deskripsi', product.description),
                    _detailRow('Stok', '${product.stock} unit'),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Harga',
                            style: TextStyle(
                                fontSize: 15,
                                color: AppColors.textSecondary)),
                        Text(
                          formatCurrency(product.price),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _addToCart(product);
                        },
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: const Text('Tambah ke Keranjang'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const Text(' : ',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 64, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text(
            'Produk tidak ditemukan',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          const Text(
            'Coba kata kunci lain atau ubah filter kategori',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ─── KERANJANG TAB ──────────────────────────────────────────────────────────

  Widget _buildKeranjangTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Text('Keranjang',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                )),
            if (_cartCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_cartCount item',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_cart.isNotEmpty)
            TextButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Kosongkan Keranjang'),
                    content: const Text(
                        'Yakin ingin menghapus semua item dari keranjang?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Batal')),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() => _cart.clear());
                        },
                        child: const Text('Hapus Semua',
                            style: TextStyle(color: AppColors.danger)),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Hapus Semua',
                  style: TextStyle(
                      color: AppColors.danger, fontSize: 13)),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.cardBorder),
        ),
      ),
      body: _cart.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 72,
                      color: AppColors.textMuted.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  const Text(
                    'Keranjang kosong',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Yuk, tambahkan produk favoritmu!',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _currentTab = 0),
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: const Text('Lihat Produk'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _cart.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildCartItem(_cart[i]),
                  ),
                ),
                _buildCartSummary(),
              ],
            ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    final color = Color(item.product.colorHex);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.product.icon, color: color, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  item.product.provider,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  formatCurrency(item.product.price * item.qty),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              // Qty controls
              Row(
                children: [
                  _qtyBtn(
                    icon: Icons.remove_rounded,
                    onTap: () => _changeQty(item.product.id, -1),
                    color: item.qty == 1 ? AppColors.danger : AppColors.primary,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '${item.qty}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _qtyBtn(
                    icon: Icons.add_rounded,
                    onTap: () => _changeQty(item.product.id, 1),
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _removeFromCart(item.product.id),
                child: const Text(
                  'Hapus',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(
      {required IconData icon,
      required VoidCallback onTap,
      required Color color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  Widget _buildCartSummary() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _summaryRow('Subtotal', formatCurrency(_cartTotal)),
          const SizedBox(height: 4),
          _summaryRow(
              'Biaya QRIS (0.7%)', formatCurrency(_cartFee),
              valueColor: AppColors.textMuted),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: AppColors.cardBorder),
          ),
          _summaryRow('Total Pembayaran', formatCurrency(_cartGrandTotal),
              isBold: true, valueColor: AppColors.primary),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _openCheckout,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Bayar dengan QRIS',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 14 : 13,
            color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 15 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // ─── RIWAYAT TAB ────────────────────────────────────────────────────────────

  Widget _buildRiwayatTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text('Riwayat Transaksi',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            )),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.cardBorder),
        ),
      ),
      body: _transactions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 72,
                      color: AppColors.textMuted.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  const Text(
                    'Belum ada transaksi',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Transaksi yang berhasil akan muncul di sini',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _transactions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _buildTxCard(_transactions[i]),
            ),
    );
  }

  Widget _buildTxCard(QrisTransaction tx) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${tx.timestamp.day}/${tx.timestamp.month}/${tx.timestamp.year} '
                  '${tx.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${tx.timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text('Berhasil',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.success,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatCurrency(tx.totalAmount),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'via QRIS',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── PROFIL TAB ─────────────────────────────────────────────────────────────

  Widget _buildProfilTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF06ACDC), Color(0xFF0077B6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5), width: 2),
                        ),
                        child: Center(
                          child: Text(
                            widget.currentUser.name.isNotEmpty
                                ? widget.currentUser.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.currentUser.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Pelanggan DigiQ',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // User info card
                  _profileCard(
                    title: 'Informasi Akun',
                    children: [
                      _profileInfoRow(Icons.person_outline_rounded, 'Nama',
                          widget.currentUser.name),
                      _profileInfoRow(Icons.email_outlined, 'Email',
                          widget.currentUser.email),
                      _profileInfoRow(Icons.phone_outlined, 'No. HP',
                          widget.currentUser.phone),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Stats card
                  _profileCard(
                    title: 'Statistik',
                    children: [
                      _statRow(
                        icon: Icons.receipt_long_rounded,
                        color: AppColors.primary,
                        label: 'Total Transaksi',
                        value: '${_transactions.length}x',
                      ),
                      _statRow(
                        icon: Icons.monetization_on_rounded,
                        color: AppColors.success,
                        label: 'Total Pengeluaran',
                        value: formatCurrency(_transactions.fold(
                            0.0, (s, t) => s + t.totalAmount)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Menu
                  _profileCard(
                    title: 'Menu',
                    children: [
                      _menuItem(
                        icon: Icons.history_rounded,
                        label: 'Riwayat Transaksi',
                        onTap: () => setState(() => _currentTab = 2),
                      ),
                      _menuItem(
                        icon: Icons.notifications_outlined,
                        label: 'Notifikasi',
                        onTap: () {},
                      ),
                      _menuItem(
                        icon: Icons.help_outline_rounded,
                        label: 'Bantuan & FAQ',
                        onTap: () {},
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Logout
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.logout_rounded,
                            color: AppColors.danger, size: 20),
                      ),
                      title: const Text(
                        'Keluar',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.danger, size: 20),
                      onTap: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          PageRouteBuilder(
                            pageBuilder: (_, anim, _) => const LoginScreen(),
                            transitionsBuilder: (_, anim, _, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration:
                                const Duration(milliseconds: 400),
                          ),
                          (route) => false,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard(
      {required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _profileInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(
      {required IconData icon,
      required Color color,
      required String label,
      required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Category Header Delegate ────────────────────────────────────────────────

class _CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final ProductCategory selectedCategory;
  final void Function(ProductCategory) onSelect;

  _CategoryHeaderDelegate(
      {required this.selectedCategory, required this.onSelect});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: ProductCategory.values.map((cat) {
            final isSelected = selectedCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.cardBorder,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cat.icon,
                        size: 15,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  double get maxExtent => 52;

  @override
  double get minExtent => 52;

  @override
  bool shouldRebuild(covariant _CategoryHeaderDelegate oldDelegate) =>
      oldDelegate.selectedCategory != selectedCategory;
}
