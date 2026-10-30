// lib/models/product_model.dart
// Model Supabase — menggantikan ProductItem & ProductStore in-memory lama.
// ProductItem lama tetap dipertahankan di bawah untuk kompatibilitas widget
// yang belum direfactor; widget baru harus memakai ProductModel.

import 'package:flutter/material.dart';

// ── Supabase model ──────────────────────────────────────────────────────────

class ProductModel {
  final String id;
  final String name;
  final String category;
  final String description;
  final double price;
  final double? discountPrice;
  final int stock;
  final bool isActive;
  final String? imageUrl;
  final String provider;
  final DateTime createdAt;

  const ProductModel({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.price,
    this.discountPrice,
    required this.stock,
    required this.isActive,
    this.imageUrl,
    required this.provider,
    required this.createdAt,
  });

  double get effectivePrice => discountPrice ?? price;
  bool get hasDiscount => discountPrice != null && discountPrice! < price;
  bool get outOfStock => stock <= 0;

  factory ProductModel.fromMap(Map<String, dynamic> m) {
    return ProductModel(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? '',
      category: (m['category'] as String?) ?? 'Streaming',
      description: (m['description'] as String?) ?? '',
      price: ((m['price'] as num?) ?? 0).toDouble(),
      discountPrice: m['discount_price'] == null
          ? null
          : (m['discount_price'] as num).toDouble(),
      stock: (m['stock'] as num?)?.toInt() ?? 0,
      isActive: (m['is_active'] as bool?) ?? true,
      imageUrl: m['image_url'] as String?,
      provider: (m['provider'] as String?) ?? '',
      createdAt: DateTime.parse(
          (m['created_at'] as String?) ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'category': category,
        'description': description,
        'price': price,
        'discount_price': discountPrice,
        'stock': stock,
        'is_active': isActive,
        'image_url': imageUrl,
        'provider': provider,
      };

  Map<String, dynamic> toUpdateMap() => {
        'name': name,
        'category': category,
        'description': description,
        'price': price,
        'discount_price': discountPrice,
        'stock': stock,
        'is_active': isActive,
        'image_url': imageUrl,
        'provider': provider,
      };

  ProductModel copyWith({
    String? name,
    String? category,
    String? description,
    double? price,
    double? discountPrice,
    int? stock,
    bool? isActive,
    String? imageUrl,
    String? provider,
  }) {
    return ProductModel(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      price: price ?? this.price,
      discountPrice: discountPrice ?? this.discountPrice,
      stock: stock ?? this.stock,
      isActive: isActive ?? this.isActive,
      imageUrl: imageUrl ?? this.imageUrl,
      provider: provider ?? this.provider,
      createdAt: createdAt,
    );
  }
}

// ── Legacy in-memory model (dipertahankan agar widget lama tidak break) ─────

enum ProductCategory {
  all('Semua', Icons.grid_view_rounded),
  pulsa('Pulsa', Icons.phone_android_rounded),
  pln('PLN', Icons.electric_bolt_rounded),
  games('Games', Icons.videogame_asset_rounded),
  ewallet('E-Wallet', Icons.account_balance_wallet_rounded),
  streaming('Streaming', Icons.play_circle_fill_rounded);

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

  /// Konversi dari Supabase ProductModel ke ProductItem legacy.
  factory ProductItem.fromProductModel(ProductModel m) {
    return ProductItem(
      id: m.id,
      name: m.name,
      category: _categoryFromString(m.category),
      price: m.effectivePrice,
      provider: m.provider,
      description: m.description,
      stock: m.stock,
      isActive: m.isActive,
      imageUrl: m.imageUrl,
    );
  }

  static ProductCategory _categoryFromString(String s) {
    switch (s) {
      case 'Pulsa':
        return ProductCategory.pulsa;
      case 'PLN':
        return ProductCategory.pln;
      case 'Games':
        return ProductCategory.games;
      case 'E-Wallet':
        return ProductCategory.ewallet;
      case 'Streaming':
        return ProductCategory.streaming;
      default:
        return ProductCategory.all;
    }
  }

  String get categoryString {
    switch (category) {
      case ProductCategory.pulsa:
        return 'Pulsa';
      case ProductCategory.pln:
        return 'PLN';
      case ProductCategory.games:
        return 'Games';
      case ProductCategory.ewallet:
        return 'E-Wallet';
      case ProductCategory.streaming:
      case ProductCategory.all:
        return 'Streaming';
    }
  }

  ProductModel toProductModel({DateTime? createdAt}) {
    return ProductModel(
      id: id,
      name: name,
      category: categoryString,
      description: description,
      price: price,
      discountPrice: null,
      stock: stock,
      isActive: isActive,
      imageUrl: imageUrl,
      provider: provider,
      createdAt: createdAt ?? DateTime.now(),
    );
  }
}
