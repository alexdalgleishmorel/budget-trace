/// One row in the Insights history list.
class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as int,
        title: (json['title'] as String?)?.trim().isNotEmpty == true
            ? json['title'] as String
            : 'New chat',
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      );
}
