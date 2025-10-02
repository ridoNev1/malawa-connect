// lib/features/home/providers/home_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/services/mock_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_api.dart';

final currentUserProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return <String, dynamic>{};
  final data = await SupabaseApi.getCustomerByMemberIdOrg5(memberId: uid);
  return data ?? <String, dynamic>{};
});

final discountsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await SupabaseApi.getDiscountsOrg5(onlyActive: true, limit: 20);
});

final presenceProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return null;
  try {
    return await SupabaseApi.getCurrentPresence();
  } catch (_) {
    return null;
  }
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

// Fetch locations for Org 5 (geofence), with fallback to mock when unauthenticated
final locationsOrg5Provider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid != null) {
    try {
      final list = await SupabaseApi.getLocationsOrg5();
      if (list.isNotEmpty) return list;
    } catch (_) {}
  }
  // Fallback to mock for dev/offline
  return await MockApi.instance.getLocations();
});
