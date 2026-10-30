// lib/services/product_service.dart

import 'dart:math' as math;
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
  /// Jika berhasil hard-delete dari tabel, bersihkan juga file gambar terkait dari storage.
  static Future<bool> deleteProduct(String productId, {String? imageUrl}) async {
    try {
      await _sb.from(_table).delete().eq('id', productId);
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await deleteStorageFile(imageUrl);
      }
      return true;
    } catch (_) {
      await setProductActive(productId, active: false);
      return false;
    }
  }

  /// Unggah gambar produk ke storage bucket 'product-images'.
  /// Menghapus file lama jika sebelumnya berada di bucket yang sama.
  /// Generate UUID v4 standar RFC 4122 tanpa dependensi eksternal
  static String generateUuidV4() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // RFC 4122 version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Menghapus file dari bucket 'product-images' berdasarkan public URL
  static Future<void> deleteStorageFile(String fileUrl) async {
    if (!fileUrl.contains('/product-images/')) return;
    try {
      final uri = Uri.parse(fileUrl);
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

  /// Unggah gambar produk ke storage bucket 'product-images' dengan path `products/<productId>/<random>.<ext>`.
  /// Menghapus file lama jika sebelumnya berada di bucket yang sama.
  static Future<String> uploadProductImage({
    required String productId,
    required Uint8List bytes,
    required String extension,
    required String mimeType,
    String? oldImageUrl,
  }) async {
    final ext = extension.toLowerCase().replaceAll('.', '');
    final randSuffix = 100000 + (math.Random.secure().nextInt(900000));
    final fileName = '$randSuffix.$ext';
    final filePath = 'products/$productId/$fileName';

    // Hapus file lama jika berada di bucket product-images
    if (oldImageUrl != null && oldImageUrl.contains('/product-images/')) {
      await deleteStorageFile(oldImageUrl);
    }

    await _sb.storage.from('product-images').uploadBinary(
      filePath,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: true),
    );

    final baseUrl = _sb.storage.from('product-images').getPublicUrl(filePath);
    return '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
