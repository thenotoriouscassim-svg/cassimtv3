import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../models/message.dart';
import '../models/system_stats.dart';

enum JarvisState { standby, processing, speaking }

class JarvisService extends ChangeNotifier {
  JarvisState _state = JarvisState.standby;
  final List<Message> _conversation = [];
  SystemStats _systemStats = SystemStats.empty();
  String _statusText = JarvisStrings.standby;
  bool _isConnected = false;
  Timer? _statsTimer;
  final AudioPlayer _ttsPlayer = AudioPlayer();
  String _backendUrl = JarvisStrings.backendUrl;
  int _retryTicks = 0;

  JarvisState get state => _state;
  List<Message> get conversation => List.unmodifiable(_conversation);
  SystemStats get systemStats => _systemStats;
  String get statusText => _statusText;
  bool get isConnected => _isConnected;

  JarvisService() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('backend_url');
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        _backendUrl = _normalizeUrl(savedUrl);
      }
    } catch (_) {
      // Use the cloud URL default if preferences are unavailable.
    }
    await _connectToBackend();
    _startStatsPolling();
  }

  String _normalizeUrl(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');


  Future<void> searchWeb(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) return;
    _addMessage(Message(
      role: MessageRole.user,
      content: 'Search the web: $cleanQuery',
      timestamp: DateTime.now(),
    ));
    _setState(JarvisState.processing);
    try {
      final response = await http
          .post(
            Uri.parse('$_backendUrl/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': cleanQuery}),
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        var detail = 'Live search failed (HTTP ${response.statusCode}).';
        try {
          detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail']?.toString() ?? detail;
        } catch (_) {}
        throw Exception(detail);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final answer = data['answer']?.toString().trim() ?? '';
      if (answer.isEmpty) throw Exception('Live search returned no answer.');
      final sources = (data['sources'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final buffer = StringBuffer(answer);
      if (sources.isNotEmpty) {
        buffer.write('\n\nSources:');
        for (final source in sources.take(8)) {
          final title = (source['title'] ?? 'Source').toString().replaceAll('[', '(').replaceAll(']', ')');
          final url = (source['url'] ?? '').toString();
          if (url.startsWith('https://') || url.startsWith('http://')) {
            buffer.write('\n- $title: $url');
          }
        }
      } else {
        buffer.write('\n\nLive search was used, but the provider returned no source links.');
      }
      _addMessage(Message(
        role: MessageRole.assistant,
        content: buffer.toString(),
        timestamp: DateTime.now(),
      ));
      _setState(JarvisState.standby);
    } catch (error) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: error.toString().replaceFirst('Exception: ', ''),
        timestamp: DateTime.now(),
        isError: true,
      ));
      _setState(JarvisState.standby);
    }
  }

  Future<void> _connectToBackend() async {
    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/health'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final health = jsonDecode(response.body) as Map<String, dynamic>;
        _isConnected =
            health['status'] == 'online' && health['ai_configured'] == true;
      } else {
        _isConnected = false;
      }
      notifyListeners();
    } catch (_) {
      _isConnected = false;
      notifyListeners();
    }
  }

  void _setState(JarvisState newState) {
    _state = newState;
    _statusText = switch (newState) {
      JarvisState.processing => JarvisStrings.processing,
      JarvisState.speaking => JarvisStrings.speaking,
      JarvisState.standby => JarvisStrings.standby,
    };
    notifyListeners();
  }

  String _makeSpeakable(String text) {
    return text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' Code omitted. ')
        .replaceAll(RegExp(r'`[^`]*`'), ' ')
        .replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'[#*_>~]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _speakResponse(String text) async {
    final speakable = _makeSpeakable(text);
    if (speakable.isEmpty) return;
    final spokenText = speakable.length > 6000 ? speakable.substring(0, 6000) : speakable;
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': spokenText}),
      ).timeout(const Duration(seconds: 100));
      if (response.statusCode != 200) {
        debugPrint('JARVIS Fish Audio TTS unavailable: HTTP ${response.statusCode} ${response.body}');
        return;
      }
      await _ttsPlayer.stop();
      _setState(JarvisState.speaking);
      try {
        final completed = _ttsPlayer.onPlayerComplete.first;
        await _ttsPlayer.play(BytesSource(response.bodyBytes));
        await completed.timeout(const Duration(minutes: 2));
      } finally {
        _setState(JarvisState.standby);
      }
    } catch (error) {
      debugPrint('JARVIS Fish Audio playback failed: $error');
    }
  }

  Future<void> sendTextMessage(String text, {bool speakResponse = false, String memoryContext = ''}) async {
    if (text.trim().isEmpty) return;

    // Route explicit search commands and natural weather questions to live search.
    final trimmed = text.trim();
    final searchCommand = RegExp(
      r"^(?:please\\s+)?(?:search(?:\\s+the\\s+web)?|look\\s+up|google|find\\s+online)(?:\\s+for)?\\s*[:,-]?\\s*(.+)$",
      caseSensitive: false,
    ).firstMatch(trimmed);
    final weatherCommand = RegExp(
      r"^(?:what(?:'s| is)\\s+)?(?:the\\s+)?(.+?)\\s+(?:weather|forecast)(?:\\s+today|\\s+tomorrow)?\\??$",
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (searchCommand != null && (searchCommand.group(1)?.trim().length ?? 0) >= 2) {
      await searchWeb(searchCommand.group(1)!.trim());
      return;
    }
    if (weatherCommand != null) {
      await searchWeb("${weatherCommand.group(1)!.trim()} weather");
      return;
    }

    // Send only earlier turns; the backend appends the current message itself.
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
      final response = await http
          .post(
            Uri.parse('$_backendUrl/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': memoryContext.trim().isEmpty ? text : '${memoryContext.trim()}\n\nCurrent user message: $text',
              'conversation_history': history,
            }),
          )
          .timeout(const Duration(seconds: 270));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final answer = data['response']?.toString() ?? 'No response received, sir.';
        _addMessage(Message(
          role: MessageRole.assistant,
          content: answer,
          timestamp: DateTime.now(),
        ));
        _setState(JarvisState.standby);
        if (speakResponse) await _speakResponse(answer);
      } else {
        String detail = 'Cloud service returned HTTP ${response.statusCode}.';
        try {
          detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail']
                  ?.toString() ??
              detail;
        } catch (_) {}
        _addMessage(Message(
          role: MessageRole.assistant,
          content: detail,
          timestamp: DateTime.now(),
          isError: true,
        ));
        _setState(JarvisState.standby);
      }
    } catch (_) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'I appear to be having trouble reaching my cloud systems, sir.',
        timestamp: DateTime.now(),
        isError: true,
      ));
      _setState(JarvisState.standby);
    }
  }

  void _addMessage(Message message) {
    _conversation.add(message);
    if (_conversation.length > 100) _conversation.removeAt(0);
    notifyListeners();
  }

  void clearConversation() {
    _conversation.clear();
    notifyListeners();
  }

  void _startStatsPolling() {
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_isConnected) {
        _retryTicks++;
        if (_retryTicks >= 5) {
          _retryTicks = 0;
          await _connectToBackend();
        }
        return;
      }
      _retryTicks = 0;
      try {
        final response = await http
            .get(Uri.parse('$_backendUrl/stats'))
            .timeout(const Duration(seconds: 5));
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
      } else {
        final detail =
            (jsonDecode(response.body) as Map<String, dynamic>)['detail'];
        _addMessage(Message(
          role: MessageRole.assistant,
          content: detail?.toString() ?? 'Command was not executed, sir.',
          timestamp: DateTime.now(),
          isError: true,
        ));
      }
    } catch (_) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'I could not contact the command service, sir.',
        timestamp: DateTime.now(),
        isError: true,
      ));
    }
  }

  Future<void> retryConnection() async {
    await _connectToBackend();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _ttsPlayer.dispose();
    super.dispose();
  }
}
