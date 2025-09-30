// lib/features/connect/providers/member_detail_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/mock_api.dart';

final memberByIdProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  return await MockApi.instance.getMemberById(userId);
});

