// lib/features/chat/models/chat_message_model.dart
class ChatMessageModel {
  final String id;
  final String text;
  final bool isSentByMe;
  final String time;
  final bool showDate;
  final bool showTime;
  final bool isImage;

  ChatMessageModel({
    required this.id,
    required this.text,
    required this.isSentByMe,
    required this.time,
    required this.showDate,
    required this.showTime,
    required this.isImage,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] ?? '',
      text: json['text'] ?? '',
      isSentByMe: json['isSentByMe'] ?? false,
      time: json['time'] ?? '',
      showDate: json['showDate'] ?? false,
      showTime: json['showTime'] ?? false,
      isImage: json['isImage'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isSentByMe': isSentByMe,
      'time': time,
      'showDate': showDate,
      'showTime': showTime,
      'isImage': isImage,
    };
  }

  ChatMessageModel copyWith({
    String? id,
    String? text,
    bool? isSentByMe,
    String? time,
    bool? showDate,
    bool? showTime,
    bool? isImage,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      text: text ?? this.text,
      isSentByMe: isSentByMe ?? this.isSentByMe,
      time: time ?? this.time,
      showDate: showDate ?? this.showDate,
      showTime: showTime ?? this.showTime,
      isImage: isImage ?? this.isImage,
    );
  }
}
