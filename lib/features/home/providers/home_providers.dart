// lib/features/home/providers/home_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/services/mock_api.dart';

final currentUserProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await MockApi.instance.getCurrentUser();
});

final discountsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await MockApi.instance.getDiscounts();
});

final presenceProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  return await MockApi.instance.getPresence();
});

final membershipSummaryProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final points = (user['total_point'] as int?) ?? 0;
  String tier;
  if (points >= 1000) {
    tier = 'Platinum Member';
  } else if (points >= 500) {
    tier = 'Gold Member';
  } else if (points >= 100) {
    tier = 'Silver Member';
  } else {
    tier = 'Bronze Member';
  }

  // Map created_at to a human-readable join date string
  final createdAtIso = (user['created_at'] ?? '').toString();
  String joinedAt = '';
  final createdAt = DateTime.tryParse(createdAtIso);
  if (createdAt != null) {
    joinedAt = DateFormat('dd MMM yyyy').format(createdAt.toLocal());
  }

  return {
    'membershipType': tier,
    'points': points,
    // Keep key name for existing widget API; now it carries joinedAt value
    'validUntil': joinedAt,
  };
});
