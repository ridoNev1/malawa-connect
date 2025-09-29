import 'package:flutter/material.dart';

class EmojiPickerWidget extends StatelessWidget {
  final ValueChanged<String> onEmojiSelected;

  const EmojiPickerWidget({super.key, required this.onEmojiSelected});

  static const _emojis = [
    '😀',
    '😁',
    '😂',
    '🤣',
    '😊',
    '😍',
    '😘',
    '😎',
    '😇',
    '🙂',
    '🙃',
    '😉',
    '😌',
    '😜',
    '🤩',
    '🤗',
    '🤔',
    '🤨',
    '😴',
    '😪',
    '😷',
    '🤒',
    '🤕',
    '🤧',
    '🥳',
    '🤤',
    '🥰',
    '😅',
    '😆',
    '😏',
    '😬',
    '😮',
    '👍',
    '👎',
    '👏',
    '🙌',
    '🙏',
    '💪',
    '🔥',
    '✨',
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🤍',
    '☕',
    '🍕',
    '🍔',
    '🍟',
    '🌮',
    '🍣',
    '🍰',
    '🍫',
    '🍩',
    '🍺',
    '🍻',
    '🍷',
    '🍹',
    '🏃',
    '🚴',
    '🏋️',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: GridView.builder(
        itemCount: _emojis.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
        ),
        itemBuilder: (context, index) {
          final emoji = _emojis[index];
          return InkWell(
            onTap: () => onEmojiSelected(emoji),
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          );
        },
      ),
    );
  }
}
