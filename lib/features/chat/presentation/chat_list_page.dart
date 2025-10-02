// lib/features/chat/pages/chat_list_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';
import '../providers/chat_list_provider.dart';
import '../../connect/providers/inapp_presence_provider.dart';
import 'chat_room_page.dart';

class ChatListPage extends ConsumerStatefulWidget {
  const ChatListPage({super.key});

  @override
  ConsumerState<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends ConsumerState<ChatListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Load chat rooms when page is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatListProvider.notifier).loadChatRooms();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatListState = ref.watch(chatListProvider);
    final chatListNotifier = ref.read(chatListProvider.notifier);

    // Filter chat rooms based on search query
    List<Map<String, dynamic>> filteredChatRooms = chatListState.chatRooms
        .where((chat) {
          final name = chat['name'].toString().toLowerCase();
          final lastMessage = chat['lastMessage'].toString().toLowerCase();
          final searchQuery = _searchController.text.toLowerCase();
          return name.contains(searchQuery) ||
              lastMessage.contains(searchQuery);
        })
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Header dengan gradient
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [MC.darkBrown, MC.darkBrown.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 16.0,
                  top: 20.0,
                  bottom: 20.0,
                  right: 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Percakapan dengan teman dan partner',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar dengan efek glassmorphism
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 16.0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: MC.darkBrown),
                  decoration: InputDecoration(
                    hintText: 'Cari percakapan...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(
                      Icons.search,
                      color: MC.darkBrown.withOpacity(0.7),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                            child: Icon(
                              Icons.clear,
                              color: MC.darkBrown.withOpacity(0.7),
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 20,
                    ),
                  ),
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    if (!mounted) return;
                    setState(() {});
                  });
                },
                ),
              ),
            ),

            // Chat List
            Expanded(
              child: chatListState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredChatRooms.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isNotEmpty
                                ? 'Tidak ada hasil pencarian'
                                : 'Belum ada percakapan',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (scrollInfo) {
                        if (scrollInfo.metrics.pixels >=
                                scrollInfo.metrics.maxScrollExtent - 200 &&
                            !chatListState.isLoadingMore &&
                            chatListState.hasMore) {
                          ref.read(chatListProvider.notifier).loadMore();
                        }
                        return false;
                      },
                      child: AnimationLimiter(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: filteredChatRooms.length + 1,
                          itemBuilder: (context, index) {
                            if (index == filteredChatRooms.length) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12.0),
                                child: Center(
                                  child: chatListState.isLoadingMore
                                      ? const CircularProgressIndicator()
                                      : (chatListState.hasMore
                                          ? const SizedBox.shrink()
                                          : Text(
                                              'Semua percakapan telah ditampilkan',
                                              style: TextStyle(
                                                color: Colors.grey[500],
                                              ),
                                            )),
                                ),
                              );
                            }
                            final chat = filteredChatRooms[index];
                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              child: SlideAnimation(
                                verticalOffset: 50.0,
                                child: FadeInAnimation(
                                  child: _buildChatListItem(
                                    chat: chat,
                                    index: index,
                                    chatListNotifier: chatListNotifier,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.go('/connect');
              break;
            case 2:
              context.go('/chat');
              break;
            case 3:
              context.go('/profiles');
              break;
          }
        },
      ),
    );
  }

  Widget _buildChatListItem({
    required Map<String, dynamic> chat,
    required int index,
    required ChatListNotifier chatListNotifier,
  }) {
    final bool isUnread = (chat['unreadCount'] ?? 0) > 0;
    final bool isOnline = (chat['isOnline'] as bool?) == true;

    return GestureDetector(
      onTap: () {
        // Mark as read when navigating to chat room
        chatListNotifier.markAsRead(chat['id']);

        // Navigate to chat room without bottom navigation
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatRoomPage(
              chatId: chat['id'],
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: isUnread ? Colors.white : Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar with in-app indicator (avatar-only)
            Stack(
              children: [
                Hero(
                  tag: 'avatar_${chat['id']}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: (() {
                      final String url = (chat['avatar'] ?? '').toString();
                      final bool valid = url.isNotEmpty &&
                          (url.startsWith('http://') || url.startsWith('https://'));
                      if (valid) {
                        return Image.network(
                          url,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 60,
                              height: 60,
                              color: MC.darkBrown.withOpacity(0.1),
                              child: const Icon(
                                Icons.person,
                                size: 30,
                                color: MC.darkBrown,
                              ),
                            );
                          },
                        );
                      }
                      return Container(
                        width: 60,
                        height: 60,
                        color: MC.darkBrown.withOpacity(0.1),
                        child: const Icon(
                          Icons.person,
                          size: 30,
                          color: MC.darkBrown,
                        ),
                      );
                    })(),
                  ),
                ),
                // In-app indicator (uses member_id parsed from avatar url)
                Consumer(builder: (context, ref, _) {
                  String? memberIdFromAvatar() {
                    final url = (chat['avatar'] ?? '').toString();
                    final idx = url.indexOf('/org5/');
                    if (idx == -1) return null;
                    final start = idx + '/org5/'.length;
                    final rest = url.substring(start);
                    final segEnd = rest.indexOf('/');
                    if (segEnd == -1) return null;
                    final uid = rest.substring(0, segEnd);
                    return uid;
                  }
                  final uid = memberIdFromAvatar();
                  final inApp = uid != null &&
                      ref.watch(inAppPresenceProvider).activeUids.contains(uid);
                  return Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: inApp ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(width: 16),
            // Chat Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          chat['name'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: MC.darkBrown,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime((chat['lastMessageTime'] as String?) ?? ''),
                        style: TextStyle(
                          fontSize: 12,
                          color: isUnread ? MC.accentOrange : Colors.grey[500],
                          fontWeight: isUnread
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final raw = (chat['lastMessage'] ?? '').toString().trim();
                            final preview = raw.isEmpty
                                ? 'Belum ada percakapan'
                                : (raw == '[image]' ? 'Mengirim gambar' : raw);
                            return Text(
                              preview,
                              style: TextStyle(
                                fontSize: 14,
                                color: isUnread ? Colors.black87 : Colors.grey[600],
                                fontWeight: isUnread
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            );
                          },
                        ),
                      ),
                      // Unread count dengan desain baru
                      if (isUnread)
                        Container(
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: MC.accentOrange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              '${chat['unreadCount']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String timeString) {
    try {
      final DateTime now = DateTime.now();
      final DateTime messageTime = DateTime.parse(timeString);

      if (now.difference(messageTime).inDays == 0) {
        return DateFormat('h:mm a').format(messageTime);
      } else if (now.difference(messageTime).inDays == 1) {
        return 'Yesterday';
      } else if (now.difference(messageTime).inDays < 7) {
        return DateFormat('EEEE').format(messageTime);
      } else {
        return DateFormat('MMM d').format(messageTime);
      }
    } catch (e) {
      return '';
    }
  }
}
