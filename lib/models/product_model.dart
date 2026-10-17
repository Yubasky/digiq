import 'package:flutter/material.dart';

enum ProductCategory {
  all('Semua', Icons.grid_view_rounded),
  pulsaData('Pulsa & Data', Icons.signal_cellular_alt_rounded),
  games('Game Topup', Icons.sports_esports_rounded),
  ewallet('E-Wallet', Icons.account_balance_wallet_rounded),
  streaming('Voucher Streaming', Icons.movie_filter_rounded),
  plnTagihan('PLN & Tagihan', Icons.bolt_rounded);

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

  const ProductItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.provider,
    required this.description,
    this.stock = 999,
    this.isActive = true,
    required this.icon,
    required this.colorHex,
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
    );
  }
}
