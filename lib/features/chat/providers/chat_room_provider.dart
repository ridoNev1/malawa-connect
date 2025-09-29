import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/sample_data.dart';
import '../models/chat_message_model.dart';
import '../models/chat_room_model.dart';

class ChatRoomState {
  final ChatRoomModel chatRoom;
  final List<ChatMessageModel> messages;
  final bool isLoading;
  final bool isSending;
  final bool showEmojiPicker;

  ChatRoomState({
    required this.chatRoom,
    required this.messages,
    this.isLoading = false,
    this.isSending = false,
    this.showEmojiPicker = false,
  });

  ChatRoomState copyWith({
    ChatRoomModel? chatRoom,
    List<ChatMessageModel>? messages,
    bool? isLoading,
    bool? isSending,
    bool? showEmojiPicker,
  }) {
    return ChatRoomState(
      chatRoom: chatRoom ?? this.chatRoom,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      showEmojiPicker: showEmojiPicker ?? this.showEmojiPicker,
    );
  }
}

class ChatRoomNotifier extends Notifier<ChatRoomState> {
  ChatRoomNotifier(this.chatRoom);
  final ChatRoomModel chatRoom;

  @override
  ChatRoomState build() {
    return ChatRoomState(chatRoom: chatRoom, messages: []);
  }

  Future<void> loadMessages() async {
    state = state.copyWith(isLoading: true);
    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));

      // Use sample data and convert to ChatMessageModel
      final sampleMessages = getChatRoomSampleMessages();
      final messages = sampleMessages
          .map((json) => ChatMessageModel.fromJson(json))
          .toList();

      state = state.copyWith(messages: messages);
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final now = DateTime.now();
    final formattedTime = DateFormat('h:mm a').format(now);

    final newMessage = ChatMessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isSentByMe: true,
      time: formattedTime,
      showDate: false,
      showTime: true,
      isImage: false,
    );

    state = state.copyWith(
      messages: [...state.messages, newMessage],
      isSending: true,
    );

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));

      // Add reply message after delay
      Future.delayed(const Duration(seconds: 2), () {
        _addReplyMessage();
      });
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isSending: false);
    }
  }

  Future<void> sendImage(String imagePath) async {
    final now = DateTime.now();
    final formattedTime = DateFormat('h:mm a').format(now);

    final newMessage = ChatMessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: imagePath,
      isSentByMe: true,
      time: formattedTime,
      showDate: false,
      showTime: true,
      isImage: true,
    );

    state = state.copyWith(
      messages: [...state.messages, newMessage],
      isSending: true,
    );

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isSending: false);
    }
  }

  void _addReplyMessage() {
    final now = DateTime.now();
    final formattedTime = DateFormat('h:mm a').format(now);

    final replies = [
      'Tentu saja! Saya ada di sini sekarang. Kamu dimana?',
      'Wah, kebetulan! Saya juga di sini. Saya pakai baju biru, duduk di dekat jendela.',
      'Bagus sekali! Saya akan segera ke sana.',
    ];

    final randomReply = replies[state.messages.length % replies.length];

    final newMessage = ChatMessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: randomReply,
      isSentByMe: false,
      time: formattedTime,
      showDate: false,
      showTime: true,
      isImage: false,
    );

    state = state.copyWith(messages: [...state.messages, newMessage]);
  }

  void toggleEmojiPicker() {
    state = state.copyWith(showEmojiPicker: !state.showEmojiPicker);
  }
}

// Deklarasi provider dengan family
final chatRoomProviderFamily =
    NotifierProvider.family<ChatRoomNotifier, ChatRoomState, ChatRoomModel>(
  ChatRoomNotifier.new,
);
