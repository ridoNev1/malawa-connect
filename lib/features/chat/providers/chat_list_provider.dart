// lib/features/chat/providers/chat_list_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sample_data.dart';

class ChatListState {
  final List<Map<String, dynamic>> chatRooms;
  final bool isLoading;

  ChatListState({required this.chatRooms, this.isLoading = false});

  ChatListState copyWith({
    List<Map<String, dynamic>>? chatRooms,
    bool? isLoading,
  }) {
    return ChatListState(
      chatRooms: chatRooms ?? this.chatRooms,
      isLoading: isLoading ?? this.isLoading,
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
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));

      // Use sample data
      final chatRooms = getChatListSampleData();

      state = state.copyWith(chatRooms: chatRooms);
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  void markAsRead(String chatId) {
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
