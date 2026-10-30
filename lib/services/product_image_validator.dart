// lib/services/product_image_validator.dart
// Validator untuk berkas gambar produk (JPG, PNG, WEBP, <= 2MB, magic bytes).

import 'dart:typed_data';

class ProductImageValidator {
  static const int maxBytes = 2 * 1024 * 1024; // 2 MB
  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  static bool isAllowedExtension(String ext) {
    return allowedExtensions.contains(ext.toLowerCase().replaceAll('.', ''));
  }

  static bool isSizeValid(int sizeInBytes) {
    return sizeInBytes > 0 && sizeInBytes <= maxBytes;
  }

  /// Verifikasi magic bytes biner asli:
  /// - JPEG: FF D8 FF
  /// - PNG:  89 50 4E 47 0D 0A 1A 0A
  /// - WEBP: 52 49 46 46 (RIFF) ... 57 45 42 50 (WEBP)
  /// Menolak SVG, XML, HTML, executable, dan file teks terselubung.
  static bool verifyMagicBytes(Uint8List bytes) {
    if (bytes.length < 12) return false;

    // PNG signature: 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }

    // JPEG signature: FF D8 FF
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }

    // WEBP signature: RIFF .... WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) { // P
      return true;
    }

    return false;
  }

  static String? validateFile({
    required String extension,
    required int sizeInBytes,
    required Uint8List bytes,
  }) {
    if (!isAllowedExtension(extension)) {
      return 'Format file tidak didukung. Gunakan JPG, PNG, atau WEBP.';
    }
    if (!isSizeValid(sizeInBytes)) {
      return 'Ukuran gambar maksimal 2 MB.';
    }
    if (!verifyMagicBytes(bytes)) {
      return 'Konten berkas tidak valid atau rusak (bukan JPG/PNG/WEBP asli).';
    }
    return null;
  }
}
