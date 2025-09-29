import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme.dart';

class ChatInputWidget extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showEmojiPicker;
  final VoidCallback onSendMessage;
  final VoidCallback onToggleEmojiPicker;
  final VoidCallback onShowImageOptions;

  const ChatInputWidget({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.showEmojiPicker,
    required this.onSendMessage,
    required this.onToggleEmojiPicker,
    required this.onShowImageOptions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Column(
        children: [
          if (showEmojiPicker) const SizedBox(height: 8),
          Row(
            children: [
              // Attachment Button
              GestureDetector(
                onTap: onShowImageOptions,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_circle,
                    size: 24,
                    color: MC.darkBrown,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Message Input
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            hintText: 'Ketik pesan...',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 20,
                            ),
                          ),
                        ),
                      ),
                      // Emoji Button
                      GestureDetector(
                        onTap: onToggleEmojiPicker,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Icon(
                            Icons.emoji_emotions_outlined,
                            color: showEmojiPicker
                                ? MC.accentOrange
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Send Button
              GestureDetector(
                onTap: controller.text.isNotEmpty ? onSendMessage : null,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: controller.text.isNotEmpty
                        ? MC.darkBrown
                        : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.send,
                    size: 20,
                    color: controller.text.isNotEmpty
                        ? Colors.white
                        : Colors.grey[500],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
