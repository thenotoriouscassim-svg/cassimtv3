import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  bool _lastSpeechSucceeded = false;
  bool _typingResponse = false;
  bool _developerMode = false;
  static const MethodChannel _deviceChannel = MethodChannel('jarvis/device');
  final ShizukuApi _shizuku = ShizukuApi();
  Timer? _statsTimer;
  final AudioPlayer _ttsPlayer = AudioPlayer();
  String _backendUrl = JarvisStrings.backendUrl;
  String _selectedModel = 'v3';
  String? _pendingCodingPrompt;
  String _pendingCodingMemoryContext = '';
  List<Map<String, String>> _pendingCodingHistory = [];
  int _retryTicks = 0;
  final List<Map<String, dynamic>> _chatSessions = [];
  String _activeChatId = '';
  String? _accountToken;
  final Set<String> _cloudChatIds = {};
  Map<String, String> get _accountHeaders => _accountToken == null ? const {} : {'Authorization': 'Bearer $_accountToken'};
  Future<void> setAccountToken(String token) async {
    _accountToken = token;
    _cloudChatIds.clear();
    await _loadCloudChats();
    if (_activeChatId.isEmpty && _chatSessions.isNotEmpty) {
      _activeChatId = _chatSessions.first['id'].toString();
      _conversation
        ..clear()
        ..addAll((_chatSessions.first['messages'] as List<dynamic>? ?? []).whereType<Map>().map((m) => Message.fromJson(Map<String, dynamic>.from(m))));
    }
    await _persistChats();
    notifyListeners();
  }
  List<Map<String, dynamic>> get savedChats => _chatSessions.map((c) => Map<String, dynamic>.from(c)).toList();
  String get activeChatId => _activeChatId;

  JarvisState get state => _state;
  List<Message> get conversation => List.unmodifiable(_conversation);
  SystemStats get systemStats => _systemStats;
  String get statusText => _statusText;
  bool get isConnected => _isConnected;
  bool get lastSpeechSucceeded => _lastSpeechSucceeded;
  bool get isTypingResponse => _typingResponse;
  bool get developerMode => _developerMode;

  String get selectedModel => _selectedModel;
  String get selectedModelLabel => switch (_selectedModel) {
    'v1' => 'JARVIS v1',
    'v2' => 'JARVIS v2',
    'v3' => 'JARVIS v3',
    'v4' => 'JARVIS v4',
    'auto' => 'AUTO',
    _ => 'JARVIS v3',
  };

  Future<void> setSelectedModel(String model) async {
    const allowed = {'auto', 'v1', 'v2', 'v3', 'v4'};
    if (!allowed.contains(model) || model == _selectedModel) return;
    _selectedModel = model;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jarvis_selected_model', model);
  }

  JarvisService() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accountToken = prefs.getString('jarvis_account_token');
      final savedUrl = prefs.getString('backend_url');
      final savedModel = prefs.getString('jarvis_selected_model');
      if (savedModel != null && {'auto', 'v1', 'v2', 'v3', 'v4'}.contains(savedModel)) {
        _selectedModel = savedModel;
      }
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
    if (_accountToken != null) await _loadCloudChats();
    if (_chatSessions.isEmpty) {
      _activeChatId = DateTime.now().microsecondsSinceEpoch.toString();
      _conversation.clear();
      _chatSessions.insert(0, {'id': _activeChatId, 'title': 'New chat', 'messages': <dynamic>[]});
    }
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
    await _syncCurrentChat();
  }


  Future<void> _loadCloudChats() async {
    try {
      final response = await http.get(Uri.parse(_backendUrl + '/chats'), headers: _accountHeaders).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return;
      final rows = (jsonDecode(response.body)['chats'] as List<dynamic>? ?? []);
      final loaded = <Map<String,dynamic>>[];
      _cloudChatIds.clear();
      for (final row in rows) {
        if (row is! Map) continue;
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final detail = await http.get(Uri.parse(_backendUrl + '/chats/' + id), headers: _accountHeaders).timeout(const Duration(seconds: 20));
        if (detail.statusCode != 200) continue;
        final data = jsonDecode(detail.body) as Map<String,dynamic>;
        final messages = (data['messages'] as List<dynamic>? ?? []).map((item) {
          final map = Map<String,dynamic>.from(item as Map);
          return Message(
            role: MessageRole.values.firstWhere((r) => r.name == map['role'], orElse: () => MessageRole.assistant),
            content: map['content']?.toString() ?? '',
            timestamp: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
          ).toJson();
        }).toList();
        loaded.add({'id':id,'title':row['title']?.toString() ?? 'Chat','messages':messages});
        _cloudChatIds.add(id);
      }
      if (loaded.isNotEmpty) {
        _chatSessions..clear()..addAll(loaded);
        _activeChatId = loaded.first['id'].toString();
        _conversation
          ..clear()
          ..addAll((loaded.first['messages'] as List<dynamic>).whereType<Map>().map((m) => Message.fromJson(Map<String,dynamic>.from(m))));
      }
    } catch (e) {
      debugPrint('JARVIS cloud chat restore failed: ' + e.toString());
    }
  }

  Future<void> _syncCurrentChat() async {
    if (_accountToken == null || _activeChatId.isEmpty) return;
    final index = _chatSessions.indexWhere((item) => item['id'] == _activeChatId);
    if (index < 0) return;
    final chat = _chatSessions[index];
    try {
      if (!_cloudChatIds.contains(_activeChatId)) {
        final created = await http.post(Uri.parse(_backendUrl + '/chats'),
          headers: {'Content-Type':'application/json', ..._accountHeaders},
          body: jsonEncode({'id':_activeChatId,'title':chat['title'] ?? 'New chat'})).timeout(const Duration(seconds:20));
        if (created.statusCode != 201 && created.statusCode != 200) return;
        _cloudChatIds.add(_activeChatId);
      }
      final messages = _conversation.map((m) => {
        'role':m.role.name,'content':m.content,'timestamp':m.timestamp.toIso8601String()
      }).toList();
      await http.put(Uri.parse(_backendUrl + '/chats/' + _activeChatId),
        headers: {'Content-Type':'application/json', ..._accountHeaders},
        body: jsonEncode({'title':chat['title'] ?? 'New chat','messages':messages})).timeout(const Duration(seconds:30));
    } catch (e) {
      debugPrint('JARVIS cloud chat sync failed: ' + e.toString());
    }
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


  Future<void> searchWeb(String query, {bool speakResponse = false}) async {
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
            headers: {'Content-Type': 'application/json', ..._accountHeaders},
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
      if (speakResponse) {
        await _speakResponse(buffer.toString());
      } else {
        _startTypingResponse();
      }
    } catch (error) {
      // Never send a failed search to the normal chat model as though it were research.
      debugPrint('JARVIS live search failed: $error');
      final message = "Sir, the live search request failed: ${error.toString().replaceFirst('Exception: ', '')}. No live results were retrieved, so I will not present an ordinary AI answer as current research.";
      _addMessage(Message(
        role: MessageRole.assistant,
        content: message,
        timestamp: DateTime.now(),
        isError: true,
      ));
      if (speakResponse) await _speakResponse(message);
      _setState(JarvisState.standby);
    }
  }

  Future<String> transcribeAudio(File audioFile) async {
    final request = http.MultipartRequest('POST', Uri.parse(_backendUrl + '/transcribe'));
    request.files.add(await http.MultipartFile.fromPath('file', audioFile.path, filename: 'jarvis-recording.m4a'));
    final streamed = await request.send().timeout(const Duration(minutes: 4));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      var detail = 'Transcription failed (HTTP ${response.statusCode}).';
      try { detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail']?.toString() ?? detail; } catch (_) {}
      throw Exception(detail);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['text']?.toString() ?? '';
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
    _lastSpeechSucceeded = false;
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
        _lastSpeechSucceeded = true;
      } finally {
        _setState(JarvisState.standby);
      }
    } catch (error) {
      debugPrint('JARVIS Fish Audio playback failed: $error');
    }
  }

  Future<void> speakText(String text) => _speakResponse(text);

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

  Future<void> _replyDevice(String answer, {bool speakResponse = false, bool isError = false}) async {
    _addMessage(Message(
      role: MessageRole.assistant,
      content: answer,
      timestamp: DateTime.now(),
      isError: isError,
    ));
    if (speakResponse) await _speakResponse(answer);
  }

  Future<bool> _handleDeviceRequest(String text, {bool speakResponse = false}) async {
    final value = text.toLowerCase().trim();
    final appMatch = RegExp(r'^(?:please\s+)?(?:open|launch|start)\s+(.+?)\s*$').firstMatch(text.trim());
    final asksAboutDevice = RegExp(r'\b(device|phone|mobile|tablet|tv box|android|ram|memory|storage|battery|cpu|processor)\b').hasMatch(value);
    final asksForDeviceInfo = asksAboutDevice &&
        RegExp(r'\b(read|check|show|tell|what|how|much|status|details|info|information|using|remaining|left|available|free|percentage|percent|level|usage|model|version|have|got)\b').hasMatch(value);
    final wantsKillBackground = RegExp(r'\b(kill|close|clear|stop)\s+(?:all\s+)?background\s+(?:activity|apps?|processes?)\b|\b(free\s+up|free)\s+(?:some\s+)?(?:ram|memory)\b|\bclear recent apps\b').hasMatch(value);
    final wantsLowerVolume = RegExp(r'\b(lower|decrease|turn down|reduce)\s+(?:the\s+)?volume\b').hasMatch(value);
    final wantsCpu = RegExp(r'\b(cpu|processor)\s+(?:usage|load|percentage)\b|\b(check|read|show)\s+(?:the\s+)?cpu\b').hasMatch(value);
    final wantsBatteryApps = RegExp(r'\b(which|what) apps? .*battery|\bbattery drain(?:ing)? apps?\b|\bapps? .*draining.*battery\b').hasMatch(value);
    final wantsInfo = RegExp(r'\b(device info|system info|phone info|about this phone|check my device|check my phone|read my device|read device|device status|device summary|device details|system details|what phone am i using|what device am i using|battery(?: level| percentage| status)?|how much battery|storage(?: space| status)?|free storage|available storage|ram usage|memory usage|android version|phone model|device model)\b').hasMatch(value) || asksForDeviceInfo;
    final settingsMatch = RegExp(r'\b(open|show)\s+(?:the\s+)?(wi-?fi|network|bluetooth|display|screen|sound|audio|battery|apps|applications|system)?\s*settings\b').firstMatch(value);

    if (wantsKillBackground) {
      _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
      await _killBackgroundProcesses();
      return true;
    }

    if (appMatch != null && !RegExp(r'\b(settings|battery usage|battery stats)\b').hasMatch(value)) {
      _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
      _setStatus(JarvisState.processing, 'Opening ${appMatch.group(1)}…');
      try {
        final requestedApp = appMatch.group(1)!.trim().replaceFirst(RegExp(r'\s+please$', caseSensitive: false), '');
        final opened = await _deviceChannel.invokeMethod<String>('openApp', {'app': requestedApp});
        await _replyDevice('Opening $opened, sir.', speakResponse: speakResponse);
      } catch (error) {
        await _replyDevice('I could not open that app: $error', speakResponse: speakResponse, isError: true);
      }
      _setState(JarvisState.standby);
      return true;
    }

    if (wantsLowerVolume) {
      _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
      try {
        final result = await _deviceChannel.invokeMapMethod<String, dynamic>('lowerVolume');
        if (result == null) throw Exception('Android did not return the volume level.');
        await _replyDevice('Volume lowered from ${result['before']} to ${result['after']} of ${result['max']}, sir.', speakResponse: speakResponse);
      } catch (error) {
        await _replyDevice('I could not change the volume: $error', speakResponse: speakResponse, isError: true);
      }
      _setState(JarvisState.standby);
      return true;
    }

    if (wantsCpu) {
      _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
      _setStatus(JarvisState.processing, 'Measuring CPU usage…');
      try {
        final result = await _deviceChannel.invokeMapMethod<String, dynamic>('getCpuUsage');
        final cpu = (result?['cpuPercent'] as num?)?.toDouble() ?? -1;
        final answer = cpu < 0 ? 'CPU usage is unavailable on this Android build.' : 'Current CPU usage is ${cpu.toStringAsFixed(1)}%.';
        await _replyDevice(answer, speakResponse: speakResponse);
      } catch (error) {
        await _replyDevice('I could not read CPU usage: $error', speakResponse: speakResponse, isError: true);
      }
      _setState(JarvisState.standby);
      return true;
    }

    if (wantsBatteryApps) {
      _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
      try {
        await _deviceChannel.invokeMethod<bool>('openSettings', {'section': 'battery'});
        await _replyDevice('Android battery usage is open, sir. Check the app list there for system-reported battery consumption. Android 14 does not let ordinary apps read precise per-app battery percentages directly, so I will not invent figures.', speakResponse: speakResponse);
      } catch (error) {
        await _replyDevice('I could not open Android battery usage: $error', speakResponse: speakResponse, isError: true);
      }
      _setState(JarvisState.standby);
      return true;
    }

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
        await _replyDevice(answer, speakResponse: speakResponse);
      } catch (error) {
        await _replyDevice('I could not read device information: $error', speakResponse: speakResponse, isError: true);
      }
      _setState(JarvisState.standby);
      return true;
    }

    final section = settingsMatch?.group(2)?.toLowerCase() ?? 'general';
    _setStatus(JarvisState.processing, 'Opening Android $section settings…');
    try {
      await _deviceChannel.invokeMethod<bool>('openSettings', {'section': section});
      await _replyDevice('Opening Android $section settings, sir.', speakResponse: speakResponse);
    } catch (error) {
      await _replyDevice('Android could not open those settings: $error', speakResponse: speakResponse, isError: true);
    }
    _setState(JarvisState.standby);
    return true;
  }

  bool _isCodingRequest(String text) {
    final value = text.toLowerCase();
    final hasCodeArtifact = RegExp(r'\b(code|coding|script|function|class|program|app|website|api|bug|error|exception|compile|build|flutter|dart|python|php|javascript|typescript|html|css|sql|yaml|json|regex|github|workflow|gradle|java|kotlin|react|node\.js)\b').hasMatch(value);
    final hasCodingAction = RegExp(r'\b(write|create|build|make|generate|implement|debug|fix|refactor|edit|update|modify|review|complete|finish|code|program|develop|convert|migrate|integrate|add|remove)\b').hasMatch(value);
    final hasCodeBlock = value.contains('```') || RegExp(r'\b(stack trace|traceback|syntaxerror|exception:|gradle task|flutter build|compiler error)\b').hasMatch(value);
    return (hasCodeArtifact && hasCodingAction) || hasCodeBlock ||
        RegExp(r'\b(code this|write code|let us code|let\x27s code|start coding|fix this code|debug this)\b').hasMatch(value);
  }

  Future<void> _sendCodingRequestStream(String text, List<Map<String, String>> history, String memoryContext, {bool speakResponse = false, String mode = 'standard'}) async {
    // Show the code-generation spinner immediately while the model starts streaming.
    _setStatus(JarvisState.processing, 'Generating code…');
    final client = http.Client();
    final placeholder = Message(role: MessageRole.assistant, content: '', timestamp: DateTime.now());
    _addMessage(placeholder);
    final messageIndex = _conversation.length - 1;
    final fullPrompt = memoryContext.trim().isEmpty
        ? text
        : '${memoryContext.trim()}\\n\\nCurrent user message: $text';
    try {
      final request = http.Request('POST', Uri.parse('$_backendUrl/code'))
        ..headers['Content-Type'] = 'application/json'
        ..headers.addAll(_accountHeaders)
        ..body = jsonEncode({
          'message': fullPrompt,
          'conversation_history': history,
          'mode': mode,
        });
      final streamed = await client.send(request).timeout(const Duration(seconds: 150));
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        var detail = 'The coding service returned HTTP ${streamed.statusCode}.';
        try {
          detail = (jsonDecode(body) as Map<String, dynamic>)['detail']?.toString() ?? detail;
        } catch (_) {}
        throw Exception(detail);
      }

      final buffer = StringBuffer();
      await for (final line in utf8.decoder.bind(streamed.stream).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        final event = jsonDecode(payload) as Map<String, dynamic>;
        final choices = event['choices'] as List<dynamic>? ?? [];
        if (choices.isEmpty) continue;
        final delta = (choices.first as Map<String, dynamic>)['delta'] as Map<String, dynamic>? ?? {};
        final chunk = delta['content']?.toString() ?? '';
        if (chunk.isEmpty) continue;
        buffer.write(chunk);
        _replaceMessageContent(messageIndex, buffer.toString());
      }

      final answer = buffer.toString().trim();
      if (answer.isEmpty) throw Exception('The coding service returned an empty answer.');
      _replaceMessageContent(messageIndex, answer);
      await _persistChats();
      if (speakResponse) await _speakResponse(answer);
    } catch (error) {
      _replaceMessageContent(
        messageIndex,
        'I could not complete that coding request: ${error.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
      await _persistChats();
    } finally {
      client.close();
      _setState(JarvisState.standby);
    }
  }

  void _replaceMessageContent(int index, String content, {bool isError = false}) {
    if (index < 0 || index >= _conversation.length) return;
    final old = _conversation[index];
    _conversation[index] = Message(
      role: old.role,
      content: content,
      timestamp: old.timestamp,
      isError: isError,
    );
    notifyListeners();
  }

  Future<void> _chooseCodingMode(String choice, {bool speakResponse = false}) async {
    final selected = choice.trim().toLowerCase();
    final isAdvanced = selected == 'advanced' || selected == 'advanced code' || selected == 'advanced coding' || selected == 'deepseek';
    final isStandard = selected == 'standard' || selected == 'standard code' || selected == 'standard coding' || selected == 'normal' || selected == 'basic';
    if (!isStandard && !isAdvanced) {
      const prompt = 'Please say Standard code or Advanced.';
      _addMessage(Message(role: MessageRole.assistant, content: prompt, timestamp: DateTime.now()));
      if (speakResponse) { await _speakResponse(prompt); } else { _startTypingResponse(); }
      return;
    }
    final mode = isAdvanced ? 'advanced' : 'standard';
    final prompt = _pendingCodingPrompt;
    if (prompt == null) return;
    final history = List<Map<String, String>>.from(_pendingCodingHistory);
    final memory = _pendingCodingMemoryContext;
    _pendingCodingPrompt = null;
    _pendingCodingMemoryContext = '';
    _pendingCodingHistory = [];
    _addMessage(Message(role: MessageRole.user, content: choice, timestamp: DateTime.now()));
    await _sendCodingRequestStream(prompt, history, memory, speakResponse: speakResponse, mode: mode);
  }
  Future<bool> _handleDeveloperConsole(String text, {bool speakResponse = false}) async {
    final value = text.trim().toLowerCase();
    if (value == '78654') {
      _developerMode = true;
      _addMessage(Message(role: MessageRole.user, content: '•••••', timestamp: DateTime.now()));
      const answer = 'Developer mode activated. Good evening, sir. I am now operating in developer diagnostic mode. You can ask me for a full system check, Cloudflare status, or outstanding issues.';
      _addMessage(Message(role: MessageRole.assistant, content: answer, timestamp: DateTime.now()));
      if (speakResponse) { await _speakResponse(answer); } else { _startTypingResponse(); }
      notifyListeners();
      return true;
    }
    if (!_developerMode) {
      if (value == 'developer mode' || value == 'enter developer mode') {
        const answer = 'Developer access requires the five-digit developer code, sir.';
        _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
        _addMessage(Message(role: MessageRole.assistant, content: answer, timestamp: DateTime.now()));
        if (speakResponse) { await _speakResponse(answer); } else { _startTypingResponse(); }
        return true;
      }
      return false;
    }
    if (value == 'exit developer mode' || value == 'disable developer mode' || value == 'lock developer console') {
      _developerMode = false;
      _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
      const answer = 'Developer mode disabled. Returning to standard operating mode.';
      _addMessage(Message(role: MessageRole.assistant, content: answer, timestamp: DateTime.now()));
      if (speakResponse) { await _speakResponse(answer); } else { _startTypingResponse(); }
      notifyListeners();
      return true;
    }
    final asksDiagnostics = value.contains('all modules') || value.contains('modules functioning') || value.contains('system check') || value.contains('full diagnostic') || value.contains('run diagnostics') || value.contains('any issues') || value.contains('outstanding issues') || value.contains('system status') || value.contains('health check');
    final asksCloudflare = (value.contains('cloudflare') || value.contains('cloudfare') || value.contains('cloud flare') || value.contains('worker')) && (value.contains('up') || value.contains('online') || value.contains('status') || value.contains('running') || value.contains('healthy') || value.contains('working'));
    if (!asksDiagnostics && !asksCloudflare) return false;
    _addMessage(Message(role: MessageRole.user, content: text, timestamp: DateTime.now()));
    _setStatus(JarvisState.processing, 'Running developer diagnostics…');
    String answer;
    try {
      final response = await http.get(Uri.parse(_backendUrl + '/diagnostics')).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        answer = 'I could not complete the diagnostic check. The endpoint returned HTTP ' + response.statusCode.toString() + '.';
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final modules = Map<String, dynamic>.from(data['modules'] as Map? ?? {});
        String status(String key) { final item = modules[key]; return item is Map ? (item['status']?.toString() ?? 'unknown') : 'unknown'; }
        String detail(String key) { final item = modules[key]; return item is Map ? (item['detail']?.toString() ?? '') : ''; }
        final worker = status('cloudflare_worker');
        final database = status('database');
        final keys = ['ai_gemini','ai_groq','ai_nvidia','ai_openrouter','coding_standard','coding_advanced','voice_output','speech_transcription','web_search','authentication','chat_memory_sync'];
        final issues = <String>[];
        if (worker != 'online') issues.add('Cloudflare Worker is not confirmed online.');
        if (database != 'online') issues.add('D1 database check: ' + detail('database'));
        for (final key in keys) { final state = status(key); if (state == 'not_configured' || state == 'degraded' || state == 'unknown') issues.add(key.replaceAll('_',' ') + ': ' + state + '.'); }
        final report = StringBuffer();
        if (asksCloudflare && !asksDiagnostics) {
          report.writeln(worker == 'online' ? 'Cloudflare Worker is responding.' : 'Cloudflare Worker is not confirmed online.');
          report.writeln(database == 'online' ? 'D1 database query passed.' : 'D1 database query did not pass.');
        } else {
          report.writeln('Developer diagnostic report.');
          report.writeln('Cloudflare Worker: ' + worker.toUpperCase() + '.');
          report.writeln('D1 database: ' + database.toUpperCase() + '.');
          report.writeln('Authentication: ' + status('authentication') + '. Cloud chat and memory sync: ' + status('chat_memory_sync') + '.');
          report.writeln('AI credentials — Gemini: ' + status('ai_gemini') + ', Groq: ' + status('ai_groq') + ', NVIDIA: ' + status('ai_nvidia') + ', OpenRouter: ' + status('ai_openrouter') + '.');
          report.writeln('Coding — Standard: ' + status('coding_standard') + ', Advanced: ' + status('coding_advanced') + '.');
          report.writeln('Voice output: ' + status('voice_output') + '. Transcription: ' + status('speech_transcription') + '. Web search: ' + status('web_search') + '.');
          if (issues.isEmpty) report.writeln('No configuration or database issues were detected.');
          else { report.writeln('Items requiring attention:'); for (final issue in issues) { report.writeln('- ' + issue); } }
          report.writeln('Note: credential presence is not proof that each external provider is responding. Only the Worker response and D1 query were actively tested.');
        }
        answer = report.toString().trim();
      }
    } catch (error) {
      answer = 'The diagnostic request failed: ' + error.toString() + '. I cannot confirm the current cloud status.';
    }
    _addMessage(Message(role: MessageRole.assistant, content: answer, timestamp: DateTime.now(), isError: answer.startsWith('I could not') || answer.startsWith('The diagnostic request failed')));
    if (speakResponse) { await _speakResponse(answer); } else { _startTypingResponse(); }
    _setState(JarvisState.standby);
    await _persistChats();
    return true;
  }

  Future<void> sendTextMessage(String text, {bool speakResponse = false, String memoryContext = ''}) async {
    if (text.trim().isEmpty) return;
    if (speakResponse) _lastSpeechSucceeded = false;
    if (await _handleDeveloperConsole(text, speakResponse: speakResponse)) return;
    if (_pendingCodingPrompt != null) {
      await _chooseCodingMode(text, speakResponse: speakResponse);
      return;
    }
    if (await _handleDeviceRequest(text.trim(), speakResponse: speakResponse)) return;

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
      await searchWeb(searchCommand.group(1)!.trim(), speakResponse: speakResponse);
      return;
    }
    if (weatherCommand != null) {
      await searchWeb("${weatherCommand.group(1)!.trim()} weather", speakResponse: speakResponse);
      return;
    }

    // Automatically research questions about recent or changing information.
    final needsLiveResearch = RegExp(
      r'\b(latest|today|yesterday|right now|currently|current|recent|newly|this week|this month|this year|202[5-9]|reviews?|reviewed|ratings?|score|released?|release date|launch(?:ed)?|price|pricing|available now|update|breaking|news|as of)\b',
      caseSensitive: false,
    ).hasMatch(trimmed) || RegExp(
      r'\b(what happened to|what is happening with|has .{2,80} released|is .{2,80} out yet|who won|who is the current|what are people saying about)\b',
      caseSensitive: false,
    ).hasMatch(trimmed);
    if (needsLiveResearch) {
      await searchWeb(trimmed, speakResponse: speakResponse);
      return;
    }

    final isCurrentNewsTopic =
        RegExp(r'\\b(iran|usa|united states|israel|palestine|ukraine|russia|lebanon|yemen|syria|gaza|nato|china|taiwan)\\b', caseSensitive: false).hasMatch(trimmed) &&
        RegExp(r'\\b(war|conflict|attack|strike|missile|ceasefire|invasion|bombing|latest|news|today|update|tensions)\\b', caseSensitive: false).hasMatch(trimmed);
    if (isCurrentNewsTopic) {
      await searchWeb(trimmed, speakResponse: speakResponse);
      return;
    }

    final codingRequest = _isCodingRequest(trimmed);
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
    if (codingRequest) {
      _pendingCodingPrompt = text;
      _pendingCodingMemoryContext = memoryContext;
      _pendingCodingHistory = List<Map<String, String>>.from(history);
      const prompt = 'Would you like Standard code or Advanced?';
      _addMessage(Message(role: MessageRole.assistant, content: prompt, timestamp: DateTime.now()));
      if (speakResponse) { await _speakResponse(prompt); } else { _startTypingResponse(); }
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_backendUrl/chat'),
            headers: {'Content-Type': 'application/json', ..._accountHeaders},
            body: jsonEncode({
              'message': (_developerMode ? 'The user has unlocked JARVIS developer mode. Treat them as the application developer. Be technically direct and never claim a test passed unless it actually ran.\\n\\n' : '') + (memoryContext.trim().isEmpty ? text : '${memoryContext.trim()}\n\nCurrent user message: $text'),
              'conversation_history': speakResponse
                  ? history.skip(history.length > 4 ? history.length - 4 : 0)
                      .map((turn) => {
                        'role': turn['role']!,
                        'content': (turn['content'] ?? '').substring(
                          0, (turn['content'] ?? '').length > 1500 ? 1500 : (turn['content'] ?? '').length),
                      }).toList()
                  : history,
              'voice_mode': speakResponse,
              'model_choice': _selectedModel,
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
