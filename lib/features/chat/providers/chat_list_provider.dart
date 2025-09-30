// lib/features/chat/providers/chat_list_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/mock_api.dart';

class ChatListState {
  final List<Map<String, dynamic>> chatRooms;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int pageSize;

  ChatListState({
    required this.chatRooms,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.pageSize = 20,
  });

  ChatListState copyWith({
    List<Map<String, dynamic>>? chatRooms,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? pageSize,
  }) {
    return ChatListState(
      chatRooms: chatRooms ?? this.chatRooms,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}

class ChatListNotifier extends Notifier<ChatListState> {
  @override
  ChatListState build() {
    return ChatListState(chatRooms: []);
  }

  Future<void> loadChatRooms() async {
    state = state.copyWith(isLoading: true);
    try {
      final chatRooms = await MockApi.instance
          .getChatList(limit: state.pageSize, offset: 0);
      state = state.copyWith(
        chatRooms: chatRooms,
        hasMore: chatRooms.length == state.pageSize,
      );
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
      final offset = state.chatRooms.length;
      final more = await MockApi.instance
          .getChatList(limit: state.pageSize, offset: offset);
      state = state.copyWith(
        chatRooms: [...state.chatRooms, ...more],
        isLoadingMore: false,
        hasMore: more.length == state.pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> markAsRead(String chatId) async {
    await MockApi.instance.markChatAsRead(chatId);
    final updatedChatRooms = state.chatRooms.map((chat) {
      if (chat['id'] == chatId) {
        return {...chat, 'unreadCount': 0};
      }
      return chat;
    }).toList();

    state = state.copyWith(chatRooms: updatedChatRooms);
  }

  void updateLastMessage(String chatId, String message, bool isSentByMe) {
    final now = DateTime.now();

    final updatedChatRooms = state.chatRooms.map((chat) {
      if (chat['id'] == chatId) {
        return {
          ...chat,
          'lastMessage': message,
          'lastMessageTime': now.toIso8601String(),
          'unreadCount': isSentByMe
              ? 0
              : ((chat['unreadCount'] ?? 0) as int) + 1,
        };
      }
      return chat;
    }).toList();

    state = state.copyWith(chatRooms: updatedChatRooms);
  }
}

final chatListProvider = NotifierProvider<ChatListNotifier, ChatListState>(
  ChatListNotifier.new,
);
