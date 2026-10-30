// lib/widgets/add_product_dialog.dart
// Dialog Tambah/Ubah Produk Digital dengan validasi ketat, Dropdown kategori DB,
// upload gambar (Opsi A - JPG/PNG/WEBP maks 2MB & magic bytes), dan proteksi double submit.

import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/avatar_picker.dart';
import '../services/product_image_validator.dart';
import '../services/product_service.dart';
import '../theme/app_theme.dart';

class AddProductDialog extends StatefulWidget {
  final Future<void> Function(ProductModel newProduct, PickedAvatarFile? imageFile)? onProductSaved;
  final Function(ProductItem newProduct)? onProductAdded;
  final ProductItem? initialProduct;

  @visibleForTesting
  static Future<PickedAvatarFile?> Function()? pickImageOverride;

  const AddProductDialog({
    super.key,
    this.onProductSaved,
    this.onProductAdded,
    this.initialProduct,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _discountPriceController;
  late final TextEditingController _providerController;
  late final TextEditingController _descController;
  late final TextEditingController _stockController;
  late final TextEditingController _imageUrlController;

  static const List<String> _allowedCategories = [
    'Streaming',
    'Games',
    'Pulsa',
    'PLN',
    'E-Wallet',
  ];

  late String _selectedCategory;
  late int _selectedColor;
  late IconData _selectedIcon;

  PickedAvatarFile? _pickedImage;
  String? _imageError;
  bool _isSubmitting = false;

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
      'category': 'Streaming',
      'name': 'Netflix Premium 4K UHD',
      'desc': 'Akun Netflix 1 Profile Private (PIN Khusus). 4K Ultra HD, semua perangkat.',
      'color': 0xFFE50914,
      'icon': Icons.movie_filter_rounded,
      'price': '45000',
      'stock': '25',
    },
    {
      'label': 'ChatGPT',
      'provider': 'OpenAI',
      'category': 'Streaming',
      'name': 'ChatGPT Plus (GPT-4o)',
      'desc': 'Akun ChatGPT Plus resmi GPT-4o, DALL-E 3, Browsing, Voice Mode aktif.',
      'color': 0xFF10B981,
      'icon': Icons.smart_toy_rounded,
      'price': '85000',
      'stock': '15',
    },
    {
      'label': 'Spotify',
      'provider': 'Spotify',
      'category': 'Streaming',
      'name': 'Spotify Premium 3 Bulan',
      'desc': 'Akun Spotify Premium Individual 3 Bulan. No ads, offline download.',
      'color': 0xFF1DB954,
      'icon': Icons.music_note_rounded,
      'price': '40000',
      'stock': '30',
    },
    {
      'label': 'Google Pro',
      'provider': 'Google Official',
      'category': 'Streaming',
      'name': 'Google One / Pro 2TB',
      'desc': 'Akses Akun Google One 2TB + Gemini Advanced resmi bergaransi.',
      'color': 0xFF0284C7,
      'icon': Icons.cloud_done_rounded,
      'price': '60000',
      'stock': '20',
    },
    {
      'label': 'Canva',
      'provider': 'Canva Official',
      'category': 'Streaming',
      'name': 'Canva Pro 1 Tahun',
      'desc': 'Lisensi Akun Canva Pro 1 Tahun. Brand Kit, background remover tanpa batas.',
      'color': 0xFF8B5CF6,
      'icon': Icons.brush_rounded,
      'price': '50000',
      'stock': '20',
    },
    {
      'label': 'YouTube',
      'provider': 'YouTube',
      'category': 'Streaming',
      'name': 'YouTube Premium 1 Bulan',
      'desc': 'YouTube Premium & Music bebas iklan, putar latar belakang HD.',
      'color': 0xFFE50914,
      'icon': Icons.play_circle_fill_rounded,
      'price': '35000',
      'stock': '20',
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
    _discountPriceController = TextEditingController();
    _providerController = TextEditingController(text: p?.provider ?? '');
    _descController = TextEditingController(text: p?.description ?? '');
    _stockController = TextEditingController(text: p != null ? p.stock.toString() : '15');
    _imageUrlController = TextEditingController(text: p?.imageUrl ?? '');

    String initCat = 'Streaming';
    if (p != null) {
      final s = p.categoryString;
      if (_allowedCategories.contains(s)) {
        initCat = s;
      }
    }
    _selectedCategory = initCat;

    _selectedColor = p?.colorHex ?? 0xFF06ACDC;
    _selectedIcon = p?.icon ?? Icons.account_circle_rounded;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _discountPriceController.dispose();
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
      _priceController.text = preset['price'];
      _stockController.text = preset['stock'];
      if (_allowedCategories.contains(preset['category'])) {
        _selectedCategory = preset['category'];
      }
    });
  }

  Future<void> _pickImage() async {
    try {
      final file = AddProductDialog.pickImageOverride != null
          ? await AddProductDialog.pickImageOverride!()
          : await pickAvatarImage();

      if (file == null) return;

      final validationErr = ProductImageValidator.validateFile(
        extension: file.extension,
        sizeInBytes: file.sizeInBytes,
        bytes: file.bytes,
      );

      if (validationErr != null) {
        setState(() => _imageError = validationErr);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(validationErr),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      setState(() {
        _pickedImage = file;
        _imageError = null;
      });
    } catch (_) {
      setState(() => _imageError = 'Gagal memilih gambar.');
    }
  }

  Future<void> _saveProduct() async {
    if (_isSubmitting) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final double price = double.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final int stock = int.tryParse(_stockController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    double? discountPrice;
    final discRaw = _discountPriceController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (discRaw.isNotEmpty) {
      discountPrice = double.tryParse(discRaw);
    }

    final String? imgUrl = _imageUrlController.text.trim().isNotEmpty ? _imageUrlController.text.trim() : null;

    // Buat model produk dengan UUID konsisten
    final String prodId = (widget.initialProduct != null && widget.initialProduct!.id.isNotEmpty)
        ? widget.initialProduct!.id
        : ProductService.generateUuidV4();

    final productModel = ProductModel(
      id: prodId,
      name: _nameController.text.trim(),
      category: _selectedCategory,
      description: _descController.text.trim().isEmpty
          ? 'Akun premium resmi bergaransi DigiQ. Pengiriman instan otomatis.'
          : _descController.text.trim(),
      price: price,
      discountPrice: discountPrice,
      stock: stock,
      isActive: widget.initialProduct?.isActive ?? true,
      imageUrl: imgUrl,
      provider: _providerController.text.trim().isEmpty ? 'DigiQ Store' : _providerController.text.trim(),
      createdAt: DateTime.now(),
    );

    setState(() => _isSubmitting = true);

    try {
      if (widget.onProductSaved != null) {
        await widget.onProductSaved!(productModel, _pickedImage);
      } else if (widget.onProductAdded != null) {
        // Fallback untuk kompabilitas
        final item = ProductItem.fromProductModel(productModel).copyWith(
          colorHex: _selectedColor,
          icon: _selectedIcon,
        );
        widget.onProductAdded!(item);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan akun: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
        constraints: const BoxConstraints(maxWidth: 500),
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
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const Divider(height: 22),

                // Quick Preset Chips (hanya saat tambah produk baru)
                if (!isEdit) ...[
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
                          onPressed: _isSubmitting ? null : () => _applyPreset(item),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Gambar Produk (Opsi A - Upload Berkas ke Storage)
                const Text(
                  'Foto / Logo Produk',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Preview box
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Color(_selectedColor).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: _pickedImage != null
                            ? Image.memory(
                                _pickedImage!.bytes,
                                fit: BoxFit.cover,
                              )
                            : (_imageUrlController.text.trim().isNotEmpty
                                ? Image.network(
                                    _imageUrlController.text.trim(),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Icon(_selectedIcon, color: Color(_selectedColor), size: 28),
                                  )
                                : Icon(_selectedIcon, color: Color(_selectedColor), size: 28)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            key: const Key('add_product_pick_image_button'),
                            onPressed: _isSubmitting ? null : _pickImage,
                            icon: const Icon(Icons.upload_file_rounded, size: 16),
                            label: Text(_pickedImage != null ? 'Ganti Berkas Foto' : 'Unggah Foto (Maks 2MB)'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _pickedImage != null
                                ? '✓ Terpilih: ${_pickedImage!.extension.toUpperCase()} (${(_pickedImage!.sizeInBytes / 1024).toStringAsFixed(1)} KB)'
                                : 'Format: JPG, PNG, WEBP (maks 2 MB)',
                            style: TextStyle(
                              fontSize: 11,
                              color: _pickedImage != null ? AppColors.success : AppColors.textSecondary,
                              fontWeight: _pickedImage != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (_imageError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _imageError!,
                                style: const TextStyle(fontSize: 11, color: AppColors.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Nama Akun field
                const Text(
                  'Nama Akun *',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('add_product_name_field'),
                  controller: _nameController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    hintText: 'Contoh: Netflix Premium 4K / ChatGPT Plus',
                    isDense: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Nama akun wajib diisi';
                    if (v.trim().length < 3) return 'Nama akun minimal 3 karakter';
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // Kategori & Provider Row
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Kategori *',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            key: const Key('add_product_category_dropdown'),
                            initialValue: _selectedCategory,
                            isDense: true,
                            decoration: const InputDecoration(isDense: true),
                            items: _allowedCategories.map((c) {
                              return DropdownMenuItem<String>(
                                value: c,
                                child: Text(c, style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: _isSubmitting
                                ? null
                                : (val) {
                                    if (val != null) setState(() => _selectedCategory = val);
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
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
                            enabled: !_isSubmitting,
                            decoration: const InputDecoration(
                              hintText: 'Netflix / OpenAI',
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Harga Jual & Harga Diskon & Stok Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Harga Jual (Rp) *',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            key: const Key('add_product_price_field'),
                            controller: _priceController,
                            enabled: !_isSubmitting,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '35000',
                              prefixText: 'Rp ',
                              isDense: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Harga wajib';
                              final numVal = double.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
                              if (numVal == null || numVal <= 0) return '> 0';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Harga Promo (Rp)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            key: const Key('add_product_discount_field'),
                            controller: _discountPriceController,
                            enabled: !_isSubmitting,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'Opsional',
                              prefixText: 'Rp ',
                              isDense: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final disc = double.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
                              final price = double.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                              if (disc == null) return 'Salah';
                              if (disc >= price) return '< Harga';
                              if (disc < 0) return '>= 0';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stok *',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            key: const Key('add_product_stock_field'),
                            controller: _stockController,
                            enabled: !_isSubmitting,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '10',
                              isDense: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Wajib';
                              final s = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
                              if (s == null || s < 0) return '>= 0';
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
                  enabled: !_isSubmitting,
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
                        onTap: _isSubmitting ? null : () => setState(() => _selectedIcon = icon),
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
                      onTap: _isSubmitting ? null : () => setState(() => _selectedColor = colorHex),
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
                        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        key: const Key('add_product_submit_button'),
                        onPressed: _isSubmitting ? null : _saveProduct,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          _isSubmitting
                              ? 'Menyimpan...'
                              : (isEdit ? 'Simpan Perubahan' : 'Tambahkan Akun'),
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
    );
  }
}
