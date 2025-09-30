import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/services/mock_api.dart';
import '../models/chat_message_model.dart';
import '../models/chat_room_model.dart';

class ChatRoomState {
  final ChatRoomModel chatRoom;
  final List<ChatMessageModel> messages;
  final bool isLoading;
  final bool isSending;
  final bool showEmojiPicker;
  final int page;
  final int pageSize;
  final bool isLoadingMore;
  final bool hasMore;

  ChatRoomState({
    required this.chatRoom,
    required this.messages,
    this.isLoading = false,
    this.isSending = false,
    this.showEmojiPicker = false,
    this.page = 1,
    this.pageSize = 50,
    this.isLoadingMore = false,
    this.hasMore = true,
  });

  ChatRoomState copyWith({
    ChatRoomModel? chatRoom,
    List<ChatMessageModel>? messages,
    bool? isLoading,
    bool? isSending,
    bool? showEmojiPicker,
    int? page,
    int? pageSize,
    bool? isLoadingMore,
    bool? hasMore,
  }) {
    return ChatRoomState(
      chatRoom: chatRoom ?? this.chatRoom,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      showEmojiPicker: showEmojiPicker ?? this.showEmojiPicker,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
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

  Future<void> loadRoom() async {
    final info = await MockApi.instance.getChatById(chatRoom.id);
    if (info != null) {
      state = state.copyWith(chatRoom: ChatRoomModel.fromJson(info));
    }
  }

  Future<void> loadMessages() async {
    state = state.copyWith(isLoading: true);
    try {
      // page 1 initial
      final data = await MockApi.instance.getChatMessages(chatRoom.id);
      final messages = data.map((json) => ChatMessageModel.fromJson(json)).toList();
      // Assume newest at bottom (as current UI)
      state = state.copyWith(messages: messages, page: 1, hasMore: messages.isNotEmpty);
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      // In mock, just duplicate earlier messages to simulate history
      final current = state.messages;
      if (current.isEmpty) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
        return;
      }
      final older = current.take(5).map((m) {
        return ChatMessageModel(
          id: 'old_${m.id}_${state.page + 1}',
          text: m.text,
          isSentByMe: m.isSentByMe,
          time: m.time,
          showDate: m.showDate,
          showTime: m.showTime,
          isImage: m.isImage,
        );
      }).toList();
      state = state.copyWith(
        messages: [...older, ...current],
        isLoadingMore: false,
        page: state.page + 1,
        hasMore: state.page + 1 < 5, // stop after few loads in mock
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
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
      await MockApi.instance
          .sendMessage(chatId: chatRoom.id, text: text, isImage: false);
      // Simulated reply
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
      await MockApi.instance
          .sendMessage(chatId: chatRoom.id, text: imagePath, isImage: true);
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

// Provider family by ChatRoomModel (pre-Riverpod 3 style used in codebase)
final chatRoomProviderFamily =
    NotifierProvider.family<ChatRoomNotifier, ChatRoomState, ChatRoomModel>(
  ChatRoomNotifier.new,
);
