import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import '../../../core/theme/theme.dart';
import '../models/chat_room_model.dart';
import '../providers/chat_room_provider.dart';
import '../providers/chat_list_provider.dart';
import '../widgets/chat_bubble_widget.dart';
import '../widgets/chat_input_widget.dart';
import '../widgets/emoji_picker_widget.dart';

class ChatRoomPage extends ConsumerStatefulWidget {
  final String chatId;
  final String name;
  final String avatar;

  const ChatRoomPage({
    super.key,
    required this.chatId,
    required this.name,
    required this.avatar,
  });

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final image_picker.ImagePicker _imagePicker = image_picker.ImagePicker();

  late final ChatRoomModel _chatRoom;

  @override
  void initState() {
    super.initState();
    // Create chat room model once
    _chatRoom = ChatRoomModel(
      id: widget.chatId,
      name: widget.name,
      avatar: widget.avatar,
      isOnline: true,
      lastSeen: 'Malawa Atrium',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatRoomProviderFamily(_chatRoom).notifier).loadMessages();
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        final chatState = ref.read(chatRoomProviderFamily(_chatRoom));
        if (chatState.showEmojiPicker) {
          ref
              .read(chatRoomProviderFamily(_chatRoom).notifier)
              .toggleEmojiPicker();
        }
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatRoomProviderFamily(_chatRoom));
    final chatNotifier = ref.read(chatRoomProviderFamily(_chatRoom).notifier);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Chat Header
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
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
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: MC.darkBrown,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // User Avatar
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(
                          widget.avatar,
                          width: 45,
                          height: 45,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 45,
                              height: 45,
                              color: const Color.fromARGB(22, 62, 39, 35),
                              child: const Icon(
                                Icons.person,
                                size: 22,
                                color: MC.darkBrown,
                              ),
                            );
                          },
                        ),
                      ),
                      // Online indicator
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 15,
                          height: 15,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // User Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: MC.darkBrown,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Malawa Atrium',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[600],
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

            // Chat Messages
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: chatState.messages.length,
                  itemBuilder: (context, index) {
                    final message = chatState.messages[index];
                    return ChatBubbleWidget(
                      message: message,
                      avatarUrl: widget.avatar,
                      index: index,
                    );
                  },
                ),
              ),
            ),

            if (chatState.showEmojiPicker && !_focusNode.hasFocus)
              EmojiPickerWidget(
                onEmojiSelected: (emoji) {
                  _insertEmoji(emoji);
                },
              ),

            // Message Input
            ChatInputWidget(
              controller: _messageController,
              focusNode: _focusNode,
              showEmojiPicker: chatState.showEmojiPicker,
              onSendMessage: _sendMessage,
              onToggleEmojiPicker: chatNotifier.toggleEmojiPicker,
              onShowImageOptions: _showImageSourceOptions,
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    ref
        .read(chatRoomProviderFamily(_chatRoom).notifier)
        .sendMessage(_messageController.text);

    // Update chat list with last message
    ref
        .read(chatListProvider.notifier)
        .updateLastMessage(widget.chatId, _messageController.text, true);

    _messageController.clear();

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _insertEmoji(String emoji) {
    final text = _messageController.text + emoji;
    _messageController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pilih Sumber Gambar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildImageOption(Icons.camera_alt, 'Kamera', () {
                  Navigator.pop(context);
                  _pickImageFromCamera();
                }),
                _buildImageOption(Icons.image, 'Galeri', () {
                  Navigator.pop(context);
                  _pickImageFromGallery();
                }),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildImageOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: MC.darkBrown),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final image_picker.XFile? image = await _imagePicker.pickImage(
        source: image_picker.ImageSource.camera,
        imageQuality: 70,
      );

      if (image != null) {
        _sendImageMessage(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal mengambil gambar: $e')));
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final image_picker.XFile? image = await _imagePicker.pickImage(
        source: image_picker.ImageSource.gallery,
        imageQuality: 70,
      );

      if (image != null) {
        _sendImageMessage(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memilih gambar: $e')));
      }
    }
  }

  void _sendImageMessage(image_picker.XFile image) {
    ref.read(chatRoomProviderFamily(_chatRoom).notifier).sendImage(image.path);

    // Update chat list with last message
    ref
        .read(chatListProvider.notifier)
        .updateLastMessage(widget.chatId, 'Gambar', true);

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }
}
