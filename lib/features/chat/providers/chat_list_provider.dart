// lib/features/chat/providers/chat_list_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_api.dart';

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
  RealtimeChannel? _userChan;
  @override
  ChatListState build() {
    ref.onDispose(() async {
      if (_userChan != null) {
        try {
          await _userChan!.unsubscribe();
        } catch (_) {}
      }
    });
    _initRealtime();
    return ChatListState(chatRooms: []);
  }

  void _initRealtime() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _userChan = SupabaseApi.userChannel(uid: uid)
      ..onBroadcast(event: 'chat_update', callback: (payload, [ref]) async {
        // payload shape can be Map with {event, payload}
        Map<String, dynamic>? data;
        if (payload is Map) {
          if (payload['payload'] is Map) {
            data = (payload['payload'] as Map).cast<String, dynamic>();
          } else {
            data = payload.cast<String, dynamic>();
          }
        }
        if (data != null) {
          // Soft-refresh: update last message in-place if found
          final chatId = (data['chat_id'] ?? '').toString();
          final lastText = (data['last_message_text'] ?? '').toString();
          final lastAt = (data['last_message_at'] ?? '').toString();
          final updated = state.chatRooms.map((e) {
            if (e['id'].toString() == chatId) {
              return {
                ...e,
                'lastMessage': lastText,
                'lastMessageTime': lastAt,
              };
            }
            return e;
          }).toList();
          state = state.copyWith(chatRooms: updated);
          // Optionally resort by lastMessageTime via full refresh
          await loadChatRooms();
        }
      })
      ..subscribe();
  }

  Future<void> loadChatRooms() async {
    state = state.copyWith(isLoading: true);
    try {
      final chatRooms = await SupabaseApi.getChatListOrg5(
        search: '',
        limit: state.pageSize,
        offset: 0,
      );
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
      final more = await SupabaseApi.getChatListOrg5(
        search: '',
        limit: state.pageSize,
        offset: offset,
      );
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
    await SupabaseApi.markReadOrg5(chatId: chatId);
    final updatedChatRooms = state.chatRooms.map((chat) {
      if (chat['id'] == chatId) {
        return {...chat, 'unreadCount': 0};
      }
      return chat;
    }).toList();

    state = state.copyWith(chatRooms: updatedChatRooms);
  }

  void updateLastMessage(String chatId, String message, bool isSentByMe) {
    final updatedChatRooms = state.chatRooms.map((chat) {
      if (chat['id'] == chatId) {
        return {
          ...chat,
          'lastMessage': message,
          'lastMessageTime': DateTime.now().toIso8601String(),
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
