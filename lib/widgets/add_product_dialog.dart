import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../theme/app_theme.dart';

class AddProductDialog extends StatefulWidget {
  final Function(ProductItem newProduct) onProductAdded;
  final ProductItem? initialProduct;

  const AddProductDialog({
    super.key,
    required this.onProductAdded,
    this.initialProduct,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _providerController;
  late final TextEditingController _descController;
  late final TextEditingController _stockController;
  late final TextEditingController _imageUrlController;

  late int _selectedColor;
  late IconData _selectedIcon;

  final List<int> _palette = const [
    0xFF06ACDC, // DigiQ Sky Blue
    0xFF0284C7, // Deep Ocean
    0xFF10B981, // Emerald Green
    0xFF8B5CF6, // Purple
    0xFFF59E0B, // Amber Orange
    0xFFE50914, // Netflix Red
    0xFF1DB954, // Spotify Green
  ];

  final List<Map<String, dynamic>> _quickPresets = const [
    {
      'label': 'Netflix',
      'provider': 'Netflix',
      'name': 'Netflix Premium 4K UHD',
      'desc': 'Akun Netflix 1 Profile Private (PIN Khusus). 4K Ultra HD, semua perangkat.',
      'color': 0xFFE50914,
      'icon': Icons.movie_filter_rounded,
      'imageUrl': 'https://images.unsplash.com/photo-1522869635100-9f4c5e86aa37?w=500&q=80',
    },
    {
      'label': 'ChatGPT',
      'provider': 'OpenAI',
      'name': 'ChatGPT Plus (GPT-4o)',
      'desc': 'Akun ChatGPT Plus resmi GPT-4o, DALL-E 3, Browsing, Voice Mode aktif.',
      'color': 0xFF10B981,
      'icon': Icons.smart_toy_rounded,
      'imageUrl': 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=500&q=80',
    },
    {
      'label': 'Spotify',
      'provider': 'Spotify',
      'name': 'Spotify Premium 3 Bulan',
      'desc': 'Akun Spotify Premium Individual 3 Bulan. No ads, offline download.',
      'color': 0xFF1DB954,
      'icon': Icons.music_note_rounded,
      'imageUrl': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80',
    },
    {
      'label': 'Google Pro',
      'provider': 'Google Official',
      'name': 'Google One / Pro 2TB',
      'desc': 'Akses Akun Google One 2TB + Gemini Advanced resmi bergaransi.',
      'color': 0xFF0284C7,
      'icon': Icons.cloud_done_rounded,
      'imageUrl': 'https://images.unsplash.com/photo-1573804633927-bfcbcd909acd?w=500&q=80',
    },
    {
      'label': 'Canva',
      'provider': 'Canva Official',
      'name': 'Canva Pro 1 Tahun',
      'desc': 'Lisensi Akun Canva Pro 1 Tahun. Brand Kit, background remover tanpa batas.',
      'color': 0xFF8B5CF6,
      'icon': Icons.brush_rounded,
      'imageUrl': 'https://images.unsplash.com/photo-1626785774573-4b799315345d?w=500&q=80',
    },
    {
      'label': 'YouTube',
      'provider': 'YouTube',
      'name': 'YouTube Premium 1 Bulan',
      'desc': 'YouTube Premium & Music bebas iklan, putar latar belakang HD.',
      'color': 0xFFE50914,
      'icon': Icons.play_circle_fill_rounded,
      'imageUrl': 'https://images.unsplash.com/photo-1611162617213-7d7a39e9b1d7?w=500&q=80',
    },
  ];

  final List<Map<String, dynamic>> _iconOptions = const [
    {'name': 'Akun', 'icon': Icons.account_circle_rounded},
    {'name': 'Film', 'icon': Icons.movie_filter_rounded},
    {'name': 'Musik', 'icon': Icons.music_note_rounded},
    {'name': 'Robot', 'icon': Icons.smart_toy_rounded},
    {'name': 'Cloud', 'icon': Icons.cloud_done_rounded},
    {'name': 'Desain', 'icon': Icons.brush_rounded},
    {'name': 'Bintang', 'icon': Icons.star_rounded},
    {'name': 'Kunci', 'icon': Icons.verified_user_rounded},
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.initialProduct;
    _nameController = TextEditingController(text: p?.name ?? '');
    _priceController = TextEditingController(text: p != null ? p.price.toInt().toString() : '');
    _providerController = TextEditingController(text: p?.provider ?? '');
    _descController = TextEditingController(text: p?.description ?? '');
    _stockController = TextEditingController(text: p != null ? p.stock.toString() : '15');
    _imageUrlController = TextEditingController(text: p?.imageUrl ?? '');

    _selectedColor = p?.colorHex ?? 0xFF06ACDC;
    _selectedIcon = p?.icon ?? Icons.account_circle_rounded;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _providerController.dispose();
    _descController.dispose();
    _stockController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  void _applyPreset(Map<String, dynamic> preset) {
    setState(() {
      _nameController.text = preset['name'];
      _providerController.text = preset['provider'];
      _descController.text = preset['desc'];
      _selectedColor = preset['color'];
      _selectedIcon = preset['icon'];
      _imageUrlController.text = preset['imageUrl'];
    });
  }

  void _saveProduct() {
    if (_formKey.currentState!.validate()) {
      final double price = double.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final int stock = int.tryParse(_stockController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 10;
      final String? imgUrl = _imageUrlController.text.trim().isNotEmpty ? _imageUrlController.text.trim() : null;

      final newProduct = ProductItem(
        id: widget.initialProduct?.id ?? 'acc_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim(),
        category: widget.initialProduct?.category ?? ProductCategory.streaming,
        price: price,
        provider: _providerController.text.trim().isEmpty ? 'DigiQ Store' : _providerController.text.trim(),
        description: _descController.text.trim().isEmpty ? 'Akun premium resmi bergaransi DigiQ. Pengiriman instan otomatis.' : _descController.text.trim(),
        stock: stock,
        isActive: widget.initialProduct?.isActive ?? true,
        icon: _selectedIcon,
        colorHex: _selectedColor,
        imageUrl: imgUrl,
      );

      widget.onProductAdded(newProduct);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialProduct != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isEdit ? Icons.edit_note_rounded : Icons.add_business_rounded,
                        color: AppColors.primaryDark,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Ubah Akun Digital' : 'Tambah Akun Digital',
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Katalog Penjualan Akun • DigiQ Admin',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const Divider(height: 22),

                // Quick Preset Chips
                const Text(
                  'Template Cepat Akun Populer:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickPresets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, idx) {
                      final item = _quickPresets[idx];
                      return ActionChip(
                        avatar: Icon(item['icon'], size: 14, color: Color(item['color'])),
                        label: Text(item['label'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        backgroundColor: AppColors.background,
                        side: const BorderSide(color: AppColors.cardBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onPressed: () => _applyPreset(item),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Image URL & Live Preview
                const Text(
                  'Gambar Akun / Produk (URL)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Preview thumbnail box
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Color(_selectedColor).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: _imageUrlController.text.trim().isNotEmpty
                            ? Image.network(
                                _imageUrlController.text.trim(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(_selectedIcon, color: Color(_selectedColor), size: 26),
                              )
                            : Icon(_selectedIcon, color: Color(_selectedColor), size: 26),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _imageUrlController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'https://images.unsplash.com/...',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Name field
                const Text(
                  'Nama Akun',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'Contoh: Netflix Premium 4K / ChatGPT Plus',
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama akun wajib diisi' : null,
                ),

                const SizedBox(height: 14),

                // Provider & Price & Stock Row
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Provider / Layanan',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _providerController,
                            decoration: const InputDecoration(
                              hintText: 'Netflix / OpenAI',
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Harga Jual (Rp)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '35000',
                              prefixText: 'Rp ',
                              isDense: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Harga wajib diisi';
                              if (double.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) == null) return 'Nominal salah';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stok Akun',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _stockController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '10',
                              suffixText: 'akun',
                              isDense: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Wajib';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Description
                const Text(
                  'Deskripsi & Spesifikasi Akun',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Contoh: Akun private 1 profile PIN khusus, 4K UHD, garansi 30 hari penuh.',
                    isDense: true,
                  ),
                ),

                const SizedBox(height: 14),

                // Choose Icon & Color
                const Text(
                  'Icon & Warna Kartu',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _iconOptions.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final item = _iconOptions[idx];
                      final IconData icon = item['icon'] as IconData;
                      final bool isSelected = _selectedIcon == icon;
                      return InkWell(
                        onTap: () => setState(() => _selectedIcon = icon),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 42,
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
                            size: 20,
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
                        width: 26,
                        height: 26,
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
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 22),

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
                        label: Text(isEdit ? 'Simpan Perubahan' : 'Tambahkan Akun'),
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
