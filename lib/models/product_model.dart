import 'package:flutter/material.dart';

enum ProductCategory {
  all('Semua', Icons.grid_view_rounded);

  final String label;
  final IconData icon;
  const ProductCategory(this.label, this.icon);
}

class ProductItem {
  final String id;
  final String name;
  final ProductCategory category;
  final double price;
  final String provider;
  final String description;
  final int stock;
  final bool isActive;
  final IconData icon;
  final int colorHex;
  final String? imageUrl;

  const ProductItem({
    required this.id,
    required this.name,
    this.category = ProductCategory.all,
    required this.price,
    required this.provider,
    required this.description,
    this.stock = 10,
    this.isActive = true,
    this.icon = Icons.account_circle_rounded,
    this.colorHex = 0xFF06ACDC,
    this.imageUrl,
  });

  ProductItem copyWith({
    String? id,
    String? name,
    ProductCategory? category,
    double? price,
    String? provider,
    String? description,
    int? stock,
    bool? isActive,
    IconData? icon,
    int? colorHex,
    String? imageUrl,
  }) {
    return ProductItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      provider: provider ?? this.provider,
      description: description ?? this.description,
      stock: stock ?? this.stock,
      isActive: isActive ?? this.isActive,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

/// Central store for account products shared across Customer & Admin dashboards
class ProductStore {
  static final List<ProductItem> _products = [
    ProductItem(
      id: 'acc_001',
      name: 'Google One / Pro 2TB',
      price: 45000,
      provider: 'Google Official',
      description: 'Akses Akun Google One 2TB Storage + Google Gemini Advanced. Private invite/akun resmi, garansi 30 hari penuh.',
      stock: 15,
      isActive: true,
      icon: Icons.cloud_done_rounded,
      colorHex: 0xFF0284C7,
      imageUrl: 'https://images.unsplash.com/photo-1573804633927-bfcbcd909acd?w=500&q=80',
    ),
    ProductItem(
      id: 'acc_002',
      name: 'ChatGPT Plus (GPT-4o)',
      price: 75000,
      provider: 'OpenAI',
      description: 'Akun ChatGPT Plus Resmi dengan akses prioritas GPT-4o, DALL-E 3 image generation, browsing internet, dan voice mode. Akun private.',
      stock: 20,
      isActive: true,
      icon: Icons.smart_toy_rounded,
      colorHex: 0xFF10B981,
      imageUrl: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=500&q=80',
    ),
    ProductItem(
      id: 'acc_003',
      name: 'Netflix Premium 4K UHD',
      price: 35000,
      provider: 'Netflix',
      description: 'Akun Netflix 1 Profile Private (PIN Khusus). Kualitas 4K UHD Ultra HD, support Smart TV, Laptop, Tablet, dan HP. Bebas on-hold.',
      stock: 28,
      isActive: true,
      icon: Icons.movie_filter_rounded,
      colorHex: 0xFFE50914,
      imageUrl: 'https://images.unsplash.com/photo-1522869635100-9f4c5e86aa37?w=500&q=80',
    ),
    ProductItem(
      id: 'acc_004',
      name: 'Spotify Premium 3 Bulan',
      price: 25000,
      provider: 'Spotify',
      description: 'Akun Spotify Premium Individual durasi 3 bulan. Bebas download lagu offline, tanpa iklan, skip lagu unlimited, audio ultra high.',
      stock: 35,
      isActive: true,
      icon: Icons.music_note_rounded,
      colorHex: 0xFF1DB954,
      imageUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80',
    ),
    ProductItem(
      id: 'acc_005',
      name: 'YouTube Premium 1 Bulan',
      price: 20000,
      provider: 'YouTube / Google',
      description: 'YouTube Premium & YouTube Music bebas iklan, putar di latar belakang (background play), unduh video offline HD.',
      stock: 40,
      isActive: true,
      icon: Icons.play_circle_fill_rounded,
      colorHex: 0xFFFF0000,
      imageUrl: 'https://images.unsplash.com/photo-1611162617213-7d7a39e9b1d7?w=500&q=80',
    ),
    ProductItem(
      id: 'acc_006',
      name: 'Canva Pro 1 Tahun',
      price: 30000,
      provider: 'Canva Official',
      description: 'Lisensi Akun Canva Pro 1 Tahun. Akses 100jt+ foto/elemen premium, Brand Kit, magic resize, background remover tanpa batas.',
      stock: 50,
      isActive: true,
      icon: Icons.brush_rounded,
      colorHex: 0xFF8B5CF6,
      imageUrl: 'https://images.unsplash.com/photo-1626785774573-4b799315345d?w=500&q=80',
    ),
    ProductItem(
      id: 'acc_007',
      name: 'Disney+ Hotstar 1 Bulan',
      price: 39000,
      provider: 'Disney+',
      description: 'Akun Disney+ Hotstar resolusi 4K Dolby Vision/Atmos. Nonton film box office Disney, Marvel Cinematic, Pixar, National Geographic.',
      stock: 18,
      isActive: true,
      icon: Icons.live_tv_rounded,
      colorHex: 0xFF0284C7,
      imageUrl: 'https://images.unsplash.com/photo-1574375927938-d5a98e8ffe85?w=500&q=80',
    ),
    ProductItem(
      id: 'acc_008',
      name: 'Microsoft 365 + 1TB Cloud',
      price: 50000,
      provider: 'Microsoft',
      description: 'Akun lisensi resmi Microsoft 365 (Word, Excel, PowerPoint, Outlook) + Cloud storage OneDrive 1TB aktif 1 tahun.',
      stock: 12,
      isActive: true,
      icon: Icons.business_center_rounded,
      colorHex: 0xFF0078D4,
      imageUrl: 'https://images.unsplash.com/photo-1531403009284-440f080d1e12?w=500&q=80',
    ),
  ];

  static List<ProductItem> get products => _products;

  static void addProduct(ProductItem item) {
    _products.insert(0, item);
  }

  static void updateProduct(ProductItem item) {
    final index = _products.indexWhere((p) => p.id == item.id);
    if (index != -1) {
      _products[index] = item;
    }
  }

  static void deleteProduct(String id) {
    _products.removeWhere((p) => p.id == id);
  }

  static void toggleStatus(String id) {
    final index = _products.indexWhere((p) => p.id == id);
    if (index != -1) {
      final current = _products[index];
      _products[index] = current.copyWith(isActive: !current.isActive);
    }
  }

  static void reduceStock(String productId, int quantity) {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      final current = _products[index];
      final newStock = (current.stock - quantity).clamp(0, 9999);
      _products[index] = current.copyWith(stock: newStock);
    }
  }
}
