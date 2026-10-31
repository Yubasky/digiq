// lib/services/chat_service.dart

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import '../models/chat_message_model.dart';

class ChatService {
  static SupabaseClient get _sb => SupabaseConfig.supabase;

  static const _table = 'chat_messages';
  static DateTime? _lastSendTime;

  // ─── Stream room chat customer/admin ────────────────────────────────────────

  /// Stream pesan dalam satu room (room_user_id = ID customer).
  /// Customer hanya bisa akses room mereka sendiri (dijamin RLS).
  static Stream<List<ChatMessageModel>> watchChatRoom(String customerUserId) {
    return _sb
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('room_user_id', customerUserId)
        .order('created_at', ascending: true)
        .map((rows) =>
            rows.map((r) => ChatMessageModel.fromMap(r)).toList());
  }

  // ─── Daftar room untuk admin ─────────────────────────────────────────────────

  /// Stream aktif daftar room chat (admin). Menggunakan channel realtime
  /// untuk refresh saat ada pesan baru, lalu memanggil RPC.
  static StreamController<List<ChatRoomSummary>>? _adminRoomsController;
  static RealtimeChannel? _adminRoomsChannel;

  static Stream<List<ChatRoomSummary>> watchActiveChatRoomsForAdmin() {
    _adminRoomsController?.close();
    _adminRoomsController = StreamController<List<ChatRoomSummary>>.broadcast();

    // Fetch awal
    _fetchAdminRooms();

    // Subscribe realtime chat_messages agar refresh otomatis
    _adminRoomsChannel?.unsubscribe();
    _adminRoomsChannel = _sb
        .channel('admin_chat_rooms_watch')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _table,
          callback: (_) => _fetchAdminRooms(),
        )
        .subscribe();

    return _adminRoomsController!.stream;
  }

  static Future<void> _fetchAdminRooms() async {
    try {
      final rows = await _sb.rpc('admin_list_chat_rooms') as List<dynamic>;
      final rooms = rows
          .map((r) => ChatRoomSummary.fromMap(r as Map<String, dynamic>))
          .toList();
      _adminRoomsController?.add(rooms);
    } catch (_) {
      _adminRoomsController?.add([]);
    }
  }

  /// Bersihkan channel admin saat widget di-dispose.
  static Future<void> disposeAdminRooms() async {
    await _adminRoomsChannel?.unsubscribe();
    _adminRoomsChannel = null;
    await _adminRoomsController?.close();
    _adminRoomsController = null;
  }

  // ─── Kirim pesan ────────────────────────────────────────────────────────────

  /// Kirim pesan teks. RLS memastikan:
  /// - Customer: room_user_id = auth.uid(), sender_id = auth.uid(), kind = 'text'
  /// - Admin: sender_id = auth.uid(), bisa ke room mana pun
  static Future<void> sendMessage({
    required String roomUserId,
    required String message,
    String? receiverId,
  }) async {
    final senderId = _sb.auth.currentUser?.id;
    if (senderId == null) throw Exception('Tidak terautentikasi');

    final cleanText = message.trim();
    if (cleanText.isEmpty) return;

    // Rate limiting sederhana di sisi client: max 1 pesan per 500ms
    final now = DateTime.now();
    if (_lastSendTime != null &&
        now.difference(_lastSendTime!) < const Duration(milliseconds: 500)) {
      throw Exception('Mohon tunggu sejenak sebelum mengirim pesan lagi');
    }
    _lastSendTime = now;

    // Batasi panjang pesan maksimal 1000 karakter
    final boundedMessage =
        cleanText.length > 1000 ? cleanText.substring(0, 1000) : cleanText;

    await _sb.from(_table).insert({
      'sender_id': senderId,
      'receiver_id': receiverId,
      'room_user_id': roomUserId,
      'message': boundedMessage,
      'kind': 'text',
    });
  }

  // ─── Tandai pesan sebagai sudah dibaca ───────────────────────────────────────

  /// Tandai semua pesan dari lawan bicara di room ini sebagai sudah dibaca.
  static Future<void> markRoomAsRead(String roomUserId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;

    try {
      await _sb
          .from(_table)
          .update({'is_read': true})
          .eq('room_user_id', roomUserId)
          .neq('sender_id', uid)
          .eq('is_read', false);
    } catch (_) {
      // Ignored if RLS or permissions restrict update
    }
  }
}
