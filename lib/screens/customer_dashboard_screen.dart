import 'dart:async';
import 'package:flutter/material.dart';
import 'edit_profile_screen.dart';
import '../models/product_model.dart';
import '../models/profile_model.dart';
import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/transaction_service.dart';
import '../services/app_language.dart';
import '../theme/app_theme.dart';
import '../widgets/qris_modal.dart';
import 'login_screen.dart';

// Shared in-memory CartItem model

class CartItem {
  final ProductItem product;
  int qty;
  CartItem({required this.product, this.qty = 1});
}

class CustomerDashboardScreen extends StatefulWidget {
  final ProfileModel profile;
  const CustomerDashboardScreen({super.key, required this.profile});

  @override
  State<CustomerDashboardScreen> createState() => _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  late ProfileModel _profile;
  int _currentTab = 0;
  final List<CartItem> _cart = [];
  List<QrisTransaction> _transactions = [];
  List<ProductModel> _products = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _productsLoading = true;

  // Stream subscriptions
  late final Stream<List<ProductModel>> _productStream;
  late final Stream<List<TransactionModel>> _trxStream;
  StreamSubscription<List<ProductModel>>? _productSub;
  StreamSubscription<List<TransactionModel>>? _trxSub;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _productStream = ProductService.watchProducts(activeOnly: true);
    _trxStream = TransactionService.watchUserTransactions();
    _productSub = _productStream.listen((list) {

      if (mounted) {
        setState(() {
          _products = list;
          _productsLoading = false;
        });
      }
    }, onError: (_) {});
    _trxSub = _trxStream.listen((list) {
      if (mounted) {
        setState(() {
          _transactions = list
              .map((m) => QrisTransaction.fromTransactionModel(m, _profile.fullName))
              .toList();
        });
      }
    }, onError: (_) {});
    // Expire pending di server saat buka riwayat
    TransactionService.expirePendingTransactions();
  }

  @override
  void didUpdateWidget(CustomerDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _profile = widget.profile;
    }
  }

  @override
  void dispose() {
    _productSub?.cancel();
    _trxSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ΓöÇΓöÇΓöÇ Cart helpers ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

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

  // ΓöÇΓöÇΓöÇ Filtered products ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

  List<ProductItem> get _filteredProducts {
    // Konversi ProductModel Supabase ke ProductItem untuk kompatibilitas widget lama
    var list = _products
        .map((m) => ProductItem.fromProductModel(m))
        .toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.provider.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  // ΓöÇΓöÇΓöÇ Checkout ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

  void _openCheckout() {
    if (_cart.isEmpty) return;
    // Untuk cart multi-item: beli produk pertama
    // (single product per transaksi sesuai desain RPC)
    final first = _cart.first;
    _openDirectQrisPayment(first.product);
  }

  Future<void> _openQrisPayment(ProductItem product, {String targetNumber = ''}) async {
    // Tampilkan loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Membuat transaksi...'),
          ],
        ),
      ),
    );

    try {
      final trx = await TransactionService.createTransaction(
        productId: product.id,
        targetNumber: targetNumber,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // tutup loading

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => QrisModal(
          transaction: trx,
          onSuccess: () {
            setState(() => _cart.clear());
            setState(() => _currentTab = 2); // buka riwayat
          },
          onCancelled: () {
            // transaksi dibatalkan/expired ΓÇö tidak perlu aksi
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // tutup loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll('Exception:', '').trim(),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }


  void _openDirectQrisPayment(ProductItem product) {
    _openQrisPayment(product);
  }



  // ΓöÇΓöÇΓöÇ Build ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: AppLanguage.current,
      builder: (context, lang, child) {
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
      },
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
              _navItem(0, Icons.home_rounded, Icons.home_outlined, AppLanguage.t('nav_home')),
              _navItemBadge(1, Icons.shopping_cart_rounded,
                  Icons.shopping_cart_outlined, AppLanguage.t('nav_cart'), _cartCount),
              _navItem(2, Icons.receipt_long_rounded,
                  Icons.receipt_long_outlined, AppLanguage.t('nav_history')),
              _navItem(3, Icons.person_rounded, Icons.person_outlined, AppLanguage.t('nav_profile')),
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

  // ΓöÇΓöÇΓöÇ BERANDA TAB ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

  Widget _buildBerandaTab() {
    return CustomScrollView(
      slivers: [
        // App Bar
        SliverAppBar(
          toolbarHeight: 62,
          expandedHeight: 180,
          floating: false,
          pinned: true,
          elevation: 0,
          backgroundColor: const Color(0xFF0077B6),
          title: Image.asset(
            'assets/img/logo digiq putih.png',
            height: 32,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              'DigiQ',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.notifications_outlined,
                          color: Colors.white, size: 24),
                      onPressed: _showCustomerNotifications,
                      constraints:
                          const BoxConstraints(minWidth: 42, minHeight: 42),
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
            ),
          ],
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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 72, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${AppLanguage.t('greeting_prefix')}${_profile.fullName.split(' ').first} 👋',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLanguage.t('greeting_subtitle'),
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
        ),

        // Search Bar in full-width Box Adapter
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Cari akun Netflix, ChatGPT, Spotify, Google...',
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
                    horizontal: 14, vertical: 11),
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

        // Promo Banner
        SliverToBoxAdapter(
          child: _buildPromoBanner(),
        ),

        // Accounts catalog header banner
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.workspace_premium_rounded, size: 20, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text(
                      'Katalog Akun Premium',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_filteredProducts.length} Akun Ready',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
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
                          '≡ƒÄë PROMO HARI INI',
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
                  onTap: () {
                    if (_products.isNotEmpty) {
                      _openDirectQrisPayment(ProductItem.fromProductModel(_products.first));
                    } else {
                      setState(() => _currentTab = 1);
                    }
                  },
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
            // Image or Icon area
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Container(
                width: double.infinity,
                height: 78,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.09),
                ),
                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                    ? Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
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
                      )
                    : Center(
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            product.provider,
                            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'Stok: ${product.stock}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: product.stock > 0 ? AppColors.success : AppColors.danger,
                          ),
                        ),
                      ],
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
                        onPressed: () => _openDirectQrisPayment(product),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 15),
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
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: AppColors.cardBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Image / Icon banner
                    Center(
                      child: Container(
                        width: 120,
                        height: 80,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                              ? Image.network(
                                  product.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(product.icon, color: color, size: 40),
                                )
                              : Icon(product.icon, color: color, size: 40),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      product.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text(
                              '${product.stock} Akun Siap Pakai',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Info rows
                    _detailRow('Provider', product.provider),
                    _detailRow('Deskripsi', product.description),
                    _detailRow('Ketersediaan', '${product.stock} akun ready'),
                    _detailRow('Pengiriman', 'Instan & Bergaransi Resmi'),
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
                    const SizedBox(height: 18),
                    // Dual action buttons: Tambah Keranjang & Beli Sekarang (Langsung QRIS)
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _addToCart(product);
                            },
                            icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                            label: const Text(
                              '+ Keranjang',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: AppColors.primary, width: 1.5),
                              foregroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _openDirectQrisPayment(product);
                            },
                            icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                            label: const Text(
                              'Beli Sekarang',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
    if (_productsLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
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

  // ΓöÇΓöÇΓöÇ KERANJANG TAB ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

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

  // ΓöÇΓöÇΓöÇ RIWAYAT TAB ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

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

  // ΓöÇΓöÇΓöÇ PROFIL TAB ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

  Widget _buildProfilTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            toolbarHeight: 62,
            expandedHeight: 200,
            pinned: true,
            automaticallyImplyLeading: false,
            elevation: 0,
            backgroundColor: const Color(0xFF0077B6),
            title: Image.asset(
              'assets/img/logo digiq putih.png',
              height: 32,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Text(
                'DigiQ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
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
                      const SizedBox(height: 22),
                      Stack(
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
                                _profile.fullName.isNotEmpty
                                    ? _profile.fullName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Material(
                              color: Colors.white,
                              shape: const CircleBorder(),
                              elevation: 3,
                              child: InkWell(
                                key: const Key('profile_avatar_edit_button'),
                                onTap: _navigateToEditProfile,
                                customBorder: const CircleBorder(),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.edit_rounded,
                                    size: 15,
                                    color: Color(0xFF0077B6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _profile.fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_profile.username.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@${_profile.username}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          AppLanguage.t('customer_badge'),
                          style: const TextStyle(
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
            child: Container(
              width: double.infinity,
              color: AppColors.background,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                children: [
                  // User info card
                  _profileCard(
                    title: 'Informasi Akun',
                    children: [
                      _profileInfoRow(Icons.person_outline_rounded, 'Nama',
                          _profile.fullName),
                      if (_profile.username.isNotEmpty)
                        _profileInfoRow(
                          Icons.alternate_email_rounded,
                          'Username',
                          '@${_profile.username}',
                        ),
                      _profileInfoRow(
                          Icons.alternate_email_rounded,
                          'ID Akun',
                          _profile.id.substring(0, 8).toUpperCase()),
                      _profileInfoRow(Icons.phone_outlined, 'No. HP',
                          _profile.phone),
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
                        key: const Key('profile_menu_edit_item'),
                        icon: Icons.manage_accounts_rounded,
                        label: 'Edit Profil',
                        onTap: _navigateToEditProfile,
                      ),
                      _menuItem(
                        icon: Icons.history_rounded,
                        label: 'Riwayat Transaksi',
                        onTap: () => setState(() => _currentTab = 2),
                      ),
                      _menuItem(
                        icon: Icons.notifications_outlined,
                        label: 'Notifikasi',
                        onTap: _showCustomerNotifications,
                      ),
                      _menuItem(
                        icon: Icons.help_outline_rounded,
                        label: 'Bantuan & FAQ',
                        onTap: _showFaqDialog,
                      ),
                      _menuItem(
                        icon: Icons.language_rounded,
                        label: AppLanguage.isId
                            ? 'Bahasa (Indonesia)'
                            : 'Language (English)',
                        onTap: () {
                          AppLanguage.toggleLanguage();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLanguage.isId
                                    ? 'Bahasa diubah ke Bahasa Indonesia'
                                    : 'Language changed to English',
                              ),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      _menuItem(
                        icon: Icons.info_outline_rounded,
                        label: 'Tentang Aplikasi',
                        onTap: _showAboutAppDialog,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Logout
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
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
                      onTap: _confirmLogout,
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
      {Key? key,
      required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return InkWell(
      key: key,
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

  Future<void> _navigateToEditProfile() async {
    final updated = await Navigator.push<ProfileModel>(
      context,
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile)),
    );
    if (updated != null && mounted) {
      setState(() => _profile = updated);
    } else if (mounted) {
      final fresh = await AuthService.getCurrentProfile();
      if (fresh != null && mounted) {
        setState(() => _profile = fresh);
      }
    }
  }

  void _showAboutAppDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF06ACDC), Color(0xFF0077B6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Image.asset(
                    'assets/img/logo digiq putih.png',
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.bolt_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'DigiQ Mobile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Versi 1.0.0 (Beta)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Aplikasi mobile produk digital yang terintegrasi pembayaran QRIS dengan konsep DANA Bisnis.\n\nNotasi biaya otomatis terjumlah, simulasi notifikasi transaksi instan, katalog pulsa, paket data, PLN, dan top up e-wallet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Tutup',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout_rounded,
                    color: AppColors.danger, size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                AppLanguage.t('logout_confirm_title'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLanguage.t('logout_confirm_desc'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.cardBorder),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(AppLanguage.t('cancel'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await AuthService.signOut();
                        if (!mounted) return;
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(AppLanguage.t('logout'),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
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

  void _showCustomerNotifications() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text(
                    AppLanguage.t('notifications'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Icon(Icons.notifications_off_outlined, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              const Text(
                'Belum Ada Notifikasi Baru',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pembaruan status pesanan dan informasi akun Anda akan muncul di sini.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Mengerti'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFaqDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.help_outline_rounded, color: AppColors.primary),
                    SizedBox(width: 10),
                    Text(
                      'Bantuan & Tanya Jawab (FAQ)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildFaqItem(
                  q: 'Bagaimana cara membeli akun digital?',
                  a: 'Pilih produk yang Anda inginkan di katalog, klik tombol "Beli Sekarang", lalu selesaikan pembayaran dengan scan kode QRIS.',
                ),
                _buildFaqItem(
                  q: 'Mengapa nominal pembayaran memiliki 3 digit unik?',
                  a: 'Kode unik (1-300) ditambahkan agar sistem dapat mencocokkan pembayaran mutasi Anda secara instan dan otomatis tanpa perlu unggah bukti transfer manual.',
                ),
                _buildFaqItem(
                  q: 'Berapa lama akun saya aktif?',
                  a: 'Setelah pembayaran terverifikasi, status transaksi akan berubah menjadi Sukses dan detail kredensial akun langsung tersedia di riwayat transaksi.',
                ),
                _buildFaqItem(
                  q: 'Bagaimana jika mengalami kendala transaksi?',
                  a: 'Silakan hubungi tim dukungan resmi kami melalui email: support@enikzrad.web.id.',
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFaqItem({required String q, required String a}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryDark)),
          const SizedBox(height: 6),
          Text(a, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }
}
