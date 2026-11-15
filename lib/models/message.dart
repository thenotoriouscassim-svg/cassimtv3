enum MessageRole { user, assistant, system }

class Message {
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isError;

  const Message({
    required this.role,
    required this.content,
    required this.timestamp,
    this.isError = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    role: MessageRole.values.firstWhere((r) => r.name == json['role'], orElse: () => MessageRole.assistant),
    content: json['content']?.toString() ?? '',
    timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
    isError: json['isError'] == true,
  );

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'isError': isError,
  };
}
