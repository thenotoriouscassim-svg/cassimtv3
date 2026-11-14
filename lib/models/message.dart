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

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'isError': isError,
  };
}
