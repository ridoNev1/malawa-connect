// lib/features/chat/models/chat_room_model.dart
class ChatRoomModel {
  final String id;
  final String name;
  final String avatar;
  final bool isOnline;
  final String lastSeen;

  ChatRoomModel({
    required this.id,
    required this.name,
    required this.avatar,
    required this.isOnline,
    required this.lastSeen,
  });

  factory ChatRoomModel.fromJson(Map<String, dynamic> json) {
    return ChatRoomModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '',
      isOnline: json['isOnline'] ?? false,
      lastSeen: json['lastSeen'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'isOnline': isOnline,
      'lastSeen': lastSeen,
    };
  }
}
