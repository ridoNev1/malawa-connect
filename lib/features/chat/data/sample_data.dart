// lib/features/chat/data/chat_sample_data.dart
List<Map<String, dynamic>> getChatListSampleData() {
  return [
    {
      'id': '1',
      'name': 'Michael Chen',
      'avatar': 'https://randomuser.me/api/portraits/men/32.jpg',
      'lastMessage': 'Wah, kebetulan! Saya juga di sini.',
      'lastMessageTime': '2023-11-15 10:40:00',
      'unreadCount': 0,
      'isOnline': true,
    },
    {
      'id': '2',
      'name': 'Jessica Lee',
      'avatar': 'https://randomuser.me/api/portraits/women/28.jpg',
      'lastMessage': 'Mau ketemu besok?',
      'lastMessageTime': '2023-11-14 18:30:00',
      'unreadCount': 2,
      'isOnline': true,
    },
    {
      'id': '3',
      'name': 'David Wilson',
      'avatar': 'https://randomuser.me/api/portraits/men/36.jpg',
      'lastMessage': 'Oke, see you there!',
      'lastMessageTime': '2023-11-13 15:45:00',
      'unreadCount': 0,
      'isOnline': false,
    },
    {
      'id': '4',
      'name': 'Emma Thompson',
      'avatar': 'https://randomuser.me/api/portraits/women/65.jpg',
      'lastMessage': 'Thanks for the recommendation!',
      'lastMessageTime': '2023-11-12 09:20:00',
      'unreadCount': 1,
      'isOnline': false,
    },
    {
      'id': '5',
      'name': 'Robert Garcia',
      'avatar': 'https://randomuser.me/api/portraits/men/67.jpg',
      'lastMessage': 'Are you coming to the event?',
      'lastMessageTime': '2023-11-11 20:15:00',
      'unreadCount': 0,
      'isOnline': true,
    },
  ];
}

List<Map<String, dynamic>> getChatRoomSampleMessages() {
  return [
    {
      'id': '1',
      'text': 'Hai, saya lihat kita punya minat yang sama!',
      'isSentByMe': false,
      'time': '10:30 AM',
      'showDate': true,
      'showTime': true,
      'isImage': false,
    },
    {
      'text':
          'Hai juga! Ya, kita sama-sama suka coffee dan music. Sering ke cafe ini?',
      'isSentByMe': true,
      'time': '10:32 AM',
      'showDate': false,
      'showTime': true,
      'isImage': false,
    },
    {
      'text':
          'Iya, hampir setiap weekend. Biasanya saya duduk di pojok dengan buku.',
      'isSentByMe': false,
      'time': '10:35 AM',
      'showDate': false,
      'showTime': true,
      'isImage': false,
    },
    {
      'text':
          'Oh, bagus juga. Saya biasanya duduk di dekat jendela. Mungkin kita bisa bertemu dan ngobrol langsung?',
      'isSentByMe': true,
      'time': '10:36 AM',
      'showDate': false,
      'showTime': true,
      'isImage': false,
    },
    {
      'text': 'Tentu saja! Saya ada di sini sekarang. Kamu dimana?',
      'isSentByMe': false,
      'time': '10:38 AM',
      'showDate': false,
      'showTime': true,
      'isImage': false,
    },
  ];
}
