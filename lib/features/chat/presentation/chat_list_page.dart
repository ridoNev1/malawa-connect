// lib/features/chat/pages/chat_list_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';
import '../providers/chat_list_provider.dart';
import 'chat_room_page.dart';

class ChatListPage extends ConsumerStatefulWidget {
  const ChatListPage({super.key});

  @override
  ConsumerState<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends ConsumerState<ChatListPage> {
  final TextEditingController _searchController = TextEditingController();

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
    _searchController.dispose();
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chat',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: MC.darkBrown,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Percakapan dengan teman dan partner',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color.fromARGB(50, 0, 0, 0),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari percakapan...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                            child: Icon(Icons.clear, color: Colors.grey[400]),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 20,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Chat List
            Expanded(
              child: chatListState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredChatRooms.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isNotEmpty
                            ? 'Tidak ada hasil pencarian'
                            : 'Tidak ada percakapan',
                        style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                      ),
                    )
                  : AnimationLimiter(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: filteredChatRooms.length,
                        itemBuilder: (context, index) {
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
    return GestureDetector(
      onTap: () {
        // Mark as read when navigating to chat room
        chatListNotifier.markAsRead(chat['id']);

        // Navigate to chat room without bottom navigation
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatRoomPage(
              chatId: chat['id'],
              name: chat['name'],
              avatar: chat['avatar'],
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color.fromARGB(50, 0, 0, 0),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar with online indicator
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: Image.network(
                    chat['avatar'],
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 60,
                        height: 60,
                        color: const Color.fromARGB(22, 62, 39, 35),
                        child: const Icon(
                          Icons.person,
                          size: 30,
                          color: MC.darkBrown,
                        ),
                      );
                    },
                  ),
                ),
                // Online indicator
                if ((chat['isOnline'] as bool?) == true)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: MC.darkBrown,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(chat['lastMessageTime']),
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          chat['lastMessage'],
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      // Unread count
                      if ((chat['unreadCount'] ?? 0) > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: MC.accentOrange,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${chat['unreadCount']}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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
