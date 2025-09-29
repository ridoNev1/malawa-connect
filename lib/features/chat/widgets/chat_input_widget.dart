import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme.dart';

class ChatInputWidget extends ConsumerStatefulWidget {
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
  ConsumerState<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends ConsumerState<ChatInputWidget> {
  bool _hasText = false;
  bool _isTextFieldFocused = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateTextState);
    widget.focusNode.addListener(_handleFocusChange);
    _updateTextState();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateTextState);
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _updateTextState() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  void _handleFocusChange() {
    setState(() {
      _isTextFieldFocused = widget.focusNode.hasFocus;
    });

    // Jika text field difokuskan dan emoji picker sedang terbuka, tutup emoji picker
    if (widget.focusNode.hasFocus && widget.showEmojiPicker) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onToggleEmojiPicker();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Column(
        children: [
          if (widget.showEmojiPicker && !_isTextFieldFocused)
            const SizedBox(height: 8),
          Row(
            children: [
              // Attachment Button
              GestureDetector(
                onTap: widget.onShowImageOptions,
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

              // Input Field Area - Terpisah dari tombol emoji
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(30), // Lebih rounded
                  ),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    decoration: InputDecoration(
                      hintText: 'Ketik pesan...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(99.0),
                        borderSide: const BorderSide(
                          color: Colors.grey,
                          width: 1.0,
                        ),
                      ),
                      border: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(99.0),
                        borderSide: const BorderSide(
                          color: Colors.grey,
                          width: 1.0,
                        ),
                      ),
                      focusedErrorBorder: InputBorder.none,

                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 20,
                      ),
                    ),
                    onTap: () {
                      // Pastikan fokus tetap pada input field
                      FocusScope.of(context).requestFocus(widget.focusNode);
                    },
                  ),
                ),
              ),

              // Spacing antara input field dan tombol emoji
              const SizedBox(width: 8),

              // Emoji Button - Sekarang terpisah dari input field
              GestureDetector(
                onTap: () {
                  // Jika text field sedang difokuskan, unfocus dulu
                  if (_isTextFieldFocused) {
                    widget.focusNode.unfocus();
                  }

                  // Toggle emoji picker
                  widget.onToggleEmojiPicker();
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.emoji_emotions_outlined,
                    color: widget.showEmojiPicker && !_isTextFieldFocused
                        ? MC.accentOrange
                        : Colors.grey,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Send Button
              GestureDetector(
                onTap: _hasText ? widget.onSendMessage : null,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _hasText ? MC.darkBrown : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.send,
                    size: 20,
                    color: _hasText ? Colors.white : Colors.grey[500],
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
