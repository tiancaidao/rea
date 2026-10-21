// Thin client for the mock backend (mock-api/server.js).
// Base URL: Android emulator -> http://10.0.2.2:8787 ; iOS sim -> http://127.0.0.1:8787

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class SleepApi {
  final String baseUrl;
  final http.Client _client;
  SleepApi({this.baseUrl = 'http://127.0.0.1:8787', http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, dynamic>> remoteConfig() async {
    final r = await _client.get(Uri.parse('$baseUrl/v1/config'));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<String> uploadSession(SleepSession s) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/v1/sessions'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(s.toJson()),
    );
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<Map<String, dynamic>> insights() async {
    final r = await _client.get(Uri.parse('$baseUrl/v1/insights'));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
