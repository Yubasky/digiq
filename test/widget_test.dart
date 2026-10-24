import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digiq/main.dart';

void main() {
  testWidgets('DigiQ dashboard and AddProductDialog mobile layout test', (WidgetTester tester) async {
    // Set typical mobile screen size (360x740)
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const DigiQApp());
    await tester.pumpAndSettle();

    // Verify header and bottom navigation items are visible
    expect(find.text('DigiQ Store'), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Katalog'), findsOneWidget);
    expect(find.text('Transaksi'), findsOneWidget);
    expect(find.text('Toko Admin'), findsOneWidget);

    // Tap on FAB to open AddProductDialog
    final fabFinder = find.byType(FloatingActionButton);
    expect(fabFinder, findsOneWidget);
    await tester.tap(fabFinder);
    await tester.pumpAndSettle();

    // Verify AddProductDialog renders without overflow
    expect(find.text('Tambah Produk Digital'), findsOneWidget);
    expect(find.text('Mode Admin • Katalog Toko'), findsOneWidget);
    expect(find.text('Simpan Produk'), findsOneWidget);

    // Close dialog
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Tambah Produk Digital'), findsNothing);
  });
}
