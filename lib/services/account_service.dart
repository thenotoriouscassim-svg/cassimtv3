import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class AccountService extends ChangeNotifier {
  String? _token;
  String? _username;
  bool _ready = false;
  bool _busy = false;
  String? _error;
  bool _hasRecovery = false;
  String? _recoveryQuestion;

  String? get token => _token;
  String? get username => _username;
  bool get isReady => _ready;
  bool get isBusy => _busy;
  bool get isLoggedIn => _token != null && _username != null;
  String? get error => _error;
  bool get hasRecovery => _hasRecovery;
  String? get recoveryQuestion => _recoveryQuestion;

  AccountService() { _restore(); }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jarvis_account_token');
    _username = prefs.getString('jarvis_account_username');
    _hasRecovery = prefs.getBool('jarvis_has_recovery') ?? false;
    if (_token != null) {
      try {
        final r = await http.get(Uri.parse('${JarvisStrings.backendUrl}/auth/me'),
          headers: {'Authorization': 'Bearer $_token'}).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) { _token = null; _username = null; await prefs.remove('jarvis_account_token'); await prefs.remove('jarvis_account_username'); }
        else { final data = jsonDecode(r.body) as Map<String,dynamic>; _username = data['user']?['username']?.toString() ?? _username; _hasRecovery = data['user']?['has_recovery'] == true; await prefs.setBool('jarvis_has_recovery', _hasRecovery); }
      } catch (_) {
        // Keep a previously issued token during a temporary network outage.
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<bool> signUp(String username, String password, String question, String answer) => _authenticate('signup', username, password, question: question, answer: answer);
  Future<bool> login(String username, String password) => _authenticate('login', username, password);

  Future<bool> _authenticate(String action, String username, String password, {String? question, String? answer}) async {
    _busy = true; _error = null; notifyListeners();
    try {
      final r = await http.post(Uri.parse('${JarvisStrings.backendUrl}/auth/$action'),
        headers: {'Content-Type':'application/json'},
        body: jsonEncode({'username':username.trim(),'password':password, if(question != null) 'recovery_question':question, if(answer != null) 'recovery_answer':answer}))
        .timeout(const Duration(seconds:25));
      final data = jsonDecode(r.body) as Map<String,dynamic>;
      if (r.statusCode != 200 && r.statusCode != 201) {
        _error = data['detail']?.toString() ?? 'Could not sign in. Please try again.';
        return false;
      }
      _token = data['token']?.toString();
      _username = data['user']?['username']?.toString();
      _hasRecovery = data['user']?['has_recovery'] == true;
      if (_token == null || _username == null) throw Exception('The account server returned an incomplete session.');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jarvis_account_token', _token!);
      await prefs.setString('jarvis_account_username', _username!);
      await prefs.setBool('jarvis_has_recovery', _hasRecovery);
      return true;
    } catch (e) {
      _error = 'Could not reach the account server. Check your connection and try again.';
      return false;
    } finally {
      _busy = false; notifyListeners();
    }
  }


  Future<String?> fetchRecoveryQuestion(String username) async {
    _busy = true; _error = null; _recoveryQuestion = null; notifyListeners();
    try {
      final r = await http.post(Uri.parse('${JarvisStrings.backendUrl}/auth/recovery-question'),
        headers: {'Content-Type':'application/json'}, body: jsonEncode({'username':username.trim()})).timeout(const Duration(seconds:15));
      final data = jsonDecode(r.body) as Map<String,dynamic>;
      if (r.statusCode != 200) { _error = data['detail']?.toString() ?? 'Could not retrieve recovery question.'; return null; }
      _recoveryQuestion = data['question']?.toString(); return _recoveryQuestion;
    } catch (_) { _error = 'Could not reach the account server.'; return null; }
    finally { _busy = false; notifyListeners(); }
  }

  Future<bool> resetPassword(String username, String answer, String newPassword) async {
    _busy = true; _error = null; notifyListeners();
    try {
      final r = await http.post(Uri.parse('${JarvisStrings.backendUrl}/auth/reset-password'),
        headers: {'Content-Type':'application/json'},
        body: jsonEncode({'username':username.trim(),'recovery_answer':answer,'new_password':newPassword})).timeout(const Duration(seconds:20));
      final data = jsonDecode(r.body) as Map<String,dynamic>;
      if (r.statusCode != 200) { _error = data['detail']?.toString() ?? 'Password reset failed.'; return false; }
      return true;
    } catch (_) { _error = 'Could not reach the account server.'; return false; }
    finally { _busy = false; notifyListeners(); }
  }

  Future<bool> setRecoveryQuestion(String question, String answer) async {
    if (_token == null) return false;
    _busy = true; _error = null; notifyListeners();
    try {
      final r = await http.post(Uri.parse('${JarvisStrings.backendUrl}/auth/set-recovery'),
        headers: {'Content-Type':'application/json','Authorization':'Bearer $_token'},
        body: jsonEncode({'recovery_question':question,'recovery_answer':answer})).timeout(const Duration(seconds:15));
      final data = jsonDecode(r.body) as Map<String,dynamic>;
      if (r.statusCode != 200) { _error = data['detail']?.toString() ?? 'Could not save recovery question.'; return false; }
      _hasRecovery = true; return true;
    } catch (_) { _error = 'Could not reach the account server.'; return false; }
    finally { _busy = false; notifyListeners(); }
  }

  Future<void> logout() async {
    final old = _token;
    _token = null; _username = null; _hasRecovery = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jarvis_account_token');
    await prefs.remove('jarvis_account_username');
    await prefs.remove('jarvis_has_recovery');
    if (old != null) {
      try { await http.post(Uri.parse('${JarvisStrings.backendUrl}/auth/logout'),
        headers: {'Authorization':'Bearer $old'}).timeout(const Duration(seconds:10)); } catch (_) {}
    }
    notifyListeners();
  }
}
