import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:piper_phonemize/piper_phonemize.dart' as piper;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/constants.dart';
import '../models/message.dart';
import '../models/system_stats.dart';

enum JarvisState { standby, wakeWordDetected, listening, processing, speaking }

class JarvisService extends ChangeNotifier {
  JarvisState _state = JarvisState.standby;
  final List<Message> _conversation = [];
  SystemStats _systemStats = SystemStats.empty();
  String _statusText = JarvisStrings.standby;
  bool _isConnected = false;
  WebSocketChannel? _wsChannel;
  Timer? _statsTimer;
  String _currentTranscript = '';
  double _audioLevel = 0.0;
  String _backendUrl = JarvisStrings.backendUrl;
  final AudioPlayer _voicePlayer = AudioPlayer();
  sherpa.OfflineTts? _neuralTts;
  bool _localTtsReady = false;
  int _retryTicks = 0;
  bool _autoSpeak = true;
  bool _voiceConfigured = false;

  JarvisState get state => _state;
  List<Message> get conversation => List.unmodifiable(_conversation);
  SystemStats get systemStats => _systemStats;
  String get statusText => _statusText;
  bool get isConnected => _isConnected;
  String get currentTranscript => _currentTranscript;
  double get audioLevel => _audioLevel;
  bool get voiceConfigured => _voiceConfigured;

  JarvisService() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('backend_url');
      _autoSpeak = prefs.getBool('auto_speak') ?? true;
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        _backendUrl = _normalizeUrl(savedUrl);
      }
    } catch (_) {
      // Use the cloud URL default if preferences are unavailable.
    }
    await _initializeLocalVoice();
    await _connectToBackend();
    _startStatsPolling();
  }

  String _normalizeUrl(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');


  Future<void> _initializeLocalVoice() async {
    if (_localTtsReady && _neuralTts != null) return;
    try {
      const modelName = 'vits-piper-en_GB-southern_english_male-medium-int8';
      const modelUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$modelName.tar.bz2';

      final supportDir = await getApplicationSupportDirectory();
      final modelDir = Directory('${supportDir.path}/$modelName');
      final modelFile = File('${modelDir.path}/model.onnx');
      final tokensFile = File('${modelDir.path}/tokens.txt');

      final modelValid = await modelFile.exists() && await modelFile.length() > 10000000;
      final tokensValid = await tokensFile.exists() && await tokensFile.length() > 0;
      if (!modelValid || !tokensValid) {
        if (await modelDir.exists()) await modelDir.delete(recursive: true);
        await modelDir.create(recursive: true);
        final response = await http.get(Uri.parse(modelUrl))
            .timeout(const Duration(minutes: 5));
        if (response.statusCode != 200) {
          throw Exception('Piper model download failed (HTTP ${response.statusCode}).');
        }
        final tarBytes = BZip2Decoder().decodeBytes(response.bodyBytes);
        final files = TarDecoder().decodeBytes(tarBytes);
        var foundModel = false;
        var foundTokens = false;
        for (final entry in files.files) {
          if (!entry.isFile) continue;
          final name = entry.name.split('/').last;
          if (name.endsWith('.onnx') && !foundModel) {
            await modelFile.writeAsBytes(entry.content as List<int>, flush: true);
            foundModel = true;
          } else if (name == 'tokens.txt' && !foundTokens) {
            await tokensFile.writeAsBytes(entry.content as List<int>, flush: true);
            foundTokens = true;
          }
        }
        if (!foundModel || !foundTokens ||
            await modelFile.length() <= 10000000 ||
            await tokensFile.length() == 0) {
          throw Exception('Piper archive downloaded, but model.onnx or tokens.txt is missing or incomplete.');
        }
      }

      await piper.initBindingsAsync();
      final espeakData = await piper.extractEspeakNgData();
      final phonemizerStatus = piper.PiperPhonemize.initialize(espeakData);
      if (phonemizerStatus < 0) {
        throw Exception('Piper could not initialize espeak-ng data at: $espeakData');
      }
      final testPhonemes = piper.PiperPhonemize.phonemize(
        'JARVIS voice test', voice: 'en-gb',
      );
      if (testPhonemes.isEmpty || testPhonemes.every((sentence) => sentence.isEmpty)) {
        throw Exception('Piper phonemizer initialized but produced no British-English phonemes.');
      }

      sherpa.initBindings();
      final modelConfig = sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: modelFile.path,
          tokens: tokensFile.path,
        ),
        numThreads: 2,
        debug: false,
      );
      final engine = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(model: modelConfig, maxNumSentences: 1),
      );
      _neuralTts = engine;
      _localTtsReady = true;
      _voiceConfigured = true;
      debugPrint('Piper ready: ${modelFile.path}; phonemizer sample rate: $phonemizerStatus; TTS sample rate: ${engine.sampleRate}');
      notifyListeners();
    } catch (error) {
      _localTtsReady = false;
      _voiceConfigured = false;
      debugPrint('Piper initialization failed: $error');
    }
  }

  Future<void> _speakResponse(String text) async {
    if (!_autoSpeak || text.trim().isEmpty) return;
    try {
      if (!_localTtsReady || _neuralTts == null) {
        await _initializeLocalVoice();
      }
      final engine = _neuralTts;
      if (!_localTtsReady || engine == null) {
        throw Exception('The offline neural voice is not ready. Check your connection once to download the voice model.');
      }

      final phonemes = piper.PiperPhonemize.phonemize(text, voice: 'en-gb')
          .where((sentence) => sentence.isNotEmpty)
          .toList();
      if (phonemes.isEmpty) return;

      final audio = engine.generateWithConfig(
        text: '',
        config: sherpa.OfflineTtsGenerationConfig(
          sid: 0,
          speed: 0.96,
          silenceScale: 0.22,
          phonemeCodepoints: phonemes,
        ),
      );
      if (audio.samples.isEmpty) {
        throw Exception('The neural voice returned no audio.');
      }

      final tempDir = await getTemporaryDirectory();
      final wavFile = File('${tempDir.path}/jarvis_voice_${DateTime.now().microsecondsSinceEpoch}.wav');
      final written = sherpa.writeWave(
        filename: wavFile.path,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      if (!written) throw Exception('Could not create the speech audio file.');

      await _voicePlayer.stop();
      final completed = _voicePlayer.onPlayerComplete.first;
      await _voicePlayer.play(DeviceFileSource(wavFile.path));
      await completed.timeout(
        Duration(seconds: (audio.samples.length / audio.sampleRate).ceil() + 15),
      );
      if (await wavFile.exists()) await wavFile.delete();
    } catch (error) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'Piper voice failed: ${error.toString().replaceFirst('Exception: ', '')}',
        timestamp: DateTime.now(),
        isError: true,
      ));
    }
  }

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
      _setState(JarvisState.speaking);
      await _speakResponse(answer);
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

  Future<String> transcribeAudio(File audioFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_backendUrl/transcribe'),
    );
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      audioFile.path,
      contentType: MediaType('audio', 'wav'),
    ));
    final streamed = await request.send().timeout(const Duration(seconds: 100));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      var detail = 'Speech recognition failed (HTTP ${response.statusCode}).';
      try {
        detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail']?.toString() ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final transcript = data['transcript']?.toString().trim() ?? '';
    if (transcript.isEmpty) throw Exception('No speech was detected.');
    return transcript;
  }

  Future<void> setAutoSpeak(bool enabled) async {
    _autoSpeak = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_speak', enabled);
    if (!enabled) {
      try { await _voicePlayer.stop(); } catch (_) {}
    }
    notifyListeners();
  }

  bool get autoSpeak => _autoSpeak;

  Future<void> _connectToBackend() async {
    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/health'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final health = jsonDecode(response.body) as Map<String, dynamic>;
        _isConnected =
            health['status'] == 'online' && health['ai_configured'] == true;
        _voiceConfigured = _localTtsReady;
        if (_isConnected) _connectWebSocket();
      } else {
        _isConnected = false;
      }
      notifyListeners();
    } catch (_) {
      _isConnected = false;
      notifyListeners();
    }
  }

  void _connectWebSocket() {
    try {
      final wsUrl = _backendUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      _wsChannel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws'));
      _wsChannel!.stream.listen(
        _handleWebSocketMessage,
        onDone: () {
          // WebSocket is optional; REST chat and speech can remain online.
        },
        onError: (_) {
          // A failed optional socket must not mark the HTTP backend offline.
        },
      );
    } catch (_) {
      // Text chat remains available if the optional socket cannot connect.
    }
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

  void _setState(JarvisState newState) {
    _state = newState;
    _statusText = switch (newState) {
      JarvisState.standby => JarvisStrings.standby,
      JarvisState.wakeWordDetected => 'ACTIVATED',
      JarvisState.listening => JarvisStrings.listening,
      JarvisState.processing => JarvisStrings.processing,
      JarvisState.speaking => JarvisStrings.speaking,
    };
    notifyListeners();
  }

  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

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
              'message': text,
              'conversation_history': history,
            }),
          )
          .timeout(const Duration(seconds: 75));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final answer = data['response']?.toString() ?? 'No response received, sir.';
        _addMessage(Message(
          role: MessageRole.assistant,
          content: answer,
          timestamp: DateTime.now(),
        ));
        _setState(JarvisState.speaking);
        await _speakResponse(answer);
        _setState(JarvisState.standby);
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

  Future<void> activateListening() async {
    if (!_isConnected) {
      _addMessage(Message(
        role: MessageRole.assistant,
        content: 'Cloud backend not connected, sir. Please check your connection.',
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
    _wsChannel?.sink.close();
    _voicePlayer.stop();
    _voicePlayer.dispose();
    _neuralTts?.free();
    super.dispose();
  }
}
