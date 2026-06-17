import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static String? baseUrl;

  final _auth = AuthService();

  // ---------- core request ----------

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool isRetry = false,
  }) async {
    if (baseUrl == null) throw ApiException(503, 'Not configured — sign out and log in again');
    final url = Uri.parse('$baseUrl$path');
    final token = await _auth.getAccessToken();
    if (token == null) throw ApiException(401, 'No access token');

    final headers = {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(url, headers: headers);
      case 'POST':
        response = await http.post(url, headers: headers, body: jsonEncode(body ?? {}));
      case 'DELETE':
        response = await http.delete(url, headers: headers);
      default:
        throw ArgumentError('Unknown method: $method');
    }

    if (response.statusCode == 401 && !isRetry) {
      final refreshed = await _refreshTokens();
      if (!refreshed) throw ApiException(401, 'Session expired');
      return _request(method, path, body: body, isRetry: true);
    }

    if (response.statusCode >= 400) {
      String message;
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        message = (decoded['error'] as String?) ?? response.body;
      } catch (_) {
        message = response.body;
      }
      throw ApiException(response.statusCode, message);
    }

    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  // Delegates to AuthService — single source of truth for refresh logic.
  // Does NOT clear tokens on network exceptions; only auth failures cause logout.
  Future<bool> _refreshTokens() => _auth.silentRefresh();

  // HTTP layer for /api/refresh — called by AuthService.silentRefresh().
  Future<Map<String, dynamic>?> refresh(String refreshToken) async {
    if (baseUrl == null) return null;
    try {
      final url = Uri.parse('$baseUrl/api/refresh');
      final response = await http.post(
        url,
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ---------- endpoints ----------

  Future<List<Map<String, dynamic>>> searchWiki(String query) async {
    final encoded = Uri.encodeComponent(query);
    final data = await _request('GET', '/api/wiki/search?q=$encoded');
    return ((data as Map<String, dynamic>)['results'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<String> capture(String text) async {
    final data = await _request('POST', '/api/capture', body: {'text': text});
    return (data as Map<String, dynamic>)['reply'] as String? ?? '';
  }

  Future<List<dynamic>> wikiList() async {
    final data = await _request('GET', '/api/wiki');
    return (data as Map<String, dynamic>)['files'] as List<dynamic>;
  }

  Future<String> wikiFile(String path) async {
    final encoded = Uri.encodeComponent(path);
    final data = await _request('GET', '/api/wiki/$encoded');
    return (data as Map<String, dynamic>)['content'] as String;
  }

}
