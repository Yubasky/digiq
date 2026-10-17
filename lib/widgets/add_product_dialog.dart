import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../theme/app_theme.dart';

class AddProductDialog extends StatefulWidget {
  final Function(ProductItem newProduct) onProductAdded;

  const AddProductDialog({super.key, required this.onProductAdded});

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _providerController = TextEditingController();
  final _descController = TextEditingController();
  
  ProductCategory _selectedCategory = ProductCategory.games;
  int _selectedColor = 0xFF06ACDC;
  IconData _selectedIcon = Icons.sports_esports_rounded;

  final List<int> _palette = const [
    0xFF06ACDC, // DigiQ Sky Blue
    0xFF0284C7, // Deep Ocean
    0xFF10B981, // Emerald Green
    0xFF8B5CF6, // Purple
    0xFFF59E0B, // Amber Orange
    0xFFEC4899, // Pink
  ];

  final List<Map<String, dynamic>> _iconOptions = const [
    {'name': 'Game', 'icon': Icons.sports_esports_rounded},
    {'name': 'Pulsa', 'icon': Icons.signal_cellular_alt_rounded},
    {'name': 'Dompet', 'icon': Icons.account_balance_wallet_rounded},
    {'name': 'Voucher', 'icon': Icons.confirmation_number_rounded},
    {'name': 'Listrik', 'icon': Icons.bolt_rounded},
    {'name': 'Streaming', 'icon': Icons.movie_filter_rounded},
    {'name': 'Wifi', 'icon': Icons.wifi_rounded},
    {'name': 'Kartu', 'icon': Icons.credit_card_rounded},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _providerController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _saveProduct() {
    if (_formKey.currentState!.validate()) {
      final double price = double.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      
      final newProduct = ProductItem(
        id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim(),
        category: _selectedCategory,
        price: price,
        provider: _providerController.text.trim().isEmpty ? 'DigiQ Official' : _providerController.text.trim(),
        description: _descController.text.trim().isEmpty ? 'Produk digital terverifikasi DigiQ. Pengiriman instan otomatis.' : _descController.text.trim(),
        stock: 999,
        isActive: true,
        icon: _selectedIcon,
        colorHex: _selectedColor,
      );

      widget.onProductAdded(newProduct);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add_shopping_cart_rounded, color: AppColors.primaryDark),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Tambah Produk Digital',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Mode Admin • Katalog Toko',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const Divider(height: 28),

                // Category selector
                const Text(
                  'Kategori Produk',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ProductCategory>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(isDense: true),
                  items: ProductCategory.values
                      .where((c) => c != ProductCategory.all)
                      .map((cat) => DropdownMenuItem(
                            value: cat,
                            child: Text(cat.label, style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCategory = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Name field
                const Text(
                  'Nama Produk Digital',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'Contoh: Diamond MLBB 86 Diamonds / Pulsa 50k',
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama produk wajib diisi' : null,
                ),
                const SizedBox(height: 16),

                // Provider & Price Row
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Provider / Brand',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _providerController,
                            decoration: const InputDecoration(
                              hintText: 'Telkomsel / Moonton',
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Harga Jual (Rp)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '25000',
                              prefixText: 'Rp ',
                              isDense: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Harga wajib diisi';
                              if (double.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) == null) return 'Nominal tidak valid';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Deskripsi
                const Text(
                  'Deskripsi Singkat',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Contoh: Pengiriman instan via ID Server, legal 100%.',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),

                // Choose Icon & Color
                const Text(
                  'Pilih Icon & Tema Warna Kartu',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _iconOptions.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final item = _iconOptions[idx];
                      final IconData icon = item['icon'] as IconData;
                      final bool isSelected = _selectedIcon == icon;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedIcon = icon;
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 44,
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.cardBorder,
                            ),
                          ),
                          child: Icon(
                            icon,
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                            size: 22,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // Color chips
                Row(
                  children: _palette.map((colorHex) {
                    final isSelected = _selectedColor == colorHex;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = colorHex),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(colorHex),
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.black87, width: 2.5)
                              : Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: Color(colorHex).withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                          ],
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _saveProduct,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Simpan Produk'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
