import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_api.dart';
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
  String? _peerId;

  @override
  ChatRoomState build() {
    return ChatRoomState(chatRoom: chatRoom, messages: []);
  }

  Future<void> loadRoom() async {
    final header = await SupabaseApi.getRoomHeaderOrg5(chatId: chatRoom.id);
    if (header != null) {
      _peerId = (header['peer_id'] ?? header['peerId'])?.toString();
      state = state.copyWith(
        chatRoom: ChatRoomModel(
          id: (header['id'] ?? chatRoom.id).toString(),
          name: (header['name'] ?? '').toString(),
          avatar: (header['avatar'] ?? '').toString(),
          isOnline: (header['isOnline'] as bool?) ?? false,
          lastSeen: (header['lastSeen'] ?? '').toString(),
        ),
      );
    }
  }

  Future<void> loadMessages() async {
    state = state.copyWith(isLoading: true);
    try {
      final data = await SupabaseApi.getMessagesOrg5(chatId: chatRoom.id, limit: state.pageSize);
      final messages = <ChatMessageModel>[];
      for (final json in data.reversed) {
        final isImg = (json['isImage'] as bool?) ?? false;
        String text = (json['text'] ?? '').toString();
        if (isImg && (json['imageUrl'] ?? '').toString().isNotEmpty) {
          final signed = await SupabaseApi.getSignedChatImageUrl(
            path: (json['imageUrl'] ?? '').toString(),
          );
          if (signed != null) text = signed;
        }
        messages.add(ChatMessageModel(
          id: (json['id'] ?? '').toString(),
          text: text,
          isSentByMe: (json['isMine'] as bool?) ?? false,
          time: _formatTime((json['created_at'] ?? '').toString()),
          showDate: false,
          showTime: true,
          isImage: isImg,
        ));
      }
      // Assume newest at bottom (as current UI)
      state = state.copyWith(messages: messages, page: 1, hasMore: data.length == state.pageSize);
      _subscribeRoom();
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
      final before = _firstCreatedAt();
      final data = await SupabaseApi.getMessagesOrg5(
        chatId: chatRoom.id,
        limit: state.pageSize,
        before: before,
      );
      if (data.isEmpty) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
        return;
      }
      final older = <ChatMessageModel>[];
      for (final json in data.reversed) {
        final isImg = (json['isImage'] as bool?) ?? false;
        String text = (json['text'] ?? '').toString();
        if (isImg && (json['imageUrl'] ?? '').toString().isNotEmpty) {
          final signed = await SupabaseApi.getSignedChatImageUrl(
            path: (json['imageUrl'] ?? '').toString(),
          );
          if (signed != null) text = signed;
        }
        older.add(ChatMessageModel(
          id: (json['id'] ?? '').toString(),
          text: text,
          isSentByMe: (json['isMine'] as bool?) ?? false,
          time: _formatTime((json['created_at'] ?? '').toString()),
          showDate: false,
          showTime: true,
          isImage: isImg,
        ));
      }
      state = state.copyWith(
        messages: [...older, ...state.messages],
        isLoadingMore: false,
        page: state.page + 1,
        hasMore: data.length == state.pageSize,
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
      final clientId = DateTime.now().millisecondsSinceEpoch.toString();
      await SupabaseApi.sendMessageOrg5(
        chatId: chatRoom.id,
        text: text,
        isImage: false,
        clientId: clientId,
      );
      // Broadcast to room channel so other device updates instantly
      try {
        SupabaseApi.roomChannel(chatRoom.id).sendBroadcastMessage(
          event: 'message',
          payload: {
            'chat_id': chatRoom.id,
            'message': {
              'id': clientId,
              'text': text,
              'is_image': false,
              'image_url': null,
              'sender_id': Supabase.instance.client.auth.currentUser?.id,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
          },
        );
        if (_peerId != null && _peerId!.isNotEmpty) {
          SupabaseApi.userChannel(uid: _peerId).sendBroadcastMessage(
            event: 'chat_update',
            payload: {
              'chat_id': chatRoom.id,
              'last_message_text': text,
              'last_message_at': DateTime.now().toUtc().toIso8601String(),
            },
          );
        }
      } catch (_) {}
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isSending: false);
    }
  }

  Future<void> sendImage(String imagePath) async {
    final now = DateTime.now();
    final formattedTime = DateFormat('h:mm a').format(now);
    state = state.copyWith(isSending: true);
    try {
      final bytes = await File(imagePath).readAsBytes();
      final path = await SupabaseApi.uploadChatImage(
        chatId: chatRoom.id,
        bytes: bytes,
      );
      final clientId = DateTime.now().millisecondsSinceEpoch.toString();
      await SupabaseApi.sendMessageOrg5(
        chatId: chatRoom.id,
        text: '',
        isImage: true,
        imageUrl: path,
        clientId: clientId,
      );
      String? signedUrl = path != null
          ? await SupabaseApi.getSignedChatImageUrl(path: path)
          : null;
      final newMessage = ChatMessageModel(
        id: clientId,
        text: signedUrl ?? '',
        isSentByMe: true,
        time: formattedTime,
        showDate: false,
        showTime: true,
        isImage: true,
      );
      state = state.copyWith(messages: [...state.messages, newMessage]);
      // Broadcast to room + user peer for list update
      SupabaseApi.roomChannel(chatRoom.id).sendBroadcastMessage(
        event: 'message',
        payload: {
          'chat_id': chatRoom.id,
          'message': {
            'id': clientId,
            'text': '',
            'is_image': true,
            'image_url': path,
            'sender_id': Supabase.instance.client.auth.currentUser?.id,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        },
      );
      if (_peerId != null && _peerId!.isNotEmpty) {
        SupabaseApi.userChannel(uid: _peerId).sendBroadcastMessage(
          event: 'chat_update',
          payload: {
            'chat_id': chatRoom.id,
            'last_message_text': '[image]',
            'last_message_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
    } catch (e) {
      // silent
    } finally {
      state = state.copyWith(isSending: false);
    }
  }

  DateTime? _firstCreatedAt() {
    if (state.messages.isEmpty) return null;
    // We don't store created_at; approximate from time string is unreliable.
    // For server pagination, load older by taking current oldest's time iso untracked → null implies first page only.
    return null;
  }

  void _subscribeRoom() {
    SupabaseApi.roomChannel(chatRoom.id)
      ..onBroadcast(event: 'message', callback: (payload, [ref]) {
        Map<String, dynamic>? map;
        if (payload is Map) {
          if (payload['payload'] is Map) {
            map = (payload['payload'] as Map).cast<String, dynamic>();
          } else {
            map = payload.cast<String, dynamic>();
          }
        }
        if (map != null) {
          final msg = (map['message'] ?? map);
          final text = (msg['text'] ?? '').toString();
          final createdAt = (msg['created_at'] ?? DateTime.now().toIso8601String()).toString();
          final sender = (msg['sender_id'] ?? '').toString();
          final isMine = sender == Supabase.instance.client.auth.currentUser?.id;
          final isImage = (msg['is_image'] as bool?) ?? false;
          if (isImage) {
            final imagePath = (msg['image_url'] ?? '').toString();
            SupabaseApi.getSignedChatImageUrl(path: imagePath).then((signed) {
              final model = ChatMessageModel(
                id: (msg['id'] ?? '').toString(),
                text: signed ?? '',
                isSentByMe: isMine,
                time: _formatTime(createdAt),
                showDate: false,
                showTime: true,
                isImage: true,
              );
              state = state.copyWith(messages: [...state.messages, model]);
            });
          } else {
            final model = ChatMessageModel(
              id: (msg['id'] ?? '').toString(),
              text: text,
              isSentByMe: isMine,
              time: _formatTime(createdAt),
              showDate: false,
              showTime: true,
              isImage: false,
            );
            state = state.copyWith(messages: [...state.messages, model]);
          }
        }
      })
      ..subscribe();
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal() ?? DateTime.now();
    return DateFormat('h:mm a').format(dt);
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
