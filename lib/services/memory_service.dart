import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryService extends ChangeNotifier {
  List<Map<String, String>> _longTermMemory = [];
  SharedPreferences? _prefs;

  List<Map<String, String>> get longTermMemory => List.unmodifiable(_longTermMemory);

  MemoryService() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadMemory();
  }

  void _loadMemory() {
    final stored = _prefs?.getStringList('jarvis_memory') ?? [];
    _longTermMemory = stored
        .map((e) => Map<String, String>.from(jsonDecode(e)))
        .toList();
    notifyListeners();
  }

  Future<void> saveMemory(String key, String value) async {
    _longTermMemory.add({'key': key, 'value': value, 'timestamp': DateTime.now().toIso8601String()});
    await _persist();
    notifyListeners();
  }

  Future<void> deleteMemory(int index) async {
    if (index >= 0 && index < _longTermMemory.length) {
      _longTermMemory.removeAt(index);
      await _persist();
      notifyListeners();
    }
  }

  Future<void> clearAllMemory() async {
    _longTermMemory.clear();
    await _prefs?.remove('jarvis_memory');
    notifyListeners();
  }

  Future<void> _persist() async {
    final stored = _longTermMemory.map((e) => jsonEncode(e)).toList();
    await _prefs?.setStringList('jarvis_memory', stored);
  }

  String buildMemoryContext() {
    if (_longTermMemory.isEmpty) return '';
    final buffer = StringBuffer('User memory notes:\n');
    for (final m in _longTermMemory) {
      buffer.writeln('- ${m['key']}: ${m['value']}');
    }
    return buffer.toString();
  }
}
