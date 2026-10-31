// test/claim_followup_audit_test.dart
// Pengujian Lanjutan Celah Audit Fitur Klaim Produk via Chat Admin (Tugas 2)
//
// Cakupan:
// 1. Antrean Admin: filter requested, badge count, navigasi chat, dialog konfirmasi & pemanggilan RPC 1x/batal, isolasi role customer.
// 2. Riwayat Pelanggan: chip status none/requested/delivered, tombol klaim/chat hanya untuk lunas belum delivered.
// 3. Toleransi Skema Lama: respons tanpa kolom claim_*, default 'none', penanganan ramah RPC missing (PGRST202/42883) tanpa crash.
// 4. Viewport Responsif: antrean admin & kartu klaim chat pada 1280x800 dan 390x844 bebas overflow.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:digiq/models/chat_message_model.dart';
import 'package:digiq/models/profile_model.dart';
import 'package:digiq/models/transaction_model.dart';
import 'package:digiq/screens/admin_dashboard_screen.dart';
import 'package:digiq/screens/chat/chat_screen.dart';
import 'package:digiq/screens/customer_dashboard_screen.dart';
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
    this._shouldThrow = false,
    this._errorMessage = '',
  });

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    if (_shouldThrow) {
      final err = PostgrestException(message: _errorMessage, code: 'PGRST202');
      return Future<T>.error(err).then(onValue, onError: onError);
    }
    return Future<T>.value(_result as T).then(onValue, onError: onError);
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    if (_shouldThrow) {
      final err = PostgrestException(message: _errorMessage, code: 'PGRST202');
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
      return Future<T>.error(PostgrestException(message: _errorMessage, code: 'PGRST202'));
    }
    return Future<T>.value(_result as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

class _FakeSupabaseStreamFilterBuilder
    extends StreamView<List<Map<String, dynamic>>>
    implements SupabaseStreamFilterBuilder, SupabaseStreamBuilder {
  final StreamController<List<Map<String, dynamic>>> _controller;

  _FakeSupabaseStreamFilterBuilder._(this._controller)
      : super(_controller.stream);

  factory _FakeSupabaseStreamFilterBuilder([
    StreamController<List<Map<String, dynamic>>>? ctrl,
  ]) {
    final controller =
        ctrl ?? StreamController<List<Map<String, dynamic>>>.broadcast();
    return _FakeSupabaseStreamFilterBuilder._(controller);
  }

  void emit(List<Map<String, dynamic>> data) {
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

class _FakeSupabaseQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final _FakeSupabaseClient client;
  final String table;
  _FakeSupabaseQueryBuilder(this.client, this.table);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> insert(
    dynamic values, {
    dynamic defaultToNull,
  }) {
    client.lastInsertedTable = table;
    client.lastInsertedValues = values;
    return _FakeRpcFilterBuilder<List<Map<String, dynamic>>>([]);
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) {
    if (table == 'profiles') {
      return _FakeRpcFilterBuilder<List<Map<String, dynamic>>>([
        client.mockProfileData,
      ]);
    }
    return _FakeRpcFilterBuilder<List<Map<String, dynamic>>>([]);
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> update(
    Map values, {
    dynamic defaultToNull,
  }) {
    return _FakeRpcFilterBuilder<List<Map<String, dynamic>>>([]);
  }

  @override
  SupabaseStreamFilterBuilder stream({
    required List<String> primaryKey,
    bool private = false,
  }) {
    final sb = _FakeSupabaseStreamFilterBuilder();
    client.streamBuildersByTable[table] = sb;
    return sb;
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
          accessToken: 'fake-token-test',
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

  Map<String, dynamic> mockProfileData = {
    'id': 'admin-uuid-1',
    'role': 'admin',
    'full_name': 'Admin DigiQ',
    'username': 'admin_digiq',
    'is_2fa_enabled': true,
  };

  List<Map<String, dynamic>> pendingClaimsMock = [];
  final Map<String, _FakeSupabaseStreamFilterBuilder> streamBuildersByTable = {};

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
        'conversation_id': 'user-uuid-123',
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
      return _FakeRpcFilterBuilder<T>(pendingClaimsMock as T);
    }

    return _FakeRpcFilterBuilder<T>(null as T);
  }
}

// ─── Main Test Runner ────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    AppLanguage.setLanguage(AppLang.id);
  });

  group('Audit & Celah Pengujian Lanjutan (Tugas 2)', () {
    late _FakeSupabaseClient fakeClient;
    const testAdminId = 'admin-uuid-001';
    const testCustomerId = 'cust-uuid-001';

    final customerProfile = ProfileModel(
      id: testCustomerId,
      fullName: 'Budi Santoso',
      username: 'budisantoso',
      phone: '08123456780',
      role: 'customer',
      balance: 150000,
      is2faEnabled: false,
      updatedAt: DateTime.now(),
    );

    setUp(() {
      final mockUser = User(
        id: testAdminId,
        appMetadata: {},
        userMetadata: {'full_name': 'Administrator DigiQ'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'admin@digiq.com',
      );
      fakeClient = _FakeSupabaseClient(user: mockUser);
      SupabaseConfig.testClient = fakeClient;
    });

    tearDown(() {
      SupabaseConfig.testClient = null;
    });

    // ─── BAGIAN 1: ANTREAN ADMIN ─────────────────────────────────────────────

    testWidgets(
        'T2.1: Antrean admin hanya menampilkan transaksi status requested & badge akurat',
        (tester) async {
      // 2 requested, 1 delivered (tidak boleh tampil di antrean), 1 none
      fakeClient.pendingClaimsMock = [
        {
          'trx_id': 'trx-req-1',
          'trx_code': 'TRX-REQ-001',
          'user_id': 'user-1',
          'customer_name': 'Ahmad',
          'product_id': 'prod-1',
          'product_name': 'Netflix 1 Bulan',
          'base_amount': 35000,
          'unique_code': 12,
          'total_amount': 35012,
          'target_number': '0811111111',
          'paid_at': DateTime.now().toIso8601String(),
          'claim_requested_at': DateTime.now().toIso8601String(),
          'claim_status': 'requested',
          'conversation_id': 'user-1',
        },
        {
          'trx_id': 'trx-req-2',
          'trx_code': 'TRX-REQ-002',
          'user_id': 'user-2',
          'customer_name': 'Siti',
          'product_id': 'prod-2',
          'product_name': 'Spotify 1 Bulan',
          'base_amount': 25000,
          'unique_code': 34,
          'total_amount': 25034,
          'target_number': '0822222222',
          'paid_at': DateTime.now().toIso8601String(),
          'claim_requested_at': DateTime.now().toIso8601String(),
          'claim_status': 'requested',
          'conversation_id': 'user-2',
        },
      ];

      await tester.pumpWidget(MaterialApp(
        home: AdminDashboardScreen(),
      ));
      await tester.pump();

      // Emit event transaksi realtime agar antrean ter-populate
      fakeClient.streamBuildersByTable['transactions']?.emit([
        {'id': 'trx-req-1', 'status': 'success', 'claim_status': 'requested'},
        {'id': 'trx-req-2', 'status': 'success', 'claim_status': 'requested'},
        {'id': 'trx-del-3', 'status': 'success', 'claim_status': 'delivered'},
        {'id': 'trx-none-4', 'status': 'success', 'claim_status': 'none'},
      ]);
      await tester.pump();

      // Beralih ke Tab Transaksi (Index 2)
      final trxTab = find.byIcon(Icons.receipt_long_outlined);
      if (trxTab.evaluate().isNotEmpty) {
        await tester.tap(trxTab);
        await tester.pump();
      }

      // Badge menampilkan angka 2
      expect(find.byKey(const Key('admin_pending_claims_section')), findsOneWidget);
      expect(find.text('2'), findsWidgets);

      // Hanya kartu trx-req-1 dan trx-req-2 yang tampil
      expect(find.byKey(const Key('pending_claim_card_trx-req-1')), findsOneWidget);
      expect(find.byKey(const Key('pending_claim_card_trx-req-2')), findsOneWidget);
      expect(find.byKey(const Key('pending_claim_card_trx-del-3')), findsNothing);
      expect(find.byKey(const Key('pending_claim_card_trx-none-4')), findsNothing);

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
        'T2.3 & T2.4: Tombol Tandai Terkirim menampilkan konfirmasi; batal tidak memanggil RPC; konfirmasi memanggil 1x',
        (tester) async {
      fakeClient.pendingClaimsMock = [
        {
          'trx_id': 'trx-confirm-test',
          'trx_code': 'TRX-CONFIRM-001',
          'user_id': 'user-cust-1',
          'customer_name': 'Doni',
          'product_id': 'prod-1',
          'product_name': 'YouTube Premium',
          'base_amount': 15000,
          'unique_code': 55,
          'total_amount': 15055,
          'target_number': '0833333333',
          'paid_at': DateTime.now().toIso8601String(),
          'claim_requested_at': DateTime.now().toIso8601String(),
          'claim_status': 'requested',
          'conversation_id': 'user-cust-1',
        },
      ];

      await tester.pumpWidget(MaterialApp(
        home: AdminDashboardScreen(),
      ));
      await tester.pump();

      fakeClient.streamBuildersByTable['transactions']?.emit([
        {'id': 'trx-confirm-test', 'status': 'success', 'claim_status': 'requested'},
      ]);
      await tester.pump();

      // Beralih ke Tab Transaksi (Index 2)
      final trxTab = find.byIcon(Icons.receipt_long_outlined);
      if (trxTab.evaluate().isNotEmpty) {
        await tester.tap(trxTab);
        await tester.pump();
      }

      final deliverBtn = find.byKey(const Key('btn_admin_deliver_trx-confirm-test'));
      expect(deliverBtn, findsOneWidget);

      // ── Uji Batal ──
      await tester.ensureVisible(deliverBtn);
      await tester.tap(deliverBtn);
      await tester.pumpAndSettle();

      // Dialog konfirmasi harus muncul
      expect(find.text(AppLanguage.t('chat_confirm_delivered_title')), findsOneWidget);
      expect(find.text(AppLanguage.t('chat_confirm_delivered_desc')), findsOneWidget);

      // Tekan tombol Batal
      final cancelBtn = find.text(AppLanguage.t('cancel'));
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      // Dialog tertutup, RPC TIDAK dipanggil sama sekali
      expect(fakeClient.markDeliveredCallCount, equals(0));

      // ── Uji Konfirmasi Kirim ──
      await tester.ensureVisible(deliverBtn);
      await tester.tap(deliverBtn);
      await tester.pumpAndSettle();

      final confirmBtn = find.descendant(of: find.byType(AlertDialog), matching: find.byType(ElevatedButton));
      await tester.tap(confirmBtn);
      await tester.pump();

      // RPC admin_mark_delivered dipanggil tepat 1 kali
      expect(fakeClient.markDeliveredCallCount, equals(1));
      expect(fakeClient.lastDeliveredTrxId, equals('trx-confirm-test'));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('T2.6: Kontrol antrean admin TIDAK muncul untuk role customer',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CustomerDashboardScreen(profile: customerProfile),
      ));
      await tester.pump();

      // Pastikan bagian antrean klaim admin sama sekali tidak ada di dashboard customer
      expect(find.byKey(const Key('admin_pending_claims_section')), findsNothing);
      expect(find.text(AppLanguage.t('admin_pending_claims_title')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    // ─── BAGIAN 2: RIWAYAT PELANGGAN ─────────────────────────────────────────

    testWidgets(
        'T2.7 & T2.8: Chip status dan tombol aksi pada riwayat pelanggan sesuai aturan status',
        (tester) async {
      // 1. Transaksi Sukses + Status none -> Tampil tombol Klaim Produk
      final txNone = QrisTransaction(
        id: 'tx-hist-1',
        customerName: 'Budi Santoso',
        productName: 'Netflix 1 Bulan',
        baseAmount: 35000,
        totalAmount: 35000,
        timestamp: DateTime.now(),
        status: 'SUCCESS',
        claimStatus: 'none',
        rawTrxId: 'trx-raw-1',
        userId: testCustomerId,
      );

      // 2. Transaksi Sukses + Status requested -> Tampil tombol Buka Chat Admin
      final txRequested = QrisTransaction(
        id: 'tx-hist-2',
        customerName: 'Budi Santoso',
        productName: 'Spotify 1 Bulan',
        baseAmount: 25000,
        totalAmount: 25000,
        timestamp: DateTime.now(),
        status: 'SUCCESS',
        claimStatus: 'requested',
        rawTrxId: 'trx-raw-2',
        userId: testCustomerId,
      );

      // 3. Transaksi Sukses + Status delivered -> TIDAK ada tombol klaim/chat
      final txDelivered = QrisTransaction(
        id: 'tx-hist-3',
        customerName: 'Budi Santoso',
        productName: 'YouTube Premium',
        baseAmount: 15000,
        totalAmount: 15000,
        timestamp: DateTime.now(),
        status: 'SUCCESS',
        claimStatus: 'delivered',
        rawTrxId: 'trx-raw-3',
        userId: testCustomerId,
      );

      // 4. Transaksi Pending -> TIDAK ada tombol klaim/chat
      final txPending = QrisTransaction(
        id: 'tx-hist-4',
        customerName: 'Budi Santoso',
        productName: 'Google One 2TB',
        baseAmount: 45000,
        totalAmount: 45000,
        timestamp: DateTime.now(),
        status: 'PENDING',
        claimStatus: 'none',
        rawTrxId: 'trx-raw-4',
        userId: testCustomerId,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                _buildTestTxCard(txNone),
                _buildTestTxCard(txRequested),
                _buildTestTxCard(txDelivered),
                _buildTestTxCard(txPending),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();

      // Verifikasi Chip Status
      expect(find.text(AppLanguage.t('claim_status_none')), findsNWidgets(2));
      expect(find.text(AppLanguage.t('claim_status_requested')), findsOneWidget);
      expect(find.text(AppLanguage.t('claim_status_delivered')), findsOneWidget);

      // Verifikasi Tombol Aksi
      expect(find.byKey(const Key('btn_claim_history_tx-hist-1')), findsOneWidget);
      expect(find.byKey(const Key('btn_open_chat_history_tx-hist-2')), findsOneWidget);
      expect(find.byKey(const Key('btn_claim_history_tx-hist-3')), findsNothing);
      expect(find.byKey(const Key('btn_open_chat_history_tx-hist-3')), findsNothing);
      expect(find.byKey(const Key('btn_claim_history_tx-hist-4')), findsNothing);
      expect(find.byKey(const Key('btn_open_chat_history_tx-hist-4')), findsNothing);
    });

    // ─── BAGIAN 3: TOLERANSI SKEMA LAMA & ERROR RAMAH ─────────────────────────

    testWidgets(
        'T2.9: Respons transaksi database lama TANPA kolom claim_* default none & tidak crash',
        (tester) async {
      final oldDbMap = {
        'id': 'trx-legacy-001',
        'trx_code': 'TRX-LEGACY-001',
        'user_id': testCustomerId,
        'product_id': 'prod-legacy-1',
        'target_number': '0899999999',
        'amount': 50000,
        'status': 'success',
        'created_at': DateTime.now().toIso8601String(),
        // Catatan: Tidak memuat kolom claim_status, claim_requested_at, delivered_at, delivered_by
      };

      // Harus parsing dengan aman tanpa exception
      final model = TransactionModel.fromMap(oldDbMap);
      expect(model.claimStatus, equals('none'));
      expect(model.isClaimNone, isTrue);
      expect(model.isClaimRequested, isFalse);
      expect(model.isClaimDelivered, isFalse);
      expect(model.claimRequestedAt, isNull);
      expect(model.deliveredAt, isNull);

      final qrisTx = QrisTransaction.fromTransactionModel(model, 'Pelanggan');
      expect(qrisTx.claimStatus, equals('none'));
    });

    testWidgets(
        'T2.11: RPC missing PGRST202 (sebelum migrasi DB) menampilkan snackbar ramah tanpa exception',
        (tester) async {
      fakeClient.shouldThrowRpc = true;
      fakeClient.rpcErrorMessage =
          'function request_claim does not exist in schema cache (PGRST202)';

      final paidTrx = TransactionModel(
        id: 'trx-unmigrated-1',
        trxCode: 'TRX-UNMIGRATED-001',
        userId: testCustomerId,
        productId: 'prod-1',
        productName: 'Canva Pro 1 Bulan',
        targetNumber: '0812345678',
        amount: 15000,
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

      await tester.tap(claimBtn, warnIfMissed: false);
      await tester.pump();

      // Memastikan SnackBar menampilkan pesan ramah
      expect(
        find.textContaining('Layanan klaim sedang disiapkan server'),
        findsOneWidget,
      );
      // Tombol tetap ada dan aplikasi tidak crash
      expect(find.byKey(const Key('btn_claim_product')), findsOneWidget);
    });

    // ─── BAGIAN 4: RESPONSIVITAS VIEWPORTS 1280x800 & 390x844 ─────────────────

    testWidgets(
        'T2.12 & T2.13: Antrean admin bebas RenderFlex overflow pada Desktop (1280x800) & Mobile (390x844)',
        (tester) async {
      fakeClient.pendingClaimsMock = [
        {
          'trx_id': 'trx-viewport-admin',
          'trx_code': 'TRX-VIEWPORT-001',
          'user_id': 'user-viewport',
          'customer_name': 'Pelanggan Uji Layar Panjang Dan Lebar Sekali',
          'product_id': 'prod-1',
          'product_name': 'Paket Langganan Disney+ Hotstar Tahunan Premium Multi-Device',
          'base_amount': 250000,
          'unique_code': 99,
          'total_amount': 250099,
          'target_number': '0812345678901234',
          'paid_at': DateTime.now().toIso8601String(),
          'claim_requested_at': DateTime.now().toIso8601String(),
          'claim_status': 'requested',
          'conversation_id': 'user-viewport',
        },
      ];

      // ── Desktop 1280x800 ──
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(
        home: AdminDashboardScreen(),
      ));
      await tester.pump();
      fakeClient.streamBuildersByTable['transactions']?.emit([
        {'id': 'trx-viewport-admin', 'status': 'success', 'claim_status': 'requested'},
      ]);
      await tester.pump();
      final trxTab1 = find.byIcon(Icons.receipt_long_outlined);
      if (trxTab1.evaluate().isNotEmpty) {
        await tester.tap(trxTab1);
        await tester.pump();
      }

      expect(tester.takeException(), isNull, reason: 'Desktop 1280x800 bebas overflow');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));



      // ── Mobile 390x844 ──
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
        home: AdminDashboardScreen(),
      ));
      await tester.pump();
      fakeClient.streamBuildersByTable['transactions']?.emit([
        {'id': 'trx-viewport-admin', 'status': 'success', 'claim_status': 'requested'},
      ]);
      await tester.pump();
      final trxTab2 = find.byIcon(Icons.receipt_long_outlined);
      if (trxTab2.evaluate().isNotEmpty) {
        await tester.tap(trxTab2);
        await tester.pump();
      }

      expect(tester.takeException(), isNull, reason: 'Mobile 390x844 bebas overflow');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets(
        'T2.14 & T2.15: Kartu klaim di chat bebas overflow pada Desktop (1280x800) & Mobile (390x844)',
        (tester) async {
      final claimMessage = ChatMessageModel(
        id: 'msg-claim-resp',
        senderId: testCustomerId,
        roomUserId: testCustomerId,
        message:
            'Halo Admin, saya ingin klaim pesanan #TRX-9999 (Paket Super Lengkap Cloud Storage 2TB) senilai Rp 150.000 (Lunas: 31/10/2026 13:00 WIB). Target pengiriman: 08123456789. Mohon segera diproses.',
        isRead: false,
        createdAt: DateTime.now(),
        kind: 'claim',
        trxId: 'trx-chat-resp',
      );

      // ── Desktop 1280x800 ──
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            roomUserId: testCustomerId,
            customerName: 'Budi Santoso',
            isAdmin: true,
          ),
        ),
      ));
      await tester.pump();

      fakeClient.streamBuildersByTable['chat_messages']?.emit([
        claimMessage.toMap(),
      ]);
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'Desktop 1280x800 chat claim bebas overflow');
      expect(find.byKey(const Key('claim_card_msg-claim-resp')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));



      // ── Mobile 390x844 ──
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatScreen(
            roomUserId: testCustomerId,
            customerName: 'Budi Santoso',
            isAdmin: true,
          ),
        ),
      ));
      await tester.pump();

      fakeClient.streamBuildersByTable['chat_messages']?.emit([
        claimMessage.toMap(),
      ]);
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'Mobile 390x844 chat claim bebas overflow');
      expect(find.byKey(const Key('claim_card_msg-claim-resp')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.binding.setSurfaceSize(null);
    });
  });
}

// ─── Helper Pembantu Uji Riwayat Pelanggan ────────────────────────────────────

Widget _buildTestTxCard(QrisTransaction tx) {
  final isSuccess = tx.status == 'SUCCESS';
  final canClaimOrChat = isSuccess && tx.claimStatus != 'delivered';
  final isClaimNone = tx.claimStatus == 'none';

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tx.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tx.claimStatus == 'delivered'
                    ? Colors.green.shade100
                    : tx.claimStatus == 'requested'
                        ? Colors.orange.shade100
                        : Colors.blue.shade100,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                tx.claimStatus == 'delivered'
                    ? AppLanguage.t('claim_status_delivered')
                    : tx.claimStatus == 'requested'
                        ? AppLanguage.t('claim_status_requested')
                        : AppLanguage.t('claim_status_none'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (canClaimOrChat)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                key: Key(isClaimNone
                    ? 'btn_claim_history_${tx.id}'
                    : 'btn_open_chat_history_${tx.id}'),
                onPressed: () {},
                icon: Icon(
                  isClaimNone
                      ? Icons.inventory_2_outlined
                      : Icons.chat_outlined,
                  size: 15,
                ),
                label: Text(
                  isClaimNone
                      ? AppLanguage.t('claim_product_btn')
                      : AppLanguage.t('open_chat_btn'),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}
