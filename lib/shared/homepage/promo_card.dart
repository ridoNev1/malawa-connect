import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class PromoCard extends StatelessWidget {
  final String title;
  final String description;
  final String validUntil;
  final bool isPrimary;

  const PromoCard({
    super.key,
    required this.title,
    required this.description,
    required this.validUntil,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2),
        ],
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 100,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: isPrimary ? MC.gradientPrimary : MC.gradientSecondary,
              ),
              child: Icon(
                isPrimary ? Icons.card_giftcard_rounded : Icons.percent_rounded,
                size: 48,
                color: isPrimary ? Colors.white : MC.accentOrange,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Berlaku hingga $validUntil',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
