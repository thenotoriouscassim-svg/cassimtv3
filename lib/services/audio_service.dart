import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  bool _isMuted = false;

  bool get isMuted => _isMuted;

  Future<void> playBoot() async {
    if (_isMuted) return;
    await _player.play(AssetSource('audio/jarvis_boot.mp3'));
  }

  Future<void> playAppClosed() async {
    if (_isMuted) return;
    await _player.play(AssetSource('audio/jarvis_app_closed.mp3'));
  }

  Future<void> playRequestRoot() async {
    if (_isMuted) return;
    await _player.play(AssetSource('audio/jarvis_request_root.mp3'));
  }

  Future<void> playActivation() async {
    if (_isMuted) return;
    // Play boot sound as activation chime
    await _player.play(AssetSource('audio/jarvis_boot.mp3'));
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
