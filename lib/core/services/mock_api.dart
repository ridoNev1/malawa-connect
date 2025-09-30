// lib/core/services/mock_api.dart
// Single source of truth for all mock data and actions.
// Centralized to ease BE integration later (e.g., Supabase).

import 'dart:math';
import 'package:flutter/foundation.dart';

class PaginatedResult<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;

  const PaginatedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.hasMore,
  });
}

class MembersQuery {
  final String tab; // 'nearest' | 'network'
  final String status; // 'Semua' | 'Online' | 'Friends' | 'Partners'
  final String search;
  final int page;
  final int pageSize;
  final int? locationId; // optional current location for nearest
  final double? radiusKm; // optional

  const MembersQuery({
    this.tab = 'nearest',
    this.status = 'Semua',
    this.search = '',
    this.page = 1,
    this.pageSize = 10,
    this.locationId,
    this.radiusKm,
  });

  MembersQuery copyWith({
    String? tab,
    String? status,
    String? search,
    int? page,
    int? pageSize,
    int? locationId,
    double? radiusKm,
  }) {
    return MembersQuery(
      tab: tab ?? this.tab,
      status: status ?? this.status,
      search: search ?? this.search,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      locationId: locationId ?? this.locationId,
      radiusKm: radiusKm ?? this.radiusKm,
    );
  }
}

class MockApi {
  MockApi._();
  static final MockApi instance = MockApi._();
  static const int presenceTtlSeconds = 120;

  // Current user mock (can be extended)
  Map<String, dynamic> currentUser = {
    // Legacy numeric id (existing table PK)
    'id': 9,
    // App-scoped member uuid (new)
    'member_id': '11111111-1111-4111-8111-111111111111',
    // Base location when offline/inactive
    'location_id': 7,
    'full_name': 'Rido Testing',
    'phone_number': '081217873551',
    'visit_count': 1,
    'last_visit_at': '2025-09-18T16:27:35.846213+00:00',
    'notes': null,
    'created_at': '2025-09-18T16:27:35.846213+00:00',
    'total_point': 107,
    'organization_id': 5,
    // profile extras used by UI
    'preference': 'Looking for Friends',
    'interests': ['Coffee', 'Music', 'Travel'],
    'gallery_images': <String>[],
    'profile_image_url': 'https://randomuser.me/api/portraits/men/12.jpg',
    'date_of_birth': '1991-09-10',
    'gender': 'Laki-laki',
    'visibility': true,
    'search_radius_km': 3.0,
  };

  // Locations
  final List<Map<String, dynamic>> _locations = [
    {
      'id': 7,
      'name': 'Malawa Atrium',
      'address':
          'Jl. Maospati - Solo No.2, Magero, Sragen Tengah, Kec. Sragen, Kabupaten Sragen, Jawa Tengah 57211',
      'is_main_warehouse': false,
      'lat': -7.4275,
      'lng': 111.0242,
      'geofence_radius_m': 120,
      'restaurant_tables': [
        {
          'id': 9,
          'name': 'Testing 01',
          'status': 'available',
          'capacity': 2,
          'deleted_at': null,
          'location_id': 7,
        },
      ],
    },
    {
      'id': 9,
      'name': 'Malawa Probolinggo',
      'address':
          'Jl. Raya Panglima Sudirman No.36, Tisnonegaran, Kec. Kanigaran, Kota Probolinggo, Jawa Timur 67211',
      'is_main_warehouse': false,
      'lat': -7.7569,
      'lng': 113.2115,
      'geofence_radius_m': 120,
      'restaurant_tables': [],
    },
    {
      'id': 8,
      'name': 'Malawa Sambirejo',
      'address':
          'G3FQ+QWQ, Garut 1, Dawung, Kec. Sambirejo, Kabupaten Sragen, Jawa Tengah 57293',
      'is_main_warehouse': false,
      'lat': -7.4800,
      'lng': 110.9870,
      'geofence_radius_m': 120,
      'restaurant_tables': [],
    },
    {
      'id': 10,
      'name': 'Warehouse Sragen',
      'address': '',
      'is_main_warehouse': true,
      'lat': -7.4300,
      'lng': 111.0200,
      'geofence_radius_m': 150,
      'restaurant_tables': [],
    },
  ];

  // Discounts
  final List<Map<String, dynamic>> _discounts = [
    {
      'id': 8,
      'name': 'Open Diskon',
      'description': '',
      'type': 'percentage',
      'value': 20,
      'is_active': true,
      'created_at': '2025-09-30T13:34:29.773957+00:00',
      'unique_code': 'OPENING20',
      'organization_id': 5,
      'image': null,
      'valid_until': '2025-12-31',
    },
  ];

  // Presence mock
  Map<String, dynamic>? _presence = {
    'location_id': 7,
    'location_name': 'Malawa Atrium',
    'check_in_time': DateTime.now().toIso8601String(),
    'last_heartbeat_at': DateTime.now().toIso8601String(),
  };

  // Members (Connect) and Profiles
  final List<Map<String, dynamic>> _members = [
    {
      'id': '1',
      'member_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'location_id': 7,
      'name': 'Michael Chen',
      'distance': '0.5 km',
      'interests': ['Coffee', 'Music', 'Travel'],
      'isConnected': false,
      'isOnline': true,
      'avatar': 'https://randomuser.me/api/portraits/men/32.jpg',
      'lastSeen': 'Sekarang',
      'age': 35,
      'gender': 'Laki-laki',
      'preference': 'Looking for Friends',
      'gallery_images': [
        'https://picsum.photos/seed/michael1/200/200.jpg',
        'https://picsum.photos/seed/michael2/200/200.jpg',
        'https://picsum.photos/seed/michael3/200/200.jpg',
      ],
      'profile_image_url': 'https://randomuser.me/api/portraits/men/32.jpg',
      'date_of_birth': '1988-08-20',
    },
    {
      'id': '2',
      'member_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'location_id': 7,
      'name': 'Jessica Lee',
      'distance': '0.8 km',
      'interests': ['Art', 'Photography', 'Books'],
      'isConnected': false,
      'isOnline': true,
      'avatar': 'https://randomuser.me/api/portraits/women/28.jpg',
      'lastSeen': '5 menit lalu',
      'age': 28,
      'gender': 'Perempuan',
      'preference': 'Looking for Partners',
      'gallery_images': [
        'https://picsum.photos/seed/jessica1/200/200.jpg',
        'https://picsum.photos/seed/jessica2/200/200.jpg',
        'https://picsum.photos/seed/jessica3/200/200.jpg',
      ],
      'profile_image_url': 'https://randomuser.me/api/portraits/women/28.jpg',
      'date_of_birth': '1995-03-12',
    },
    {
      'id': '3',
      'member_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'location_id': 8,
      'name': 'David Wilson',
      'distance': '1.2 km',
      'interests': ['Coffee', 'Business', 'Tech'],
      'isConnected': true,
      'isOnline': false,
      'avatar': 'https://randomuser.me/api/portraits/men/36.jpg',
      'lastSeen': '2 jam lalu',
      'age': 38,
      'gender': 'Laki-laki',
      'preference': 'Looking for Friends',
      'gallery_images': [
        'https://picsum.photos/seed/david1/200/200.jpg',
        'https://picsum.photos/seed/david2/200/200.jpg',
      ],
      'profile_image_url': 'https://randomuser.me/api/portraits/men/36.jpg',
      'date_of_birth': '1985-11-05',
    },
    {
      'id': '4',
      'member_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'location_id': 9,
      'name': 'Emma Thompson',
      'distance': '1.5 km',
      'interests': ['Travel', 'Food', 'Music'],
      'isConnected': false,
      'isOnline': true,
      'avatar': 'https://randomuser.me/api/portraits/women/65.jpg',
      'lastSeen': 'Sekarang',
      'age': 30,
      'gender': 'Perempuan',
      'preference': 'Looking for Friends',
      'gallery_images': <String>[],
      'profile_image_url': 'https://randomuser.me/api/portraits/women/65.jpg',
      'date_of_birth': '1993-04-14',
    },
    {
      'id': '5',
      'member_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'location_id': 9,
      'name': 'Robert Garcia',
      'distance': '2.0 km',
      'interests': ['Sports', 'Music', 'Movies'],
      'isConnected': false,
      'isOnline': false,
      'avatar': 'https://randomuser.me/api/portraits/men/67.jpg',
      'lastSeen': '1 hari lalu',
      'age': 32,
      'gender': 'Laki-laki',
      'preference': 'Looking for Partners',
      'gallery_images': <String>[],
      'profile_image_url': 'https://randomuser.me/api/portraits/men/67.jpg',
      'date_of_birth': '1991-12-08',
    },
    {
      'id': '6',
      'member_id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      'location_id': 8,
      'name': 'Sophia Martinez',
      'distance': '2.5 km',
      'interests': ['Coffee', 'Art', 'Design'],
      'isConnected': false,
      'isOnline': true,
      'avatar': 'https://randomuser.me/api/portraits/women/33.jpg',
      'lastSeen': 'Sekarang',
      'age': 27,
      'gender': 'Perempuan',
      'preference': 'Looking for Friends',
      'gallery_images': <String>[],
      'profile_image_url': 'https://randomuser.me/api/portraits/women/33.jpg',
      'date_of_birth': '1996-06-03',
    },
  ];

  // Simulated presence for other members (TTL-based; keyed by legacy string id)
  final Map<String, Map<String, dynamic>> _memberPresence = {
    '1': {
      'location_id': 7,
      'check_in_time': null,
      'last_heartbeat_at': "INIT", // placeholder
    },
    '2': {'location_id': 7, 'check_in_time': null, 'last_heartbeat_at': "INIT"},
    '6': {'location_id': 8, 'check_in_time': null, 'last_heartbeat_at': "INIT"},
  };

  // Blocked users by current user (store both legacy id and member_id strings)
  final Set<String> _blockedIds = <String>{};

  bool isBlocked(String userId) {
    if (_blockedIds.contains(userId)) return true;
    try {
      final m = _members.firstWhere(
        (e) =>
            e['id'].toString() == userId ||
            e['member_id']?.toString() == userId,
      );
      return _blockedIds.contains(m['id'].toString()) ||
          (m['member_id'] != null &&
              _blockedIds.contains(m['member_id'].toString()));
    } catch (_) {
      return false;
    }
  }

  // Chat data
  final List<Map<String, dynamic>> _chatList = [
    {
      'id': '1',
      'name': 'Michael Chen',
      'avatar': 'https://randomuser.me/api/portraits/men/32.jpg',
      'lastMessage': 'Wah, kebetulan! Saya juga di sini.',
      'lastMessageTime': '2023-11-15T10:40:00',
      'unreadCount': 0,
      'isOnline': true,
    },
    {
      'id': '2',
      'name': 'Jessica Lee',
      'avatar': 'https://randomuser.me/api/portraits/women/28.jpg',
      'lastMessage': 'Mau ketemu besok?',
      'lastMessageTime': '2023-11-14T18:30:00',
      'unreadCount': 2,
      'isOnline': true,
    },
    {
      'id': '3',
      'name': 'David Wilson',
      'avatar': 'https://randomuser.me/api/portraits/men/36.jpg',
      'lastMessage': null,
      'lastMessageTime': null,
      'unreadCount': 0,
      'isOnline': false,
    },
    {
      'id': '4',
      'name': 'Emma Thompson',
      'avatar': 'https://randomuser.me/api/portraits/women/65.jpg',
      'lastMessage': null,
      'lastMessageTime': null,
      'unreadCount': 0,
      'isOnline': false,
    },
    {
      'id': '5',
      'name': 'Robert Garcia',
      'avatar': 'https://randomuser.me/api/portraits/men/67.jpg',
      'lastMessage': null,
      'lastMessageTime': null,
      'unreadCount': 0,
      'isOnline': true,
    },
  ];

  final Map<String, List<Map<String, dynamic>>> _chatMessages = {
    '1': [
      {
        'id': 'm1',
        'text': 'Hai, saya lihat kita punya minat yang sama!',
        'isSentByMe': false,
        'time': '10:30 AM',
        'showDate': true,
        'showTime': true,
        'isImage': false,
      },
      {
        'id': 'm2',
        'text':
            'Hai juga! Ya, kita sama-sama suka coffee dan music. Sering ke cafe ini?',
        'isSentByMe': true,
        'time': '10:32 AM',
        'showDate': false,
        'showTime': true,
        'isImage': false,
      },
    ],
    '2': [
      {
        'id': 'm3',
        'text': 'Mau ketemu besok?',
        'isSentByMe': false,
        'time': '06:30 PM',
        'showDate': true,
        'showTime': true,
        'isImage': false,
      }
    ],
  };

  // Notifications (mock)
  final List<Map<String, dynamic>> _notifications = [
    {
      'id': '1',
      'type': 'newMessage',
      'title': 'Pesan Baru',
      'message': 'Halo, apakah kita bisa bertemu di cafe nanti?',
      'senderId': '1',
      'senderName': 'Michael Chen',
      'senderAvatar': 'https://randomuser.me/api/portraits/men/32.jpg',
      'timestamp': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
      'isRead': false,
      'requiresAction': false,
    },
    {
      'id': '2',
      'type': 'connectionRequest',
      'title': 'Permintaan Koneksi',
      'message': 'Sarah Johnson ingin terhubung dengan Anda',
      'senderId': '2',
      'senderName': 'Sarah Johnson',
      'senderAvatar': 'https://randomuser.me/api/portraits/women/44.jpg',
      'timestamp': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
      'isRead': false,
      'requiresAction': true,
    },
    {
      'id': '3',
      'type': 'connectionRequest',
      'title': 'Permintaan Koneksi',
      'message': 'David Wilson ingin terhubung dengan Anda',
      'senderId': '3',
      'senderName': 'David Wilson',
      'senderAvatar': 'https://randomuser.me/api/portraits/men/36.jpg',
      'timestamp': DateTime.now()
          .subtract(const Duration(hours: 5))
          .toIso8601String(),
      'isRead': false,
      'requiresAction': true,
    },
    {
      'id': '4',
      'type': 'connectionAccepted',
      'title': 'Koneksi Diterima',
      'message': 'Emma Wilson telah menerima permintaan koneksi Anda',
      'senderId': '4',
      'senderName': 'Emma Wilson',
      'senderAvatar': 'https://randomuser.me/api/portraits/women/65.jpg',
      'timestamp': DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
      'isRead': true,
      'requiresAction': false,
    },
  ];

  // --- GET endpoints ---
  Future<Map<String, dynamic>> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Initialize member presences on first call (set last_heartbeat_at to now)
    for (final entry in _memberPresence.entries) {
      if (entry.value['last_heartbeat_at'] == 'INIT') {
        entry.value['last_heartbeat_at'] = DateTime.now().toIso8601String();
        entry.value['check_in_time'] = DateTime.now().toIso8601String();
      }
    }
    return Map<String, dynamic>.from(currentUser);
  }

  Future<List<Map<String, dynamic>>> getLocations({String? search}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    var list = List<Map<String, dynamic>>.from(_locations);
    if (search != null && search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      list = list
          .where(
            (e) =>
                e['name'].toString().toLowerCase().contains(q) ||
                e['address'].toString().toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  Future<List<Map<String, dynamic>>> getDiscounts({String? search}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    var list = List<Map<String, dynamic>>.from(_discounts);
    if (search != null && search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      list = list
          .where((e) => e['name'].toString().toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  Future<Map<String, dynamic>?> getPresence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _presence == null ? null : Map<String, dynamic>.from(_presence!);
  }

  Future<void> heartbeat() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (_presence != null) {
      _presence!['last_heartbeat_at'] = DateTime.now().toIso8601String();
    }
    debugPrint('[MockApi] heartbeat payload: {}');
  }

  Future<PaginatedResult<Map<String, dynamic>>> getMembers(
    MembersQuery query,
  ) async {
    await Future.delayed(const Duration(milliseconds: 350));

    List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(_members);

    // Filter blocked by current user
    list = list.where((m) {
      final id = m['id'].toString();
      final mid = (m['member_id'] ?? '').toString();
      return !_blockedIds.contains(id) && !_blockedIds.contains(mid);
    }).toList();

    // Compute online via TTL presence; if online, override location_id
    list = list.map((m) {
      final id = m['id'].toString();
      final updated = {...m};
      final pres = _memberPresence[id];
      if (pres != null) {
        final last = DateTime.tryParse(pres['last_heartbeat_at'] ?? '');
        final online =
            last != null &&
            DateTime.now().difference(last).inSeconds <= presenceTtlSeconds;
        updated['isOnline'] = online;
        if (online) {
          updated['location_id'] = pres['location_id'];
        }
      } else {
        updated['isOnline'] = false;
      }
      return updated;
    }).toList();

    // Tab: nearest -> base on presence location or currentUser.location_id
    if (query.tab.toLowerCase() == 'nearest') {
      final presence = await getPresence();
      final baseLocId = presence != null
          ? presence['location_id'] as int?
          : (currentUser['location_id'] as int?);
      if (baseLocId != null) {
        list = list.where((e) => e['location_id'] == baseLocId).toList();
      }
    }

    // Status filter
    switch (query.status) {
      case 'Online':
        list = list.where((m) => (m['isOnline'] as bool?) == true).toList();
        break;
      case 'Friends':
        list = list.where((m) => (m['isConnected'] as bool?) == true).toList();
        break;
      case 'Partners':
        list = list
            .where(
              (m) => (m['preference'] ?? '').toString().contains('Partners'),
            )
            .toList();
        break;
      default:
        break;
    }

    // Search
    if (query.search.trim().isNotEmpty) {
      final q = query.search.toLowerCase();
      list = list.where((m) {
        final name = (m['name'] as String).toLowerCase();
        final interests = (m['interests'] as List<dynamic>)
            .map((i) => i.toString().toLowerCase())
            .join(' ');
        return name.contains(q) || interests.contains(q);
      }).toList();
    }

    // Pagination
    final total = list.length;
    final start = (query.page - 1) * query.pageSize;
    final end = min(start + query.pageSize, total);
    final items = (start < total)
        ? list.sublist(start, end)
        : <Map<String, dynamic>>[];
    final hasMore = end < total;

    return PaginatedResult(
      items: items,
      page: query.page,
      pageSize: query.pageSize,
      total: total,
      hasMore: hasMore,
    );
  }

  Future<Map<String, dynamic>?> getMemberById(String userId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    try {
      final raw = _members.firstWhere(
        (e) =>
            e['id'].toString() == userId ||
            e['member_id']?.toString() == userId,
      );
      final m = Map<String, dynamic>.from(raw);
      final id = m['id'].toString();
      final pres = _memberPresence[id];
      bool online = false;
      if (pres != null) {
        final last = DateTime.tryParse(pres['last_heartbeat_at'] ?? '');
        online =
            last != null &&
            DateTime.now().difference(last).inSeconds <= presenceTtlSeconds;
      }
      m['isOnline'] = online;
      if (online && pres != null) {
        m['location_id'] = pres['location_id'];
      }
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getChatList({String? search}) async {
    await Future.delayed(const Duration(milliseconds: 250));
    // Ensure a chat entry exists for all connected members (even with zero messages)
    for (final m in _members) {
      if ((m['isConnected'] as bool?) == true) {
        final id = m['id'].toString();
        final exists = _chatList.any((c) => c['id'].toString() == id);
        if (!exists) {
          _chatList.add({
            'id': id,
            'name': m['name'] ?? (m['full_name'] ?? ''),
            'avatar': m['avatar'] ?? m['profile_image_url'] ?? '',
            'lastMessage': '',
            'lastMessageTime': DateTime.now().toIso8601String(),
            'unreadCount': 0,
            'isOnline': (m['isOnline'] as bool?) == true,
          });
          _chatMessages.putIfAbsent(id, () => []);
        }
      }
    }

    var list = List<Map<String, dynamic>>.from(_chatList);
    // Recompute online from TTL presence
    list = list.map((c) {
      final id = c['id'].toString();
      final pres = _memberPresence[id];
      bool online = false;
      if (pres != null) {
        final last = DateTime.tryParse(pres['last_heartbeat_at'] ?? '');
        online =
            last != null &&
            DateTime.now().difference(last).inSeconds <= presenceTtlSeconds;
      }
      // Align lastMessage with room state: if no messages in room, blank preview
      final msgs = _chatMessages[id] ?? const [];
      final adjusted = {...c, 'isOnline': online};
      if (msgs.isEmpty) {
        adjusted['lastMessage'] = '';
      }
      return adjusted;
    }).toList();
    // Keep chats even without messages so all connections appear
    // Filter blocked: assume chat.id == member.id in mock
    list = list
        .where((e) => !_blockedIds.contains(e['id'].toString()))
        .toList();
    if (search != null && search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      list = list
          .where(
            (e) =>
                e['name'].toString().toLowerCase().contains(q) ||
                e['lastMessage'].toString().toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  Future<Map<String, dynamic>?> getChatById(String chatId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      return _chatList.firstWhere((e) => e['id'].toString() == chatId);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getChatMessages(String chatId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final list = _chatMessages[chatId] ?? [];
    return List<Map<String, dynamic>>.from(list);
  }

  Future<Map<String, dynamic>> getOrCreateDirectChatByUserId(
    String userId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 150));
    // Try find member by either id or member_id
    final member = await getMemberById(userId);
    if (member == null) {
      // Fallback to existing chat if any
      final existing = await getChatById(userId);
      if (existing != null) return existing;
      // Create a placeholder chat
      final placeholder = {
        'id': userId,
        'name': 'Unknown',
        'avatar': '',
        'lastMessage': '',
        'lastMessageTime': DateTime.now().toIso8601String(),
        'unreadCount': 0,
        'isOnline': false,
      };
      _chatList.add(placeholder);
      return placeholder;
    }
    // Use legacy numeric id as chat id to match existing mock
    final chatId = member['id'].toString();
    final found = await getChatById(chatId);
    if (found != null) return found;
    final newChat = {
      'id': chatId,
      'name': member['name'] ?? (member['full_name'] ?? ''),
      'avatar': member['avatar'] ?? member['profile_image_url'] ?? '',
      'lastMessage': '',
      'lastMessageTime': DateTime.now().toIso8601String(),
      'unreadCount': 0,
      'isOnline': (member['isOnline'] as bool?) == true,
    };
    _chatList.add(newChat);
    // Ensure messages store exists
    _chatMessages.putIfAbsent(chatId, () => []);
    return newChat;
  }

  // --- Action endpoints (prints payloads) ---
  Future<void> sendFriendRequest({
    required String toUserId,
    String? message,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));
    debugPrint(
      '[MockApi] sendFriendRequest payload: {toUserId: $toUserId, message: $message}',
    );
  }

  Future<void> acceptFriendRequest({required String requestId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    debugPrint(
      '[MockApi] acceptFriendRequest payload: {requestId: $requestId}',
    );
  }

  Future<void> declineFriendRequest({required String requestId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    debugPrint(
      '[MockApi] declineFriendRequest payload: {requestId: $requestId}',
    );
  }

  Future<void> unfriend({required String userId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    debugPrint('[MockApi] unfriend payload: {userId: $userId}');
  }

  Future<void> blockUser({required String userId, String? reason}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Store both forms if resolvable
    _blockedIds.add(userId);
    final m = await getMemberById(userId);
    if (m != null) {
      _blockedIds.add(m['id'].toString());
      if (m['member_id'] != null) _blockedIds.add(m['member_id'].toString());
    }
    debugPrint(
      '[MockApi] blockUser payload: {userId: $userId, reason: $reason}',
    );
  }

  Future<void> reportUser({required String userId, String? reason}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    debugPrint(
      '[MockApi] reportUser payload: {userId: $userId, reason: $reason}',
    );
  }

  Future<void> updateProfile({
    required String userId,
    required Map<String, dynamic> payload,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    debugPrint(
      '[MockApi] updateProfile payload: {userId: $userId, data: $payload}',
    );
    // Update local member data if exists
    final idx = _members.indexWhere((e) => e['id'].toString() == userId);
    if (idx != -1) {
      _members[idx] = {..._members[idx], ...payload};
    }
  }

  Future<void> toggleVisibility({required bool visible}) async {
    await Future.delayed(const Duration(milliseconds: 180));
    currentUser['visibility'] = visible;
    debugPrint('[MockApi] toggleVisibility payload: {visible: $visible}');
  }

  Future<void> updateSearchRadius({required double radiusKm}) async {
    await Future.delayed(const Duration(milliseconds: 180));
    currentUser['search_radius_km'] = radiusKm;
    debugPrint('[MockApi] updateSearchRadius payload: {radius_km: $radiusKm}');
  }

  Future<void> checkIn({required int locationId}) async {
    await Future.delayed(const Duration(milliseconds: 220));
    final loc = _locations.firstWhere(
      (e) => e['id'] == locationId,
      orElse: () => {},
    );
    _presence = {
      'location_id': locationId,
      'location_name': loc['name'] ?? 'Unknown',
      'check_in_time': DateTime.now().toIso8601String(),
      'last_heartbeat_at': DateTime.now().toIso8601String(),
    };
    debugPrint('[MockApi] checkIn payload: {locationId: $locationId}');
  }

  Future<void> checkOut() async {
    await Future.delayed(const Duration(milliseconds: 180));
    debugPrint('[MockApi] checkOut payload: {}');
    _presence = null;
  }

  Future<void> sendMessage({
    required String chatId,
    required String text,
    bool isImage = false,
  }) async {
    await Future.delayed(const Duration(milliseconds: 220));
    final now = DateTime.now();
    final time =
        '${now.hour % 12 == 0 ? 12 : now.hour % 12}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
    final newMsg = {
      'id': 'm${now.millisecondsSinceEpoch}',
      'text': text,
      'isSentByMe': true,
      'time': time,
      'showDate': false,
      'showTime': true,
      'isImage': isImage,
    };
    _chatMessages.putIfAbsent(chatId, () => []);
    _chatMessages[chatId]!.add(newMsg);

    // Update chat list
    final idx = _chatList.indexWhere((e) => e['id'].toString() == chatId);
    if (idx != -1) {
      _chatList[idx] = {
        ..._chatList[idx],
        'lastMessage': isImage ? 'Gambar' : text,
        'lastMessageTime': now.toIso8601String(),
        'unreadCount': 0,
      };
    }

    debugPrint(
      '[MockApi] sendMessage payload: {chatId: $chatId, text: $text, isImage: $isImage}',
    );
  }

  Future<void> markChatAsRead(String chatId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final idx = _chatList.indexWhere((e) => e['id'].toString() == chatId);
    if (idx != -1) {
      _chatList[idx] = {..._chatList[idx], 'unreadCount': 0};
    }
    debugPrint('[MockApi] markChatAsRead payload: {chatId: $chatId}');
  }

  // --- Notifications ---
  Future<List<Map<String, dynamic>>> getNotifications() async {
    await Future.delayed(const Duration(milliseconds: 120));
    return List<Map<String, dynamic>>.from(_notifications);
  }

  Future<void> markNotificationRead(String id) async {
    await Future.delayed(const Duration(milliseconds: 60));
    final idx = _notifications.indexWhere((n) => n['id'] == id);
    if (idx != -1)
      _notifications[idx] = {..._notifications[idx], 'isRead': true};
  }

  Future<void> markAllNotificationsRead() async {
    await Future.delayed(const Duration(milliseconds: 80));
    for (var i = 0; i < _notifications.length; i++) {
      _notifications[i] = {..._notifications[i], 'isRead': true};
    }
  }

  Future<void> acceptConnectionRequest(String notificationId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    debugPrint(
      '[MockApi] acceptConnectionRequest payload: {notificationId: $notificationId}',
    );
    final idx = _notifications.indexWhere((n) => n['id'] == notificationId);
    if (idx != -1) {
      final notif = _notifications[idx];
      final senderId = notif['senderId']?.toString();
      _notifications[idx] = {
        ...notif,
        'isRead': true,
        'requiresAction': false,
        'type': 'connectionAccepted',
        'title': 'Koneksi Diterima',
      };
      if (senderId != null) {
        final midx = _members.indexWhere((m) => m['id'].toString() == senderId);
        if (midx != -1) {
          _members[midx] = {..._members[midx], 'isConnected': true};
          final exists = _chatList.any((c) => c['id'].toString() == senderId);
          if (!exists) {
            final m = _members[midx];
            _chatList.add({
              'id': senderId,
              'name': m['name'] ?? (m['full_name'] ?? ''),
              'avatar': m['avatar'] ?? m['profile_image_url'] ?? '',
              'lastMessage': null,
              'lastMessageTime': null,
              'unreadCount': 0,
              'isOnline': (m['isOnline'] as bool?) == true,
            });
            _chatMessages.putIfAbsent(senderId, () => []);
          }
        }
      }
    }
  }

  Future<void> declineConnectionRequest(String notificationId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    debugPrint(
      '[MockApi] declineConnectionRequest payload: {notificationId: $notificationId}',
    );
    final idx = _notifications.indexWhere((n) => n['id'] == notificationId);
    if (idx != -1) {
      final notif = _notifications[idx];
      final senderId = notif['senderId']?.toString();
      _notifications[idx] = {
        ...notif,
        'isRead': true,
        'requiresAction': false,
        'type': 'connectionRejected',
        'title': 'Koneksi Ditolak',
      };
      if (senderId != null) {
        final midx = _members.indexWhere((m) => m['id'].toString() == senderId);
        if (midx != -1) {
          _members[midx] = {..._members[midx], 'isConnected': false};
        }
        final cidx = _chatList.indexWhere((c) => c['id'].toString() == senderId);
        if (cidx != -1) {
          final msgs = _chatMessages[senderId] ?? const [];
          if (msgs.isEmpty) {
            _chatList.removeAt(cidx);
            _chatMessages.remove(senderId);
          }
        }
      }
    }
  }
}
