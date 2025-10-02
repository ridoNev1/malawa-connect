// lib/features/chat/models/chat_room_model.dart
class ChatRoomModel {
  final String id;
  final String name;
  final String avatar;
  final bool isOnline;
  final String lastSeen;
  final String? locationName;

  ChatRoomModel({
    required this.id,
    required this.name,
    required this.avatar,
    required this.isOnline,
    required this.lastSeen,
    this.locationName,
  });

  factory ChatRoomModel.fromJson(Map<String, dynamic> json) {
    return ChatRoomModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '',
      isOnline: json['isOnline'] ?? false,
      lastSeen: json['lastSeen'] ?? '',
      locationName: json['locationName'] ?? json['location_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'isOnline': isOnline,
      'lastSeen': lastSeen,
      if (locationName != null) 'locationName': locationName,
    };
  }
}
