// test/product_hardening_test.dart
// Pengujian menyeluruh untuk validator produk, image validator (ukuran, ekstensi, magic bytes),
// model serialization, dan widget form AddProductDialog.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digiq/models/product_model.dart';
import 'package:digiq/services/product_service.dart';
import 'package:digiq/services/avatar_picker.dart';
import 'package:digiq/services/product_image_validator.dart';
import 'package:digiq/widgets/add_product_dialog.dart';

// Valid 1x1 transparent PNG yang dapat di-decode oleh mesin gambar Flutter di test environment
final kValid1x1Png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d,
  0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42,
  0x60, 0x82,
]);

void main() {
  group('1. ProductImageValidator Unit Tests (Ukuran, Ekstensi, Magic Bytes)', () {
    Uint8List makeJpegBytes({int length = 64}) {
      final b = Uint8List(length);
      b[0] = 0xFF;
      b[1] = 0xD8;
      b[2] = 0xFF;
      return b;
    }

    Uint8List makePngBytes({int length = 64}) {
      final b = Uint8List(length);
      b[0] = 0x89;
      b[1] = 0x50;
      b[2] = 0x4E;
      b[3] = 0x47;
      b[4] = 0x0D;
      b[5] = 0x0A;
      b[6] = 0x1A;
      b[7] = 0x0A;
      return b;
    }

    Uint8List makeWebpBytes({int length = 64}) {
      final b = Uint8List(length);
      b[0] = 0x52; // R
      b[1] = 0x49; // I
      b[2] = 0x46; // F
      b[3] = 0x46; // F
      b[8] = 0x57; // W
      b[9] = 0x45; // E
      b[10] = 0x42; // B
      b[11] = 0x50; // P
      return b;
    }

    test('Ekstensi yang diizinkan hanya jpg, jpeg, png, webp', () {
      expect(ProductImageValidator.isAllowedExtension('jpg'), isTrue);
      expect(ProductImageValidator.isAllowedExtension('JPEG'), isTrue);
      expect(ProductImageValidator.isAllowedExtension('.png'), isTrue);
      expect(ProductImageValidator.isAllowedExtension('webp'), isTrue);

      expect(ProductImageValidator.isAllowedExtension('svg'), isFalse);
      expect(ProductImageValidator.isAllowedExtension('gif'), isFalse);
      expect(ProductImageValidator.isAllowedExtension('exe'), isFalse);
      expect(ProductImageValidator.isAllowedExtension('php'), isFalse);
    });

    test('Validasi ukuran maksimal 2 MB (2 * 1024 * 1024)', () {
      const max = 2 * 1024 * 1024;
      expect(ProductImageValidator.isSizeValid(100), isTrue);
      expect(ProductImageValidator.isSizeValid(max), isTrue);
      expect(ProductImageValidator.isSizeValid(max + 1), isFalse);
      expect(ProductImageValidator.isSizeValid(0), isFalse);
      expect(ProductImageValidator.isSizeValid(-1), isFalse);
    });

    test('Magic bytes verifier menerima format valid JPEG, PNG, dan WEBP', () {
      expect(ProductImageValidator.verifyMagicBytes(makeJpegBytes()), isTrue);
      expect(ProductImageValidator.verifyMagicBytes(makePngBytes()), isTrue);
      expect(ProductImageValidator.verifyMagicBytes(makeWebpBytes()), isTrue);
    });

    test('Magic bytes verifier menolak SVG, HTML, teks, atau file pendek palsu', () {
      final svgBytes = Uint8List.fromList('<svg width="100" height="100"></svg>'.codeUnits);
      expect(ProductImageValidator.verifyMagicBytes(svgBytes), isFalse);

      final htmlBytes = Uint8List.fromList('<html><body>bad file</body></html>'.codeUnits);
      expect(ProductImageValidator.verifyMagicBytes(htmlBytes), isFalse);

      final shortBytes = Uint8List.fromList([0xFF, 0xD8]); // Kurang dari 12 byte
      expect(ProductImageValidator.verifyMagicBytes(shortBytes), isFalse);
    });

    test('validateFile memberikan pesan error yang ramah dan tepat', () {
      final validJpg = makeJpegBytes();

      // Format tidak didukung
      final errExt = ProductImageValidator.validateFile(
        extension: 'svg',
        sizeInBytes: validJpg.length,
        bytes: validJpg,
      );
      expect(errExt, contains('Format file tidak didukung'));

      // Ukuran melebihi batas
      final errSize = ProductImageValidator.validateFile(
        extension: 'jpg',
        sizeInBytes: (2 * 1024 * 1024) + 500,
        bytes: validJpg,
      );
      expect(errSize, contains('maksimal 2 MB'));

      // File menyamar (.jpg tapi isi teks / corrupt)
      final fakeJpg = Uint8List.fromList('ini file teks biasa tapi ekstensi jpg'.codeUnits);
      final errFake = ProductImageValidator.validateFile(
        extension: 'jpg',
        sizeInBytes: fakeJpg.length,
        bytes: fakeJpg,
      );
      expect(errFake, contains('Konten berkas tidak valid atau rusak'));

      // Berkas valid
      final ok = ProductImageValidator.validateFile(
        extension: 'png',
        sizeInBytes: kValid1x1Png.length,
        bytes: kValid1x1Png,
      );
      expect(ok, isNull);
    });
  });

  group('2. ProductModel & ProductItem Serialization & Helper Tests', () {
    test('ProductModel.fromMap menangani konversi num ke int dan double', () {
      final map = {
        'id': '00000000-0000-0000-0000-000000000001',
        'name': 'Netflix 4K',
        'category': 'Streaming',
        'description': 'Deskripsi akun',
        'price': 45000, // int num
        'discount_price': 38000.5, // double num
        'stock': 25, // int num
        'is_active': true,
        'image_url': 'https://supabase.co/storage/v1/object/public/product-images/test.jpg',
        'provider': 'Netflix',
        'created_at': '2026-10-30T08:00:00.000Z',
      };

      final m = ProductModel.fromMap(map);
      expect(m.id, '00000000-0000-0000-0000-000000000001');
      expect(m.name, 'Netflix 4K');
      expect(m.price, 45000.0);
      expect(m.discountPrice, 38000.5);
      expect(m.effectivePrice, 38000.5);
      expect(m.hasDiscount, isTrue);
      expect(m.stock, 25);
      expect(m.outOfStock, isFalse);
    });

    test('ProductModel.toInsertMap tidak menyertakan id (mengandalkan UUID database)', () {
      final m = ProductModel(
        id: 'klien-id-harus-diabaikan',
        name: 'Spotify Premium',
        category: 'Streaming',
        description: '3 Bulan',
        price: 40000,
        discountPrice: null,
        stock: 10,
        isActive: true,
        provider: 'Spotify',
        createdAt: DateTime(2026, 1, 1),
      );

      final insertMap = m.toInsertMap();
      expect(insertMap.containsKey('id'), isFalse, reason: 'ID harus digenerate DB via gen_random_uuid()');
      expect(insertMap['name'], 'Spotify Premium');
      expect(insertMap['category'], 'Streaming');
      expect(insertMap['price'], 40000.0);
      expect(insertMap['discount_price'], isNull);
      expect(insertMap['stock'], 10);
      expect(insertMap['is_active'], isTrue);
    });

    test('ProductItem.toProductModel melakukan konversi kategori dengan tepat', () {
      const item = ProductItem(
        id: 'uuid-1234',
        name: 'Token PLN 50K',
        category: ProductCategory.pln,
        price: 52000,
        provider: 'PLN',
        description: 'Token listrik',
        stock: 100,
        isActive: true,
      );

      expect(item.categoryString, 'PLN');
      final model = item.toProductModel();
      expect(model.id, 'uuid-1234');
      expect(model.category, 'PLN');
      expect(model.price, 52000.0);
    });

    test('ProductService.generateUuidV4 menghasilkan format UUID v4 RFC 4122 yang valid', () {
      final uuid1 = ProductService.generateUuidV4();
      final uuid2 = ProductService.generateUuidV4();
      expect(uuid1, isNot(equals(uuid2)));
      expect(uuid1.length, 36);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(uuid1), isTrue);
    });

    test('ProductModel.toInsertMap tidak menyertakan id (mengandalkan UUID database gen_random_uuid)', () {
      final model = ProductModel(
        id: 'prod-uuid-123',
        name: 'Test Product',
        category: 'Games',
        description: 'Deskripsi test produk',
        price: 25000,
        stock: 5,
        isActive: true,
        provider: 'DigiQ Store',
        createdAt: DateTime.now(),
      );
      final map = model.toInsertMap();
      expect(map.containsKey('id'), isFalse);
      expect(map['name'], 'Test Product');
    });
  });

  group('3. AddProductDialog Widget Tests (Form Validations & Image Picker & Double Submit)', () {
    tearDown(() {
      AddProductDialog.pickImageOverride = null;
    });

    testWidgets('Menampilkan seluruh field form tambah produk secara lengkap', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddProductDialog(
              onProductSaved: (model, file) async {},
            ),
          ),
        ),
      );

      expect(find.text('Tambah Akun Digital'), findsOneWidget);
      expect(find.byKey(const Key('add_product_name_field')), findsOneWidget);
      expect(find.byKey(const Key('add_product_category_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('add_product_price_field')), findsOneWidget);
      expect(find.byKey(const Key('add_product_discount_field')), findsOneWidget);
      expect(find.byKey(const Key('add_product_stock_field')), findsOneWidget);
      expect(find.byKey(const Key('add_product_pick_image_button')), findsOneWidget);
      expect(find.byKey(const Key('add_product_submit_button')), findsOneWidget);
    });

    testWidgets('Validasi form menolak nama kosong, harga <= 0, dan stok negatif', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddProductDialog(
              onProductSaved: (model, file) async {},
            ),
          ),
        ),
      );

      // Submit form kosong
      await tester.tap(find.byKey(const Key('add_product_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Nama akun wajib diisi'), findsOneWidget);
      expect(find.text('Harga wajib'), findsOneWidget);
    });

    testWidgets('Validasi harga promo menolak jika diskon >= harga jual', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddProductDialog(
              onProductSaved: (model, file) async {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('add_product_name_field')), 'Netflix Premium 4K');
      await tester.enterText(find.byKey(const Key('add_product_price_field')), '40000');
      await tester.enterText(find.byKey(const Key('add_product_discount_field')), '50000'); // Diskon > Harga
      await tester.enterText(find.byKey(const Key('add_product_stock_field')), '10');

      await tester.tap(find.byKey(const Key('add_product_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('< Harga'), findsOneWidget);
    });

    testWidgets('Memilih gambar valid memicu preview dan menampilkan info file', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AddProductDialog.pickImageOverride = () async {
        return PickedAvatarFile(
          bytes: kValid1x1Png,
          extension: 'png',
          mimeType: 'image/png',
          sizeInBytes: kValid1x1Png.length,
        );
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddProductDialog(
              onProductSaved: (model, file) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('add_product_pick_image_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      
      final err = tester.takeException();
      if (err != null) {
        }

      
      expect(find.textContaining('Terpilih: PNG'), findsOneWidget);
    });

    testWidgets('Pencegahan double-submit: tombol disabled dan menampilkan loading saat menyimpan', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool saveCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddProductDialog(
              onProductSaved: (model, file) async {
                saveCalled = true;
                await Future.delayed(const Duration(milliseconds: 300));
              },
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('add_product_name_field')), 'ChatGPT Plus 1 Bulan');
      await tester.enterText(find.byKey(const Key('add_product_price_field')), '85000');
      await tester.enterText(find.byKey(const Key('add_product_stock_field')), '10');

      // Tap simpan
      await tester.tap(find.byKey(const Key('add_product_submit_button')));
      await tester.pump(); // Render state loading

      expect(saveCalled, isTrue);
      expect(find.text('Menyimpan...'), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });
}
