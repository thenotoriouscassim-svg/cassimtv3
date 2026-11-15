import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/constants.dart';
import '../models/message.dart';
import '../models/system_stats.dart';

enum JarvisState { standby, wakeWordDetected, listening, processing, speaking }

class JarvisService extends ChangeNotifier {
  JarvisState _state = JarvisState.standby;
  List<Message> _conversation = [];
  SystemStats _systemStats = SystemStats.empty();
  String _statusText = JarvisStrings.standby;
  bool _isConnected = false;
  WebSocketChannel? _wsChannel;
  Timer? _statsTimer;
  String _currentTranscript = '';
  double _audioLevel = 0.0;
  String _backendUrl = JarvisStrings.backendUrl;

  // Getters
  JarvisState get state => _state;
  List<Message> get conversation => List.unmodifiable(_conversation);
  SystemStats get systemStats => _systemStats;
  String get statusText => _statusText;
  bool get isConnected => _isConnected;
  String get currentTranscript => _currentTranscript;
  double get audioLevel => _audioLevel;

  JarvisService() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('backend_url');
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        _backendUrl = _normalizeUrl(savedUrl);
      } else {
        _backendUrl = JarvisStrings.backendUrl;
      }
    } catch (_) {
      _backendUrl = JarvisStrings.backendUrl;
    }
    await _connectToBackend();
    _startStatsPolling();
  }

  String _normalizeUrl(String value) => value.trim().replaceAll(RegExp(r'/+

  // ─── Backend Connection ───────────────────────────────────────────────

  Future<void> _connectToBackend() async {
    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/health'))
           .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final health = jsonDecode(response.body) as Map<String, dynamic>;
        _isConnected = health['online'] == true && health['ai_configured'] == true;
        if (_isConnected) _connectWebSocket();
        notifyListeners();
      }
    } catch (_) {
      _isConnected = false;
      notifyListeners();
    }
  }

  void _connectWebSocket() {
    try {
      final wsUrl = _backendUrl
          .replaceFirst('http', 'ws')
          .replaceFirst('https', 'wss');
      _wsChannel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws'));
      _wsChannel!.stream.listen(
        _handleWebSocketMessage,
        onDone: () { _isConnected = false; notifyListeners(); },
        onError: (_) { _isConnected = false; notifyListeners(); },
      );
    } catch (_) {}
  }

  void _handleWebSocketMessage(dynamic data) {
    final Map<String, dynamic> msg = jsonDecode(data);
    switch (msg['type']) {
      case 'state_change':
        _setState(JarvisState.values.byName(msg['state']));
        break;
      case 'transcript':
        _currentTranscript = msg['text'] ?? '';
        notifyListeners();
        break;
      case 'response':
        _addMessage(Message(
          role: MessageRole.assistant,
          content: msg['text'] ?? '',
          timestamp: DateTime.now(),
        ));
        break;
      case 'audio_level':
        _audioLevel = (msg['level'] as num).toDouble();
        notifyListeners();
        break;
      case 'stats':
        _systemStats = SystemStats.fromJson(msg['data']);
        notifyListeners();
        break;
    }
  }

  // ─── State Management ────────────────────────────────────────────────

  void _setState(JarvisState newState) {
    _state = newState;
    _statusText = switch (newState) {
      JarvisState.standby          => JarvisStrings.standby,
      JarvisState.wakeWordDetected => 'ACTIVATED',
      JarvisState.listening        => JarvisStrings.listening,
      JarvisState.processing       => JarvisStrings.processing,
      JarvisState.speaking         => JarvisStrings.speaking,
    };
    notifyListeners();
  }

  // ─── Sending Messages ────────────────────────────────────────────────

  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    final history = _conversation
        .map((m) => {'role': m.role.name, 'content': m.content})
        .toList();

    _addMessage(Message(
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    ));

    _setState(JarvisState.processing);

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': text,
          'conversation_history': history,
        }),
      ).timeout(const Duration(seconds: 75));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _addMessage(Message(
          role: MessageRole.assistant,
          content: data['response'],
          timestamp: DateTime.now(),
        ));
        _setState(JarvisState.speaking);
        await Future.delayed(const Duration(seconds: 2));
        _setState(JarvisState.standby);
      } else {
        final detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail'];
        _addMessage(Message(
          role: MessageRole.assistant,
          content: detail?.toString() ?? 'The cloud service returned HTTP ${response.statusCode}, sir.',
          timestamp: DateTime.now(),
          isError: true,
        ));
        _setState(JarvisState.standby);
      }
    } catch (e) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'I appear to be having trouble reaching my systems, sir. Please check the backend connection.',
        timestamp: DateTime.now(),
        isError: true,
      ));
      _setState(JarvisState.standby);
    }
  }

  Future<void> activateListening() async {
    if (!_isConnected) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'Backend not connected, sir. Please ensure the JARVIS server is running.',
        timestamp: DateTime.now(),
        isError: true,
      ));
      return;
    }
    _wsChannel?.sink.add(jsonEncode({'type': 'activate_listening'}));
    _setState(JarvisState.listening);
  }

  Future<void> stopListening() async {
    _wsChannel?.sink.add(jsonEncode({'type': 'stop_listening'}));
    _setState(JarvisState.standby);
  }

  void _addMessage(Message message) {
    _conversation.add(message);
    if (_conversation.length > 100) {
      _conversation.removeAt(0);
    }
    notifyListeners();
  }

  void clearConversation() {
    _conversation.clear();
    notifyListeners();
  }

  // ─── System Stats ────────────────────────────────────────────────────

  void _startStatsPolling() {
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_isConnected) return;
      try {
        final response = await http.get(
          Uri.parse('$_backendUrl/stats'),
        ).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          _systemStats = SystemStats.fromJson(jsonDecode(response.body));
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  Future<void> executeCommand(String command) async {
    if (!_isConnected) return;
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'command': command}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _addMessage(Message(
          role: MessageRole.assistant,
          content: data['response'],
          timestamp: DateTime.now(),
        ));
      }
    } catch (_) {}
  }

  Future<void> retryConnection() async {
    await _connectToBackend();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }
}
), '');

  // ─── Backend Connection ───────────────────────────────────────────────

  Future<void> _connectToBackend() async {
    try {
      final response = await http
          .get(Uri.parse('${JarvisStrings.backendUrl}/health'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        _isConnected = true;
        _connectWebSocket();
        notifyListeners();
      }
    } catch (_) {
      _isConnected = false;
      notifyListeners();
    }
  }

  void _connectWebSocket() {
    try {
      final wsUrl = JarvisStrings.backendUrl
          .replaceFirst('http', 'ws')
          .replaceFirst('https', 'wss');
      _wsChannel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws'));
      _wsChannel!.stream.listen(
        _handleWebSocketMessage,
        onDone: () { _isConnected = false; notifyListeners(); },
        onError: (_) { _isConnected = false; notifyListeners(); },
      );
    } catch (_) {}
  }

  void _handleWebSocketMessage(dynamic data) {
    final Map<String, dynamic> msg = jsonDecode(data);
    switch (msg['type']) {
      case 'state_change':
        _setState(JarvisState.values.byName(msg['state']));
        break;
      case 'transcript':
        _currentTranscript = msg['text'] ?? '';
        notifyListeners();
        break;
      case 'response':
        _addMessage(Message(
          role: MessageRole.assistant,
          content: msg['text'] ?? '',
          timestamp: DateTime.now(),
        ));
        break;
      case 'audio_level':
        _audioLevel = (msg['level'] as num).toDouble();
        notifyListeners();
        break;
      case 'stats':
        _systemStats = SystemStats.fromJson(msg['data']);
        notifyListeners();
        break;
    }
  }

  // ─── State Management ────────────────────────────────────────────────

  void _setState(JarvisState newState) {
    _state = newState;
    _statusText = switch (newState) {
      JarvisState.standby          => JarvisStrings.standby,
      JarvisState.wakeWordDetected => 'ACTIVATED',
      JarvisState.listening        => JarvisStrings.listening,
      JarvisState.processing       => JarvisStrings.processing,
      JarvisState.speaking         => JarvisStrings.speaking,
    };
    notifyListeners();
  }

  // ─── Sending Messages ────────────────────────────────────────────────

  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    _addMessage(Message(
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    ));

    _setState(JarvisState.processing);

    try {
      final response = await http.post(
        Uri.parse('${JarvisStrings.backendUrl}/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': text,
          'conversation_history': _conversation
              .map((m) => {'role': m.role.name, 'content': m.content})
              .toList(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _addMessage(Message(
          role: MessageRole.assistant,
          content: data['response'],
          timestamp: DateTime.now(),
        ));
        _setState(JarvisState.speaking);
        await Future.delayed(const Duration(seconds: 2));
        _setState(JarvisState.standby);
      }
    } catch (e) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'I appear to be having trouble reaching my systems, sir. Please check the backend connection.',
        timestamp: DateTime.now(),
        isError: true,
      ));
      _setState(JarvisState.standby);
    }
  }

  Future<void> activateListening() async {
    if (!_isConnected) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'Backend not connected, sir. Please ensure the JARVIS server is running.',
        timestamp: DateTime.now(),
        isError: true,
      ));
      return;
    }
    _wsChannel?.sink.add(jsonEncode({'type': 'activate_listening'}));
    _setState(JarvisState.listening);
  }

  Future<void> stopListening() async {
    _wsChannel?.sink.add(jsonEncode({'type': 'stop_listening'}));
    _setState(JarvisState.standby);
  }

  void _addMessage(Message message) {
    _conversation.add(message);
    if (_conversation.length > 100) {
      _conversation.removeAt(0);
    }
    notifyListeners();
  }

  void clearConversation() {
    _conversation.clear();
    notifyListeners();
  }

  // ─── System Stats ────────────────────────────────────────────────────

  void _startStatsPolling() {
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_isConnected) return;
      try {
        final response = await http.get(
          Uri.parse('${JarvisStrings.backendUrl}/stats'),
        ).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          _systemStats = SystemStats.fromJson(jsonDecode(response.body));
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  Future<void> executeCommand(String command) async {
    if (!_isConnected) return;
    try {
      final response = await http.post(
        Uri.parse('${JarvisStrings.backendUrl}/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'command': command}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _addMessage(Message(
          role: MessageRole.assistant,
          content: data['response'],
          timestamp: DateTime.now(),
        ));
      }
    } catch (_) {}
  }

  Future<void> retryConnection() async {
    await _connectToBackend();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }
}
