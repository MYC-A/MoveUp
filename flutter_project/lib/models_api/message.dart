class Message {
  final int id;
  final int senderId;
  final int recipientId;
  final String content;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      senderId: json['sender_id'],
      recipientId: json['recipient_id'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class MessageCreate {
  final int recipientId;
  final String content;

  MessageCreate({
    required this.recipientId,
    required this.content,
  });

  Map<String, dynamic> toJson() {
    return {
      'recipient_id': recipientId,
      'content': content,
    };
  }
}
