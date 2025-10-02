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
  final String? peerId;

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
    this.peerId,
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
    String? peerId,
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
      peerId: peerId ?? this.peerId,
    );
  }
}

class ChatRoomNotifier extends Notifier<ChatRoomState> {
  ChatRoomNotifier(this.chatRoom);
  final ChatRoomModel chatRoom;
  String? _peerId;

  @override
  ChatRoomState build() {
    return ChatRoomState(chatRoom: chatRoom, messages: [], peerId: null);
  }

  Future<void> loadRoom() async {
    final header = await SupabaseApi.getRoomHeaderOrg5(chatId: chatRoom.id);
    if (header != null) {
      _peerId = (header['peer_id'] ?? header['peerId'])?.toString();
      state = state.copyWith(
        peerId: _peerId,
        chatRoom: ChatRoomModel(
          id: (header['id'] ?? chatRoom.id).toString(),
          name: (header['name'] ?? '').toString(),
          avatar: (header['avatar'] ?? '').toString(),
          isOnline: (header['isOnline'] as bool?) ?? false,
          lastSeen: (header['lastSeen'] ?? '').toString(),
          locationName: (header['locationName'] ?? header['location_name'])?.toString(),
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
        final isImg = ((json['isImage'] ?? json['is_image'] ?? json['isimage']) as bool?) ?? false;
        bool isMine = false;
        final mineRaw = (json['isMine'] ?? json['is_mine'] ?? json['ismine']);
        if (mineRaw is bool) {
          isMine = mineRaw;
        } else if (mineRaw != null) {
          final s = mineRaw.toString().toLowerCase();
          isMine = (s == 'true' || s == 't' || s == '1');
        }
        String text = (json['text'] ?? '').toString();
        final imgPathAny = (json['imageUrl'] ?? json['image_url'] ?? json['imageurl'] ?? '').toString();
        if (isImg && imgPathAny.isNotEmpty) {
          final signed = await SupabaseApi.getSignedChatImageUrl(path: imgPathAny);
          if (signed != null) text = signed;
        }
        final id = (json['id'] ?? '').toString();
        
        messages.add(ChatMessageModel(
          id: id,
          text: text,
          isSentByMe: isMine,
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
        final isImg = ((json['isImage'] ?? json['is_image'] ?? json['isimage']) as bool?) ?? false;
        bool isMine = false;
        final mineRaw = (json['isMine'] ?? json['is_mine'] ?? json['ismine']);
        if (mineRaw is bool) {
          isMine = mineRaw;
        } else if (mineRaw != null) {
          final s = mineRaw.toString().toLowerCase();
          isMine = (s == 'true' || s == 't' || s == '1');
        }
        String text = (json['text'] ?? '').toString();
        final imgPathAny = (json['imageUrl'] ?? json['image_url'] ?? json['imageurl'] ?? '').toString();
        if (isImg && imgPathAny.isNotEmpty) {
          final signed = await SupabaseApi.getSignedChatImageUrl(path: imgPathAny);
          if (signed != null) text = signed;
        }
        final id = (json['id'] ?? '').toString();
        // ignore: avoid_print
        print('[debugging] chat_room.loadMore.row id=' + id + ' isMine=' + isMine.toString() + ' isImage=' + isImg.toString());
        older.add(ChatMessageModel(
          id: id,
          text: text,
          isSentByMe: isMine,
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
    state = state.copyWith(isSending: true);

    try {
      
      final res = await SupabaseApi.sendMessageOrg5(
        chatId: chatRoom.id,
        text: text,
        isImage: false,
      );
      // Append using server result
      if (res != null) {
        final msgId = (res['id'] ?? '').toString();
        final createdAt = (res['created_at'] ?? now.toIso8601String()).toString();
        final model = ChatMessageModel(
          id: msgId.isNotEmpty ? msgId : DateTime.now().millisecondsSinceEpoch.toString(),
          text: text,
          isSentByMe: true,
          time: _formatTime(createdAt),
          showDate: false,
          showTime: true,
          isImage: false,
        );
        state = state.copyWith(messages: [...state.messages, model]);
        
        // Broadcast with server id
        try {
          SupabaseApi.roomChannel(chatRoom.id).sendBroadcastMessage(
            event: 'message',
            payload: {
              'chat_id': chatRoom.id,
              'message': {
                'id': model.id,
                'text': text,
                'is_image': false,
                'image_url': null,
                'sender_id': Supabase.instance.client.auth.currentUser?.id,
                'created_at': createdAt,
              },
            },
          );
          if (_peerId != null && _peerId!.isNotEmpty) {
            SupabaseApi.userChannel(uid: _peerId).sendBroadcastMessage(
              event: 'chat_update',
              payload: {
                'chat_id': chatRoom.id,
                'last_message_text': text,
                'last_message_at': createdAt,
              },
            );
          }
        } catch (_) {}
      }
      // Broadcast to room channel so other device updates instantly
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isSending: false);
    }
  }

  Future<void> sendImage(String imagePath) async {
    final now = DateTime.now();
    state = state.copyWith(isSending: true);
    try {
      final bytes = await File(imagePath).readAsBytes();
      final path = await SupabaseApi.uploadChatImage(
        chatId: chatRoom.id,
        bytes: bytes,
      );
      final res = await SupabaseApi.sendMessageOrg5(
        chatId: chatRoom.id,
        text: '',
        isImage: true,
        imageUrl: path,
      );
      String? signedUrl = path != null
          ? await SupabaseApi.getSignedChatImageUrl(path: path)
          : null;
      if (res != null) {
        final msgId = (res['id'] ?? '').toString();
        final createdAt = (res['created_at'] ?? now.toIso8601String()).toString();
        final newMessage = ChatMessageModel(
          id: msgId.isNotEmpty ? msgId : DateTime.now().millisecondsSinceEpoch.toString(),
          text: signedUrl ?? '',
          isSentByMe: true,
          time: _formatTime(createdAt),
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
              'id': newMessage.id,
              'text': '',
              'is_image': true,
              'image_url': path,
              'sender_id': Supabase.instance.client.auth.currentUser?.id,
              'created_at': createdAt,
            },
          },
        );
        if (_peerId != null && _peerId!.isNotEmpty) {
          SupabaseApi.userChannel(uid: _peerId).sendBroadcastMessage(
            event: 'chat_update',
            payload: {
              'chat_id': chatRoom.id,
              'last_message_text': '[image]',
              'last_message_at': createdAt,
            },
          );
        }
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
          final msgId = (msg['id'] ?? '').toString();
          
          // Deduplicate if message with same id already exists in state
          if (msgId.isNotEmpty && state.messages.any((m) => m.id == msgId)) {
            
            return;
          }
          if (isImage) {
            final imagePath = (msg['image_url'] ?? '').toString();
            SupabaseApi.getSignedChatImageUrl(path: imagePath).then((signed) {
              final model = ChatMessageModel(
                id: msgId.isNotEmpty ? msgId : DateTime.now().millisecondsSinceEpoch.toString(),
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
              id: msgId.isNotEmpty ? msgId : DateTime.now().millisecondsSinceEpoch.toString(),
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
