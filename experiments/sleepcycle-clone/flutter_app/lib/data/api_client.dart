// Client for the mock backend (mock-api/server.js).
// Base URL: Android emulator -> http://10.0.2.2:8787 ; iOS sim -> http://127.0.0.1:8787

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class SleepApi {
  final String baseUrl;
  final http.Client _client;
  String? _token;

  SleepApi({this.baseUrl = 'http://127.0.0.1:8787', http.Client? client})
      : _client = client ?? http.Client();

  bool get isAuthed => _token != null;
  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  Future<void> login(String email, String password) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/self-service/login/api'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    _token = (jsonDecode(r.body) as Map<String, dynamic>)['session_token'] as String?;
  }

  Future<Map<String, dynamic>> remoteConfig() async =>
      _get('/v1/config');

  Future<List<Map<String, dynamic>>> paywallProducts() async {
    final j = await _get('/v1/paywall');
    return (j['products'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> sleepAidPackages() async {
    final j = await _get('/v1/sleep-aid');
    return (j['packages'] as List).cast<Map<String, dynamic>>();
  }

  Future<String> uploadSession(SleepSession s) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/v1/sessions'),
      headers: _headers,
      body: jsonEncode({...s.toJson(), 'minutesAsleep': s.minutesAsleep}),
    );
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<Map<String, dynamic>> insights() async => _get('/v1/insights');

  Future<Map<String, dynamic>> _get(String pathPart) async {
    final r = await _client.get(Uri.parse('$baseUrl$pathPart'), headers: _headers);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
