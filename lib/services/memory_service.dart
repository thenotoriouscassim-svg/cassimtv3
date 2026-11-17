import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class MemoryService extends ChangeNotifier {
  List<Map<String, String>> _longTermMemory = [];
  SharedPreferences? _prefs;
  String? _accountToken;

  List<Map<String, String>> get longTermMemory => List.unmodifiable(_longTermMemory);

  MemoryService() { _init(); }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _accountToken = _prefs?.getString('jarvis_account_token');
    _loadMemory();
    if (_accountToken != null) await _loadCloudMemory();
  }

  void _loadMemory() {
    final stored = _prefs?.getStringList('jarvis_memory') ?? [];
    _longTermMemory = stored.map((e) => Map<String, String>.from(jsonDecode(e))).toList();
    notifyListeners();
  }

  Future<void> setAccountToken(String token) async {
    _accountToken = token;
    await _loadCloudMemory();
  }

  Future<void> _loadCloudMemory() async {
    if (_accountToken == null) return;
    try {
      final response = await http.get(Uri.parse(JarvisStrings.backendUrl + '/memories'),
        headers: {'Authorization': 'Bearer ' + _accountToken!}).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return;
      final rows = (jsonDecode(response.body)['memories'] as List<dynamic>? ?? []);
      _longTermMemory = rows.whereType<Map>().map((row) =>
        row.map((key, value) => MapEntry(key.toString(), value.toString()))).toList();
      await _persist();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> saveMemory(String key, String value) async {
    if (_accountToken != null) {
      try {
        final response = await http.post(Uri.parse(JarvisStrings.backendUrl + '/memories'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + _accountToken!},
          body: jsonEncode({'key': key, 'value': value})).timeout(const Duration(seconds: 20));
        if (response.statusCode == 201) {
          final row = Map<String, dynamic>.from(jsonDecode(response.body));
          _longTermMemory.insert(0, row.map((k, v) => MapEntry(k.toString(), v.toString())));
          await _persist();
          notifyListeners();
          return;
        }
      } catch (_) {}
    }
    _longTermMemory.add({'key': key, 'value': value, 'timestamp': DateTime.now().toIso8601String()});
    await _persist();
    notifyListeners();
  }

  Future<void> deleteMemory(int index) async {
    if (index >= 0 && index < _longTermMemory.length) {
      final removed = _longTermMemory.removeAt(index);
      final id = removed['id'];
      if (_accountToken != null && id != null) {
        try {
          await http.delete(Uri.parse(JarvisStrings.backendUrl + '/memories/' + id),
            headers: {'Authorization': 'Bearer ' + _accountToken!}).timeout(const Duration(seconds: 15));
        } catch (_) {}
      }
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
      buffer.writeln('- ' + (m['key'] ?? '') + ': ' + (m['value'] ?? ''));
    }
    return buffer.toString();
  }
}
