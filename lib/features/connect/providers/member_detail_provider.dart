// lib/features/connect/providers/member_detail_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/supabase_api.dart';

final memberByIdProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  // userId can be legacy id (string) or member_id uuid (string)
  final data = await SupabaseApi.getMemberDetailOrg5(id: userId);
  if (kDebugMode) {
    // ignore: avoid_print
    print('[DEBUG] member detail id=$userId => ${data ?? {}}');
  }
  return data;
});
