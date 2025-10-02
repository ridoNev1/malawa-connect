import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseApi {
  static SupabaseClient get _c => Supabase.instance.client;

  // Upsert customer for Org 5 on login (RPC)
  static Future<Map<String, dynamic>?> syncCustomerLoginOrg5({
    required String phone62,
    String? fullName,
    int? locationId,
  }) async {
    final params = {
      'p_phone': phone62,
      if (fullName != null) 'p_full_name': fullName,
      if (locationId != null) 'p_location_id': locationId,
    };
    final res = await _c.rpc('auth_sync_customer_login_org5', params: params);
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  // Get customer by current auth uid for Org 5 (RPC)
  static Future<Map<String, dynamic>?> getCustomerByMemberIdOrg5({
    String? memberId,
  }) async {
    final uid = memberId ?? _c.auth.currentUser?.id;
    if (uid == null) return null;
    final res = await _c.rpc(
      'get_customer_detail_by_member_id_org5',
      params: {'p_member_id': uid},
    );
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  // Presence RPCs (Org 5)
  static Future<Map<String, dynamic>?> checkIn({
    required int locationId,
  }) async {
    if (_c.auth.currentUser == null) return null;
    final res = await _c.rpc(
      'presence_check_in_org5',
      params: {'p_location_id': locationId},
    );
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  static Future<void> heartbeat() async {
    if (_c.auth.currentUser == null) return;
    await _c.rpc('presence_heartbeat_org5');
  }

  static Future<void> checkOut() async {
    if (_c.auth.currentUser == null) return;
    await _c.rpc('presence_check_out_org5');
  }

  static Future<Map<String, dynamic>?> getCurrentPresence() async {
    final res = await _c.rpc('get_current_presence_org5');
    if (res == null) return null;
    if (res is Map<String, dynamic>) return res;
    // Some drivers return List<Map> with single row; normalize
    if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
      return res.first as Map<String, dynamic>;
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getLocationsOrg5() async {
    final res = await _c.rpc('get_locations_org5');
    if (res is List) {
      return res.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  // ==========================
  // Chat (Org 5) — RPC helpers
  // ==========================

  static Future<Map<String, dynamic>?> getOrCreateDirectChat({
    required String peerId,
  }) async {
    final res = await _c.rpc('get_or_create_direct_chat_org5', params: {
      'p_peer_id': peerId,
    });
    if (res is Map<String, dynamic>) return res;
    if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
      return res.first as Map<String, dynamic>;
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getChatListOrg5({
    String search = '',
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _c.rpc('get_chat_list_org5', params: {
      'p_search': search,
      'p_limit': limit,
      'p_offset': offset,
    });
    if (res is List) {
      final list = res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      // Normalize keys to camelCase used by UI
      final norm = list.map((m) {
        return {
          ...m,
          'lastMessage': m['lastMessage'] ?? m['lastmessage'],
          'lastMessageTime': m['lastMessageTime'] ?? m['lastmessagetime'],
          'unreadCount': m['unreadCount'] ?? m['unreadcount'],
          'isOnline': m['isOnline'] ?? m['isonline'],
        };
      }).toList();
      return norm;
    }
    return const [];
  }

  static Future<Map<String, dynamic>?> getRoomHeaderOrg5({
    required String chatId,
  }) async {
    final res = await _c.rpc('get_room_header_org5', params: {
      'p_chat_id': chatId,
    });
    if (res is Map<String, dynamic>) return res;
    if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
      return res.first as Map<String, dynamic>;
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getMessagesOrg5({
    required String chatId,
    int limit = 50,
    DateTime? before,
  }) async {
    final params = <String, dynamic>{
      'p_chat_id': chatId,
      'p_limit': limit,
      if (before != null) 'p_before': before.toUtc().toIso8601String(),
    };
    final res = await _c.rpc('get_messages_org5', params: params);
    if (res is List) return res.whereType<Map<String, dynamic>>().toList();
    return const [];
  }

  static Future<Map<String, dynamic>?> sendMessageOrg5({
    required String chatId,
    required String text,
    bool isImage = false,
    String? imageUrl,
    String? clientId,
  }) async {
    bool _isValidUuid(String s) {
      final r = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\$');
      return r.hasMatch(s);
    }
    final params = <String, dynamic>{
      'p_chat_id': chatId,
      'p_text': text,
      'p_is_image': isImage,
      if (imageUrl != null) 'p_image_url': imageUrl,
      if (clientId != null && _isValidUuid(clientId)) 'p_client_id': clientId,
    };
    final res = await _c.rpc('send_message_org5', params: params);
    if (res is Map<String, dynamic>) return res;
    if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
      return res.first as Map<String, dynamic>;
    }
    return null;
  }

  static Future<void> markReadOrg5({required String chatId}) async {
    await _c.rpc('mark_read_org5', params: {'p_chat_id': chatId});
  }

  // Realtime Channels helpers (client broadcast)
  static RealtimeChannel userChannel({String? uid}) {
    final id = uid ?? _c.auth.currentUser?.id;
    return _c.channel('user:${id ?? 'unknown'}');
  }

  static RealtimeChannel roomChannel(String chatId) {
    return _c.channel('room:$chatId');
  }

  // Chat images (private bucket)
  static const String _chatBucket = 'chatimages';

  static Future<String?> uploadChatImage({
    required String chatId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'org5/$chatId/$ts.jpg';
    await _c.storage
        .from(_chatBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return path;
  }

  static Future<String?> getSignedChatImageUrl({
    required String path,
    int expiresIn = 60 * 60,
  }) async {
    final result = await _c.storage.from(_chatBucket).createSignedUrl(path, expiresIn);
    if (result is String) return result;
    if (result is Map) {
      final map = Map<String, dynamic>.from(result as Map);
      final s = map['signedUrl'] ?? map['signed_url'];
      if (s is String) return s;
    }
    return null;
  }

  // Upload avatar image to 'avatars' bucket under org5/<uid>/profile.jpg
  static Future<String?> uploadAvatar({
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return null;
    final path = 'org5/$uid/profile.jpg';
    await _c.storage
        .from('memberavatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    final url = _c.storage.from('memberavatars').getPublicUrl(path);
    return url;
  }

  // Upload gallery image, returns public URL
  static Future<String?> uploadGalleryImage({
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'org5/$uid/gallery/$ts.jpg';
    await _c.storage
        .from('membergallery')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    final url = _c.storage.from('membergallery').getPublicUrl(path);
    return url;
  }

  // Update customer profile for org 5 via RPC
  static Future<Map<String, dynamic>?> updateCustomerProfileOrg5({
    String? fullName,
    String? preference,
    List<String>? interests,
    List<String>? galleryImages,
    String? profileImageUrl,
    DateTime? dateOfBirth,
    String? gender,
    bool? visibility,
    double? searchRadiusKm,
    int? locationId,
    String? notes,
  }) async {
    final params = <String, dynamic>{
      if (fullName != null) 'p_full_name': fullName,
      if (preference != null) 'p_preference': preference,
      if (interests != null) 'p_interests': interests,
      if (galleryImages != null) 'p_gallery_images': galleryImages,
      if (profileImageUrl != null) 'p_profile_image_url': profileImageUrl,
      if (dateOfBirth != null)
        'p_date_of_birth': dateOfBirth.toIso8601String().substring(0, 10),
      if (gender != null) 'p_gender': gender,
      if (visibility != null) 'p_visibility': visibility,
      if (searchRadiusKm != null) 'p_search_radius_km': searchRadiusKm,
      if (locationId != null) 'p_location_id': locationId,
      if (notes != null) 'p_notes': notes,
    };
    final res = await _c.rpc('update_customer_profile_org5', params: params);
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  // Discounts (Org 5)
  static Future<List<Map<String, dynamic>>> getDiscountsOrg5({
    bool onlyActive = true,
    int limit = 20,
  }) async {
    final res = await _c.rpc(
      'get_discounts_org5',
      params: {'p_only_active': onlyActive, 'p_limit': limit},
    );
    if (res is List) {
      return res.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  // Notifications (Org 5)
  static Future<List<Map<String, dynamic>>> getNotificationsOrg5({
    bool onlyUnread = false,
    int limit = 50,
  }) async {
    final res = await _c.rpc(
      'get_notifications_org5',
      params: {
        'p_only_unread': onlyUnread,
        'p_limit': limit,
      },
    );
    if (res is List) {
      return res.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  static Future<void> markAllNotificationsReadOrg5() async {
    await _c.rpc('mark_all_notifications_read_org5');
  }

  static Future<void> markNotificationReadOrg5({
    required String id,
  }) async {
    await _c.rpc('mark_notification_read_org5', params: {'p_id': id});
  }

  // Connect — Members (Org 5)
  static Future<Map<String, dynamic>> getMembersOrg5({
    required String tab, // 'nearest' | 'network'
    required String status, // 'Semua' | 'Online' | 'Friends' | 'Partners'
    String search = '',
    int page = 1,
    int pageSize = 10,
  }) async {
    int? baseLocationId;
    if (tab == 'nearest') {
      try {
        final p = await getCurrentPresence();
        baseLocationId = p?['location_id'] as int?;
      } catch (_) {}
      if (baseLocationId == null) {
        final uid = _c.auth.currentUser?.id;
        if (uid != null) {
          final me = await getCustomerByMemberIdOrg5(memberId: uid);
          baseLocationId = me?['location_id'] as int?;
        }
      }
    }
    final res = await _c.rpc(
      'get_members_org5',
      params: {
        'p_tab': tab,
        'p_status': status,
        'p_search': search,
        'p_page': page,
        'p_page_size': pageSize,
        'p_base_location_id': baseLocationId,
      },
    );
    if (res is Map<String, dynamic>) return res;
    // Some drivers return List with single row; normalize
    if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
      return res.first as Map<String, dynamic>;
    }
    return {
      'items': <Map<String, dynamic>>[],
      'page': page,
      'pageSize': pageSize,
      'total': 0,
      'hasMore': false,
    };
  }

  // Member detail (by legacy id or member_id string)
  static Future<Map<String, dynamic>?> getMemberDetailOrg5({
    required String id,
  }) async {
    final res = await _c.rpc('get_member_detail_org5', params: {'p_id': id});
    if (res is Map<String, dynamic>) return res;
    if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
      return res.first as Map<String, dynamic>;
    }
    return null;
  }

  // Connect — Actions
  static Future<Map<String, dynamic>?> sendConnectionRequestOrg5({
    required String addresseeId,
    String connectionType = 'friend',
  }) async {
    final res = await _c.rpc(
      'send_connection_request_org5',
      params: {
        'p_addressee_id': addresseeId,
        'p_connection_type': connectionType,
      },
    );
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  static Future<Map<String, dynamic>?> acceptConnectionRequestOrg5({
    required String requesterId,
  }) async {
    final res = await _c.rpc(
      'accept_connection_request_org5',
      params: {'p_requester_id': requesterId},
    );
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  static Future<Map<String, dynamic>?> declineConnectionRequestOrg5({
    required String requesterId,
  }) async {
    final res = await _c.rpc(
      'decline_connection_request_org5',
      params: {'p_requester_id': requesterId},
    );
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  static Future<Map<String, dynamic>?> unfriendOrg5({
    required String peerId,
  }) async {
    final res = await _c.rpc('unfriend_org5', params: {'p_peer_id': peerId});
    if (res is Map<String, dynamic>) return res;
    return null;
  }
}
