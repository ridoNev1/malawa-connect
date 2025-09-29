import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';

class RoundedSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const RoundedSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ChipBadge extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? textColor;
  const ChipBadge(this.text, {super.key, this.color, this.textColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? MC.lightCream,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: textColor ?? MC.darkBrown,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String text;
  final bool me;
  const MessageBubble({super.key, required this.text, required this.me});
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: me ? const Radius.circular(18) : const Radius.circular(4),
      bottomRight: me ? const Radius.circular(4) : const Radius.circular(18),
    );
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: me ? MC.mediumBrown : const Color(0xFFF1F1F1),
        borderRadius: radius,
      ),
      child: Text(
        text,
        style: TextStyle(color: me ? Colors.white : const Color(0xFF333333)),
      ),
    );
  }
}
