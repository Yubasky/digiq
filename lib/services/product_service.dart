// lib/services/product_service.dart

import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import '../models/product_model.dart';

class ProductService {
  static SupabaseClient get _sb => SupabaseConfig.supabase;

  static const _table = 'products';

  // ─── Stream Realtime ────────────────────────────────────────────────────────

  /// Stream produk aktif (untuk customer). Filter is_active=true di server via RLS.
  /// Admin mendapatkan semua produk karena RLS admin policy mengembalikan semua.
  static Stream<List<ProductModel>> watchProducts({bool activeOnly = true}) {
    return _sb
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) {
          var list = rows.map((r) => ProductModel.fromMap(r)).toList();
          if (activeOnly) {
            list = list.where((p) => p.isActive).toList();
          }
          return list;
        });
  }

  // ─── Admin: CRUD ────────────────────────────────────────────────────────────

  /// Tambah produk baru. RLS menjamin hanya admin aal2 yang bisa.
  static Future<ProductModel> addProduct(ProductModel product) async {
    final data = await _sb
        .from(_table)
        .insert(product.toInsertMap())
        .select()
        .single();
    return ProductModel.fromMap(data);
  }

  /// Update produk. RLS menjamin hanya admin aal2 yang bisa.
  static Future<ProductModel> updateProduct(ProductModel product) async {
    final data = await _sb
        .from(_table)
        .update(product.toUpdateMap())
        .eq('id', product.id)
        .select()
        .single();
    return ProductModel.fromMap(data);
  }

  /// Update stok saja.
  static Future<void> updateProductStock(String productId, int newStock) async {
    await _sb
        .from(_table)
        .update({'stock': newStock})
        .eq('id', productId);
  }

  /// Soft-delete: set is_active=false. Tidak benar-benar menghapus.
  static Future<void> setProductActive(String productId, {required bool active}) async {
    await _sb
        .from(_table)
        .update({'is_active': active})
        .eq('id', productId);
  }

  /// Ambil satu produk by ID (one-shot, bukan stream).
  static Future<ProductModel?> getProduct(String productId) async {
    try {
      final data = await _sb
          .from(_table)
          .select()
          .eq('id', productId)
          .single();
      return ProductModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Hapus produk. Bila gagal karena transaksi terkait (FK 23503), otomatis fallback ke soft-delete.
  static Future<bool> deleteProduct(String productId) async {
    try {
      await _sb.from(_table).delete().eq('id', productId);
      return true;
    } catch (_) {
      await setProductActive(productId, active: false);
      return false;
    }
  }

  /// Unggah gambar produk ke storage bucket 'product-images'.
  /// Menghapus file lama jika sebelumnya berada di bucket yang sama.
  static Future<String> uploadProductImage({
    required Uint8List bytes,
    required String extension,
    required String mimeType,
    String? oldImageUrl,
  }) async {
    final ext = extension.toLowerCase().replaceAll('.', '');
    final randSuffix = 1000 + (DateTime.now().microsecond % 9000);
    final fileName = 'prod_' + DateTime.now().millisecondsSinceEpoch.toString() + '_' + randSuffix.toString() + '.' + ext;
    final filePath = 'products/' + fileName;

    // Hapus file lama jika berada di bucket product-images
    if (oldImageUrl != null && oldImageUrl.contains('/product-images/')) {
      try {
        final uri = Uri.parse(oldImageUrl);
        final segments = uri.pathSegments;
        final idx = segments.indexOf('product-images');
        if (idx != -1 && idx + 1 < segments.length) {
          final oldPath = segments.sublist(idx + 1).join('/');
          if (oldPath.isNotEmpty) {
            await _sb.storage.from('product-images').remove([oldPath]);
          }
        }
      } catch (_) {}
    }

    await _sb.storage.from('product-images').uploadBinary(
      filePath,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: true),
    );

    final baseUrl = _sb.storage.from('product-images').getPublicUrl(filePath);
    return baseUrl + '?v=' + DateTime.now().millisecondsSinceEpoch.toString();
  }
}
