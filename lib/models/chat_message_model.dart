// lib/models/chat_message_model.dart

class ChatMessageModel {
  final String id;
  final String senderId;
  final String? receiverId;
  final String roomUserId;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  // Join field (nullable)
  final String? senderName;

  // Bidirectional claim & system fields
  final String kind; // 'text' | 'claim' | 'system'
  final String? trxId;

  const ChatMessageModel({
    required this.id,
    required this.senderId,
    this.receiverId,
    required this.roomUserId,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.senderName,
    this.kind = 'text',
    this.trxId,
  });

  bool get isClaim => kind == 'claim';
  bool get isSystem => kind == 'system';
  bool get isText => kind == 'text';

  bool isFromUser(String userId) => senderId == userId;

  factory ChatMessageModel.fromMap(Map<String, dynamic> m) {
    final senderMap = m['sender'] as Map<String, dynamic>?;
    return ChatMessageModel(
      id: m['id'] as String,
      senderId: m['sender_id'] as String,
      receiverId: m['receiver_id'] as String?,
      roomUserId: m['room_user_id'] as String,
      message: (m['message'] as String?) ?? '',
      isRead: (m['is_read'] as bool?) ?? false,
      createdAt: DateTime.parse(
          (m['created_at'] as String?) ?? DateTime.now().toIso8601String()),
      senderName: senderMap?['full_name'] as String?,
      kind: (m['kind'] as String?) ?? 'text',
      trxId: m['trx_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'room_user_id': roomUserId,
      'message': message,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'kind': kind,
      'trx_id': trxId,
    };
  }
}

/// Ringkasan room chat untuk tampilan daftar di admin.
class ChatRoomSummary {
  final String roomUserId;
  final String customerName;
  final String lastMessage;
  final DateTime lastAt;
  final int unreadCount;

  const ChatRoomSummary({
    required this.roomUserId,
    required this.customerName,
    required this.lastMessage,
    required this.lastAt,
    required this.unreadCount,
  });

  factory ChatRoomSummary.fromMap(Map<String, dynamic> m) {
    return ChatRoomSummary(
      roomUserId: m['room_user_id'] as String,
      customerName: (m['customer_name'] as String?) ?? 'Customer',
      lastMessage: (m['last_message'] as String?) ?? '',
      lastAt: DateTime.parse(
          (m['last_at'] as String?) ?? DateTime.now().toIso8601String()),
      unreadCount: ((m['unread_count'] as num?) ?? 0).toInt(),
    );
  }
}

