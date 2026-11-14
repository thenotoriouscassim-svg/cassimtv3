import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _wakeWordEnabled = true;
  bool _autoSpeak = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text = prefs.getString('backend_url') ?? JarvisStrings.backendUrl;
      _wakeWordEnabled    = prefs.getBool('wake_word_enabled') ?? true;
      _autoSpeak          = prefs.getBool('auto_speak') ?? true;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', _urlController.text.trim());
    await prefs.setBool('wake_word_enabled', _wakeWordEnabled);
    await prefs.setBool('auto_speak', _autoSpeak);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved. Restart app to apply backend URL changes.',
            style: TextStyle(fontFamily: 'Orbitron', fontSize: 11)),
          backgroundColor: JarvisColors.surfaceLight,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisColors.background,
      appBar: AppBar(
        backgroundColor: JarvisColors.surface,
        title: const Text('SETTINGS', style: TextStyle(
          color: JarvisColors.cyan, fontSize: 14, letterSpacing: 4, fontFamily: 'Orbitron')),
        iconTheme: const IconThemeData(color: JarvisColors.cyan),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section('BACKEND CONNECTION'),
          const SizedBox(height: 8),
          _label('Backend Server URL'),
          const SizedBox(height: 6),
          _textField(_urlController, 'e.g. http://192.168.1.100:8000'),
          const SizedBox(height: 4),
          Text(
            'Enter the IP address of the machine running the JARVIS backend.\nMust be on the same WiFi network.',
            style: TextStyle(color: JarvisColors.textDim, fontSize: 9,
              height: 1.6, fontFamily: 'Orbitron'),
          ),
          const SizedBox(height: 24),

          _section('VOICE SETTINGS'),
          _toggle('Wake Word Detection ("Jarvis!")', _wakeWordEnabled,
              (v) => setState(() => _wakeWordEnabled = v)),
          _toggle('Auto-Speak Responses', _autoSpeak,
              (v) => setState(() => _autoSpeak = v)),
          const SizedBox(height: 24),

          _section('ABOUT'),
          _infoRow('App', 'JARVIS AI'),
          _infoRow('Developer', 'CassimTV'),
          _infoRow('Version', '1.0.0'),
          _infoRow('AI Engine', 'Ollama (Local, Free)'),
          _infoRow('Voice Engine', 'Coqui XTTS-v2 (Local, Free)'),
          _infoRow('STT Engine', 'Faster-Whisper (Local, Free)'),
          _infoRow('Wake Word', 'openWakeWord (Local, Free)'),
          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: JarvisColors.surfaceLight,
              foregroundColor: JarvisColors.cyan,
              side: const BorderSide(color: JarvisColors.cyan),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('SAVE SETTINGS', style: TextStyle(
              letterSpacing: 3, fontSize: 12, fontFamily: 'Orbitron')),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: const TextStyle(
      color: JarvisColors.textSecondary, fontSize: 10,
      letterSpacing: 2, fontFamily: 'Orbitron')),
  );

  Widget _label(String text) => Text(text,
    style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 11, fontFamily: 'Orbitron'));

  Widget _textField(TextEditingController c, String hint) => TextField(
    controller: c,
    style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 12, fontFamily: 'Orbitron'),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: JarvisColors.textDim, fontSize: 11, fontFamily: 'Orbitron'),
      filled: true,
      fillColor: JarvisColors.surfaceLight,
      border: OutlineInputBorder(
        borderSide: const BorderSide(color: JarvisColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: JarvisColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: JarvisColors.cyan),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
    title: Text(label, style: const TextStyle(
      color: JarvisColors.textPrimary, fontSize: 11, fontFamily: 'Orbitron')),
    value: value,
    onChanged: onChanged,
    activeColor: JarvisColors.cyan,
    contentPadding: EdgeInsets.zero,
  );

  Widget _infoRow(String key, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(key, style: const TextStyle(color: JarvisColors.textDim, fontSize: 10, fontFamily: 'Orbitron')),
        Text(val, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 10, fontFamily: 'Orbitron')),
      ],
    ),
  );
}
