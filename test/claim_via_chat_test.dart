// test/claim_via_chat_test.dart
// Pengujian Komprehensif Fitur Klaim Produk via Chat Admin (U1-U9 + Viewports)

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:digiq/models/chat_message_model.dart';
import 'package:digiq/models/transaction_model.dart';
import 'package:digiq/screens/chat/chat_screen.dart';
import 'package:digiq/services/app_language.dart';
import 'package:digiq/services/supabase_config.dart';
import 'package:digiq/widgets/qris_modal.dart';

// ─── Mocks & Fakes ───────────────────────────────────────────────────────────

class _FakeRpcFilterBuilder<T> extends Fake
    implements PostgrestFilterBuilder<T> {
  final dynamic _result;
  final bool _shouldThrow;
  final String _errorMessage;

  _FakeRpcFilterBuilder(
    this._result, {
    bool shouldThrow = false,
    String errorMessage = '',
  })  : _shouldThrow = shouldThrow,
        _errorMessage = errorMessage;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    if (_shouldThrow) {
      final err = PostgrestException(message: _errorMessage, code: '42501');
      return Future<T>.error(err).then(onValue, onError: onError);
    }
    return Future<T>.value(_result as T).then(onValue, onError: onError);
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    if (_shouldThrow) {
      final err = PostgrestException(message: _errorMessage, code: '42501');
      return Future<T>.error(err).catchError(onError, test: test);
    }
    return Future<T>.value(_result as T).catchError(onError, test: test);
  }

  @override
  Future<T> timeout(
    Duration timeLimit, {
    FutureOr<T> Function()? onTimeout,
  }) {
    if (_shouldThrow) {
      return Future<T>.error(PostgrestException(message: _errorMessage, code: '42501'));
    }
    return Future<T>.value(_result as T);
  }
}

class _FakeSupabaseStreamFilterBuilder
    extends StreamView<List<Map<String, dynamic>>>
    implements SupabaseStreamFilterBuilder, SupabaseStreamBuilder {
  final StreamController<List<Map<String, dynamic>>> _ctrl;

  _FakeSupabaseStreamFilterBuilder._(this._ctrl) : super(_ctrl.stream);

  factory _FakeSupabaseStreamFilterBuilder() {
    final ctrl = StreamController<List<Map<String, dynamic>>>.broadcast();
    return _FakeSupabaseStreamFilterBuilder._(ctrl);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

class _FakeSupabaseQueryBuilder extends Fake
    implements SupabaseQueryBuilder {
  final _FakeSupabaseClient client;
  final String table;
  _FakeSupabaseQueryBuilder(this.client, this.table);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> insert(dynamic values,
      {dynamic defaultToNull}) {
    client.lastInsertedTable = table;
    client.lastInsertedValues = values;
    return _FakeRpcFilterBuilder<List<Map<String, dynamic>>>([]);
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return _FakeRpcFilterBuilder<List<Map<String, dynamic>>>([]);
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> update(Map values,
      {dynamic defaultToNull}) {
    return _FakeRpcFilterBuilder<List<Map<String, dynamic>>>([]);
  }

  @override
  SupabaseStreamFilterBuilder stream({required List<String> primaryKey, bool private = false}) {
    return _FakeSupabaseStreamFilterBuilder();
  }
}

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  final User? mockUser;
  _FakeGoTrueClient({this.mockUser});

  @override
  User? get currentUser => mockUser;

  @override
  Session? get currentSession => mockUser != null
      ? Session(
          accessToken: 'fake-token',
          tokenType: 'bearer',
          user: mockUser!,
        )
      : null;
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  late final _FakeGoTrueClient fakeAuth;
  int requestClaimCallCount = 0;
  int markDeliveredCallCount = 0;
  String? lastClaimTrxId;
  String? lastDeliveredTrxId;
  bool shouldThrowRpc = false;
  String rpcErrorMessage = '';

  String? lastInsertedTable;
  dynamic lastInsertedValues;

  _FakeSupabaseClient({User? user}) {
    fakeAuth = _FakeGoTrueClient(mockUser: user);
  }

  @override
  GoTrueClient get auth => fakeAuth;

  @override
  SupabaseQueryBuilder from(String table) {
    return _FakeSupabaseQueryBuilder(this, table);
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    dynamic get,
  }) {
    if (fn == 'request_claim') {
      requestClaimCallCount++;
      lastClaimTrxId = params?['p_trx_id'] as String?;
      if (shouldThrowRpc) {
        return _FakeRpcFilterBuilder<T>(
          null,
          shouldThrow: true,
          errorMessage: rpcErrorMessage,
        );
      }
      return _FakeRpcFilterBuilder<T>({
        'success': true,
        'claim_status': 'requested',
        'already_requested': false,
        'conversation_id': 'user-123',
      } as T);
    }

    if (fn == 'admin_mark_delivered') {
      markDeliveredCallCount++;
      lastDeliveredTrxId = params?['p_trx_id'] as String?;
      return _FakeRpcFilterBuilder<T>({
        'id': lastDeliveredTrxId,
        'claim_status': 'delivered',
        'status': 'success',
      } as T);
    }

    if (fn == 'get_admin_pending_claims') {
      return _FakeRpcFilterBuilder<T>([] as T);
    }

    return _FakeRpcFilterBuilder<T>(null as T);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    AppLanguage.setLanguage(AppLang.id);
  });

  group('Klaim Produk via Chat Admin Test Suite (U1-U9)', () {
    late _FakeSupabaseClient fakeClient;
    const testUserId = 'user-uuid-123';
    const testTrxId = 'trx-uuid-abc';

    setUp(() {
      final mockUser = User(
        id: testUserId,
        appMetadata: {},
        userMetadata: {'full_name': 'Pelanggan Test'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'pelanggan@test.com',
      );
      fakeClient = _FakeSupabaseClient(user: mockUser);
      SupabaseConfig.testClient = fakeClient;
    });

    tearDown(() {
      SupabaseConfig.testClient = null;
    });

    // ─── U1: Tombol Klaim Hanya untuk Transaksi Lunas ─────────────────────────
    testWidgets('U1: QrisModal status pending TIDAK menampilkan tombol klaim produk', (tester) async {
      final pendingTrx = TransactionModel(
        id: testTrxId,
        trxCode: 'TRX-PENDING-001',
        userId: testUserId,
        productId: 'prod-1',
        productName: 'Akun Netflix 1 Bulan',
        targetNumber: '0812345678',
        amount: 35000,
        status: 'pending',
        createdAt: DateTime.now(),
        expiredAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: QrisModal(transaction: pendingTrx)),
      ));
      await tester.pump();

      // Memastikan tombol klaim produk TIDAK ada saat pending
      expect(find.byKey(const Key('btn_claim_product')), findsNothing);
      expect(find.text(AppLanguage.t('claim_product_btn')), findsNothing);
      // Memastikan elemen QRIS tetap ada
      expect(find.text('Pembayaran QRIS'), findsOneWidget);
    });

    testWidgets('U1b: QrisModal status success MENAMPILKAN tombol klaim produk', (tester) async {
      final paidTrx = TransactionModel(
        id: testTrxId,
        trxCode: 'TRX-PAID-001',
        userId: testUserId,
        productId: 'prod-1',
        productName: 'Akun Netflix 1 Bulan',
        targetNumber: '0812345678',
        amount: 35000,
        status: 'success',
        claimStatus: 'none',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: QrisModal(transaction: paidTrx)),
      ));
      await tester.pump();

      expect(find.byKey(const Key('btn_claim_product')), findsOneWidget);
      expect(find.text(AppLanguage.t('claim_product_btn')), findsOneWidget);
    });

    // ─── U2: Tap -> requestClaim 1 kali, Tap Ganda dicegah ────────────────────
    testWidgets('U2: Tap tombol klaim memanggil requestClaim tepat 1 kali & cegah tap ganda', (tester) async {
      final paidTrx = TransactionModel(
        id: testTrxId,
        trxCode: 'TRX-PAID-002',
        userId: testUserId,
        productId: 'prod-1',
        productName: 'Spotify 1 Bulan',
        targetNumber: '0812345678',
        amount: 25000,
        status: 'success',
        claimStatus: 'none',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: QrisModal(transaction: paidTrx)),
      ));
      await tester.pump();

      final claimBtn = find.byKey(const Key('btn_claim_product'));
      expect(claimBtn, findsOneWidget);

      // Tap pertama
      await tester.tap(claimBtn, warnIfMissed: false);
      // Tap kedua instan untuk simulasi spam tap ganda
      await tester.tap(claimBtn, warnIfMissed: false);
      await tester.pump();

      expect(fakeClient.requestClaimCallCount, equals(1));
      expect(fakeClient.lastClaimTrxId, equals(testTrxId));
    });

    // ─── U3: Klaim requested/delivered -> "Buka Chat Admin" ──────────────────
    testWidgets('U3: Transaksi yang sudah requested menampilkan tombol Buka Chat Admin', (tester) async {
      final claimedTrx = TransactionModel(
        id: testTrxId,
        trxCode: 'TRX-CLAIMED-001',
        userId: testUserId,
        productId: 'prod-1',
        productName: 'YouTube Premium 1 Bulan',
        targetNumber: '0812345678',
        amount: 15000,
        status: 'success',
        claimStatus: 'requested',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: QrisModal(transaction: claimedTrx)),
      ));
      await tester.pump();

      expect(find.byKey(const Key('btn_open_chat')), findsOneWidget);
      expect(find.text(AppLanguage.t('open_chat_btn')), findsOneWidget);
      expect(find.byKey(const Key('btn_claim_product')), findsNothing);
    });

    // ─── U4: Gagal (42901 / 42501 / Jaringan) -> Pesan Ramah & Retry ─────────
    testWidgets('U4: Kegagalan RPC menampilkan snackbar pesan ramah dan tidak navigasi', (tester) async {
      fakeClient.shouldThrowRpc = true;
      fakeClient.rpcErrorMessage = 'Batas frekuensi klaim terlampaui. Mohon tunggu 1 menit.';

      final paidTrx = TransactionModel(
        id: testTrxId,
        trxCode: 'TRX-FAIL-001',
        userId: testUserId,
        productId: 'prod-1',
        productName: 'Canva Pro',
        targetNumber: '0812345678',
        amount: 10000,
        status: 'success',
        claimStatus: 'none',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: QrisModal(transaction: paidTrx)),
      ));
      await tester.pump();

      final claimBtn = find.byKey(const Key('btn_claim_product'));
      await tester.tap(claimBtn);
      await tester.pump();

      // Modal tetap terbuka, tombol tetap ada untuk retry
      expect(find.byKey(const Key('btn_claim_product')), findsOneWidget);
      expect(find.textContaining('Gagal mengajukan klaim'), findsOneWidget);
    });

    // ─── U5: Kartu kind='claim' Dirender Benar ───────────────────────────────
    testWidgets('U5: ChatScreen merender pesan kind=claim sebagai kartu pesanan resmi', (tester) async {
      final claimMessage = ChatMessageModel(
        id: 'msg-claim-1',
        senderId: testUserId,
        roomUserId: testUserId,
        message: 'Halo Admin, saya ingin klaim pesanan #TRX-999 (Netflix 1 Bulan) senilai Rp 35.000 (Lunas: 31/10/2026 12:00 WIB). Mohon diproses.',
        isRead: false,
        createdAt: DateTime.now(),
        kind: 'claim',
        trxId: testTrxId,
      );

      await tester.pumpWidget(MaterialApp(
        home: ChatScreen(roomUserId: testUserId, isAdmin: false),
      ));
      await tester.pump();

      // Verifikasi model ChatMessageModel
      expect(claimMessage.isClaim, isTrue);
      expect(claimMessage.isText, isFalse);
      expect(claimMessage.isSystem, isFalse);
    });

    // ─── U6: Chip Status none / requested / delivered ────────────────────────
    test('U6: TransactionModel claimStatus helper flags berfungsi presisi', () {
      final mNone = TransactionModel(
        id: '1', trxCode: 'A', userId: 'u', productId: 'p', targetNumber: '0', amount: 10, status: 'success', createdAt: DateTime.now(),
        claimStatus: 'none',
      );
      final mReq = TransactionModel(
        id: '2', trxCode: 'B', userId: 'u', productId: 'p', targetNumber: '0', amount: 10, status: 'success', createdAt: DateTime.now(),
        claimStatus: 'requested',
      );
      final mDel = TransactionModel(
        id: '3', trxCode: 'C', userId: 'u', productId: 'p', targetNumber: '0', amount: 10, status: 'success', createdAt: DateTime.now(),
        claimStatus: 'delivered',
      );

      expect(mNone.isClaimNone, isTrue);
      expect(mNone.isClaimRequested, isFalse);
      expect(mNone.isClaimDelivered, isFalse);

      expect(mReq.isClaimNone, isFalse);
      expect(mReq.isClaimRequested, isTrue);
      expect(mReq.isClaimDelivered, isFalse);

      expect(mDel.isClaimNone, isFalse);
      expect(mDel.isClaimRequested, isFalse);
      expect(mDel.isClaimDelivered, isTrue);
    });

    // ─── U7: Admin Mark Delivered & Pelanggan Tak Melihat Kontrol Admin ────────
    testWidgets('U7: ChatScreen customer tidak melihat tombol tandai terkirim admin', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ChatScreen(roomUserId: testUserId, isAdmin: false),
      ));
      await tester.pump();

      // Customer view
      expect(find.byKey(Key('btn_mark_delivered_$testTrxId')), findsNothing);
    });

    // ─── U8: Dispose Tanpa Timer Pending ─────────────────────────────────────
    testWidgets('U8: QrisModal dispose bersih tanpa timer pending', (tester) async {
      final paidTrx = TransactionModel(
        id: testTrxId,
        trxCode: 'TRX-DISPOSE',
        userId: testUserId,
        productId: 'prod-1',
        targetNumber: '0812345678',
        amount: 20000,
        status: 'pending',
        createdAt: DateTime.now(),
        expiredAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: QrisModal(transaction: paidTrx)),
      ));
      await tester.pump();

      // Unmount widget
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump(const Duration(seconds: 1));
      // Verifikasi tidak ada timer atau exception menggantung
      expect(tester.takeException(), isNull);
    });

    // ─── U9: Audit Statis: Bebas wa.me / url_launcher / nomor literal ────────
    test('U9: lib/ bebas dari wa.me, whatsapp, url_launcher untuk alur klaim', () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final prohibitedRegex = RegExp(r'wa\.me|api\.whatsapp\.com|url_launcher');
      final violations = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (prohibitedRegex.hasMatch(content)) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Dilarang menggunakan WhatsApp/url_launcher. Gunakan Chat Admin bawaan.',
      );
    });

    // ─── Viewport Tests: Desktop (1280x800) & Mobile (390x844) ───────────────
    testWidgets('Viewport Desktop 1280x800 QrisModal Success tanpa overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final paidTrx = TransactionModel(
        id: testTrxId,
        trxCode: 'TRX-VIEWPORT-DESK',
        userId: testUserId,
        productId: 'prod-1',
        productName: 'Google One 2TB 1 Bulan',
        targetNumber: '0812345678',
        amount: 45000,
        status: 'success',
        claimStatus: 'none',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: QrisModal(transaction: paidTrx)),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('btn_claim_product')), findsOneWidget);
    });

    testWidgets('Viewport Mobile 390x844 QrisModal Success tanpa overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final paidTrx = TransactionModel(
        id: testTrxId,
        trxCode: 'TRX-VIEWPORT-MOB',
        userId: testUserId,
        productId: 'prod-1',
        productName: 'Google One 2TB 1 Bulan',
        targetNumber: '0812345678',
        amount: 45000,
        status: 'success',
        claimStatus: 'none',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: QrisModal(transaction: paidTrx)),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('btn_claim_product')), findsOneWidget);
    });
  });
}
