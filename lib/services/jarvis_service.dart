import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shizuku_api/shizuku_api.dart';
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
  bool _typingResponse = false;
  static const MethodChannel _deviceChannel = MethodChannel('jarvis/device');
  final ShizukuApi _shizuku = ShizukuApi();
  Timer? _statsTimer;
  final AudioPlayer _ttsPlayer = AudioPlayer();
  String _backendUrl = JarvisStrings.backendUrl;
  int _retryTicks = 0;
  final List<Map<String, dynamic>> _chatSessions = [];
  String _activeChatId = '';
  List<Map<String, dynamic>> get savedChats => _chatSessions.map((c) => Map<String, dynamic>.from(c)).toList();
  String get activeChatId => _activeChatId;

  JarvisState get state => _state;
  List<Message> get conversation => List.unmodifiable(_conversation);
  SystemStats get systemStats => _systemStats;
  String get statusText => _statusText;
  bool get isConnected => _isConnected;
  bool get isTypingResponse => _typingResponse;

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
    await _loadChats();
    await _connectToBackend();
    _startStatsPolling();
  }

  Future<void> _loadChats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('jarvis_chat_sessions');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _chatSessions.addAll(decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      } catch (_) {
        _chatSessions.clear();
      }
    }
    // Always open into a clean chat. Old sessions stay saved for chat history.
    _activeChatId = DateTime.now().microsecondsSinceEpoch.toString();
    _conversation.clear();
    _chatSessions.insert(0, {'id': _activeChatId, 'title': 'New chat', 'messages': <dynamic>[]});
    await _persistChats();
    notifyListeners();
  }
  Future<void> _persistChats() async {
    final index = _chatSessions.indexWhere((c) => c['id'] == _activeChatId);
    if (index >= 0) {
      _chatSessions[index]['messages'] = _conversation.map((m) => m.toJson()).toList();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jarvis_chat_sessions', jsonEncode(_chatSessions));
  }

  Future<void> createNewChat() async {
    await _persistChats();
    _conversation.clear();
    _activeChatId = DateTime.now().microsecondsSinceEpoch.toString();
    _chatSessions.insert(0, {'id': _activeChatId, 'title': 'New chat', 'messages': <dynamic>[]});
    await _persistChats();
    notifyListeners();
  }

  Future<void> openChat(String id) async {
    await _persistChats();
    final chat = _chatSessions.firstWhere((c) => c['id'] == id, orElse: () => _chatSessions.first);
    _activeChatId = chat['id'].toString();
    _conversation
      ..clear()
      ..addAll((chat['messages'] as List<dynamic>? ?? []).whereType<Map>().map((m) => Message.fromJson(Map<String, dynamic>.from(m))));
    notifyListeners();
  }

  Future<void> deleteChat(String id) async {
    _chatSessions.removeWhere((c) => c['id'] == id);
    if (_chatSessions.isEmpty) {
      _conversation.clear();
      _activeChatId = DateTime.now().microsecondsSinceEpoch.toString();
      _chatSessions.add({'id': _activeChatId, 'title': 'New chat', 'messages': <dynamic>[]});
    } else if (_activeChatId == id) {
      _activeChatId = _chatSessions.first['id'].toString();
      _conversation
        ..clear()
        ..addAll((_chatSessions.first['messages'] as List<dynamic>? ?? []).whereType<Map>().map((m) => Message.fromJson(Map<String, dynamic>.from(m))));
    }
    await _persistChats();
    notifyListeners();
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
    _setStatus(JarvisState.processing, 'Searching the web…');
    try {
      final response = await http
          .post(
            Uri.parse('$_backendUrl/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': cleanQuery}),
          )
          .timeout(const Duration(seconds: 270));
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
      _startTypingResponse();
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

  void _setStatus(JarvisState newState, String text) {
    _state = newState;
    _statusText = text;
    notifyListeners();
  }

  void _startTypingResponse() {
    // Animate the arriving answer without showing a fake thinking/loading state.
    _typingResponse = true;
    notifyListeners();
  }

  void finishResponseTyping() {
    if (!_typingResponse) return;
    _typingResponse = false;
    _setState(JarvisState.standby);
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
      await _ttsPlayer.setVolume(0.65);
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

  Future<void> _killBackgroundProcesses() async {
    _setStatus(JarvisState.processing, 'Checking Android system-control access…');
    try {
      final running = await _shizuku.pingBinder() ?? false;
      if (!running) {
        _addMessage(Message(
          role: MessageRole.assistant,
          content: 'Sir, Shizuku is not running. Install Shizuku from https://shizuku.rikka.app/ if it is not installed, then start its service on this TV box. On supported Android 11+ devices, Shizuku can be started with Wireless debugging. No background processes were stopped.',
          timestamp: DateTime.now(),
          isError: true,
        ));
        _setState(JarvisState.standby);
        return;
      }

      var permitted = await _shizuku.checkPermission() ?? false;
      if (!permitted) {
        _setStatus(JarvisState.processing, 'Requesting permission for Android system control…');
        permitted = await _shizuku.requestPermission() ?? false;
      }
      if (!permitted) {
        _addMessage(Message(
          role: MessageRole.assistant,
          content: 'I do not have Shizuku permission, sir. No background processes were stopped. Grant JARVIS permission in Shizuku and try again.',
          timestamp: DateTime.now(),
          isError: true,
        ));
        _setState(JarvisState.standby);
        return;
      }

      _setStatus(JarvisState.processing, 'Terminating eligible background processes…');
      final output = await _shizuku.runCommand(
        'am kill-all && echo JARVIS_BACKGROUND_CLEANUP_COMPLETE && grep MemAvailable /proc/meminfo',
      );
      final result = output?.trim() ?? '';
      if (!result.contains('JARVIS_BACKGROUND_CLEANUP_COMPLETE')) {
        throw Exception(result.isEmpty ? 'Android did not confirm the cleanup command.' : result);
      }
      final memoryLines = result.split('\n').where((line) => line.startsWith('MemAvailable:')).toList();
      final memoryLine = memoryLines.isEmpty ? null : memoryLines.first;
      var memoryText = '';
      if (memoryLine != null) {
        final match = RegExp(r'MemAvailable:\s+(\d+)\s+kB').firstMatch(memoryLine);
        if (match != null) {
          final mb = (int.parse(match.group(1)!) / 1024).round();
          memoryText = '\nAvailable memory after cleanup: $mb MB.';
        }
      }
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'On it, sir. Android confirmed that eligible background processes were terminated.$memoryText\nApps and system services may automatically restart when needed.',
        timestamp: DateTime.now(),
      ));
      _setState(JarvisState.standby);
    } catch (error) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'I could not complete background cleanup. Android reported: $error',
        timestamp: DateTime.now(),
        isError: true,
      ));
      _setState(JarvisState.standby);
    }
  }

  Future<bool> _handleDeviceRequest(String text) async {
    final value = text.toLowerCase();
    final wantsKillBackground = RegExp(r'\b(kill|close|clear|stop)\s+(?:all\s+)?background\s+(?:activity|apps?|processes?)\b|\b(free\s+up|free)\s+(?:some\s+)?(?:ram|memory)\b|\bclear\s+recent\s+apps\b').hasMatch(value);
    if (wantsKillBackground) {
      _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
      await _killBackgroundProcesses();
      return true;
    }
    final wantsInfo = RegExp(r'\b(device info|system info|phone info|about this phone|check my device|check my phone|device details|system details|what phone am i using|what device am i using|battery(?: level| percentage| status)?|how much battery|storage(?: space| status)?|free storage|available storage|ram usage|memory usage|android version|phone model|device model)\b').hasMatch(value);
    final settingsMatch = RegExp(r'\b(open|show)\s+(?:the\s+)?(wi-?fi|network|bluetooth|display|screen|sound|audio|battery|apps|applications|system)?\s*settings\b').firstMatch(value);
    if (!wantsInfo && settingsMatch == null) return false;

    _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
    if (wantsInfo) {
      _setStatus(JarvisState.processing, 'Reading device and system information…');
      try {
        final info = await _deviceChannel.invokeMapMethod<String, dynamic>('getDeviceInfo');
        if (info == null) throw Exception('Android did not return device information.');
        final battery = info['batteryPercent'] as int? ?? -1;
        final answer = [
          'Device: ${info['manufacturer']} ${info['model']}',
          'Android: ${info['androidVersion']} (API ${info['sdk']})',
          'RAM: ${info['availableRamMb']} MB available of ${info['totalRamMb']} MB',
          'Internal storage: ${info['storageFreeGb']} GB free of ${info['storageTotalGb']} GB',
          'Battery: ${battery < 0 ? 'Unavailable' : '$battery%'}${info['charging'] == true ? ' (charging)' : ''}',
          'Network: ${info['network']}',
          if (info['lowMemory'] == true) 'Android reports low memory at the moment.',
        ].join('\n');
        _addMessage(Message(role: MessageRole.assistant, content: answer, timestamp: DateTime.now()));
        _startTypingResponse();
      } catch (error) {
        _addMessage(Message(role: MessageRole.assistant, content: 'I could not read device information: $error', timestamp: DateTime.now(), isError: true));
        _setState(JarvisState.standby);
      }
      return true;
    }

    final section = settingsMatch?.group(2)?.toLowerCase() ?? 'general';
    _setStatus(JarvisState.processing, 'Opening Android $section settings…');
    try {
      await _deviceChannel.invokeMethod<bool>('openSettings', {'section': section});
      _addMessage(Message(role: MessageRole.assistant, content: 'Opening Android $section settings, sir.', timestamp: DateTime.now()));
    } catch (error) {
      _addMessage(Message(role: MessageRole.assistant, content: 'Android could not open those settings: $error', timestamp: DateTime.now(), isError: true));
    }
    _setState(JarvisState.standby);
    return true;
  }

  Future<void> sendTextMessage(String text, {bool speakResponse = false, String memoryContext = ''}) async {
    if (text.trim().isEmpty) return;
    if (await _handleDeviceRequest(text.trim())) return;

    // Route explicit search commands and natural weather questions to live search.
    final trimmed = text.trim();
    final searchCommand = RegExp(
      r"^(?:please\s+)?(?:search(?:\s+the\s+web)?|look\s+up|google|find\s+online)(?:\s+for)?\s*[:,-]?\s*(.+)$",
      caseSensitive: false,
    ).firstMatch(trimmed);
    final weatherCommand = RegExp(
      r"^(?:what(?:'s| is)\s+)?(?:the\s+)?(.+?)\s+(?:weather|forecast)(?:\s+today|\s+tomorrow)?\??$",
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
    // Ordinary chat stays visually quiet; no thinking/provider indicator.

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
        _startTypingResponse();
        if (speakResponse) {
          finishResponseTyping();
          await _speakResponse(answer);
        }
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
    final index = _chatSessions.indexWhere((c) => c['id'] == _activeChatId);
    if (index >= 0 && _chatSessions[index]['title'] == 'New chat' && message.role == MessageRole.user) {
      final title = message.content.trim();
      _chatSessions[index]['title'] = title.length > 32 ? '${title.substring(0, 32)}…' : title;
    }
    _persistChats();
    notifyListeners();
  }

  void clearConversation() { createNewChat(); }

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
