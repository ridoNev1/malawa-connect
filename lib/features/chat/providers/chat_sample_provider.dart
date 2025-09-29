// lib/features/chat/providers/chat_sample_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sample_data.dart';

final chatListSampleProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return getChatListSampleData();
});

final chatRoomSampleProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return getChatRoomSampleMessages();
});
