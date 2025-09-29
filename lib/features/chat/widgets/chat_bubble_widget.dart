// lib/features/chat/widgets/chat_bubble_widget.dart
import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';
import '../models/chat_message_model.dart';

class ChatBubbleWidget extends StatelessWidget {
  final ChatMessageModel message;
  final String? avatarUrl;
  final int index;

  const ChatBubbleWidget({
    super.key,
    required this.message,
    this.avatarUrl,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isSentByMe;
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final mainAxis = isMe ? MainAxisAlignment.end : MainAxisAlignment.start;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: alignment,
            child: Row(
              mainAxisAlignment: mainAxis,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: _buildAvatar(),
                  ),
                Flexible(child: _buildBubble(context, isMe)),
              ],
            ),
          ),
          if (message.showTime)
            Padding(
              padding: EdgeInsets.only(
                left: isMe ? 0 : 48,
                right: isMe ? 8 : 0,
                top: 4,
              ),
              child: Text(
                message.time,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: MC.darkBrown.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person, size: 16, color: MC.darkBrown),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        avatarUrl!,
        width: 28,
        height: 28,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: MC.darkBrown.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, size: 16, color: MC.darkBrown),
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context, bool isMe) {
    final bgColor = isMe ? MC.darkBrown : Colors.white;
    final textColor = isMe ? Colors.white : MC.darkBrown;
    final border = Border.all(color: Colors.grey[200]!, width: isMe ? 0 : 1);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );

    Widget content;
    if (message.isImage) {
      // Simple image placeholder to avoid platform-specific File handling
      content = ClipRRect(
        borderRadius: radius,
        child: Container(
          color: Colors.grey[200],
          width: 200,
          height: 200,
          alignment: Alignment.center,
          child: const Icon(Icons.image, color: Colors.grey, size: 48),
        ),
      );
    } else {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: radius,
          border: border,
          boxShadow: [
            if (!isMe)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Text(
          message.text,
          style: TextStyle(color: textColor, fontSize: 14),
        ),
      );
    }

    return content;
  }
}
