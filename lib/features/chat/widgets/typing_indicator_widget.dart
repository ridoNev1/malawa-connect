// lib/features/chat/widgets/typing_indicator_widget.dart
import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class TypingIndicatorWidget extends StatelessWidget {
  final String? avatarUrl;

  const TypingIndicatorWidget({super.key, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          if (avatarUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: (() {
                final String url = avatarUrl!.trim();
                final bool valid = url.isNotEmpty &&
                    (url.startsWith('http://') || url.startsWith('https://'));
                if (valid) {
                  return Image.network(
                    url,
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 30,
                        height: 30,
                        color: MC.darkBrown.withOpacity(0.1),
                        child: const Icon(
                          Icons.person,
                          size: 15,
                          color: MC.darkBrown,
                        ),
                      );
                    },
                  );
                }
                return Container(
                  width: 30,
                  height: 30,
                  color: MC.darkBrown.withOpacity(0.1),
                  child: const Icon(
                    Icons.person,
                    size: 15,
                    color: MC.darkBrown,
                  ),
                );
              })(),
            ),
          if (avatarUrl != null) const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypingDot(0),
                const SizedBox(width: 8),
                Text(
                  'Sedang mengetik...',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      height: 8,
      width: 8,
      decoration: BoxDecoration(color: MC.darkBrown, shape: BoxShape.circle),
    );
  }
}
