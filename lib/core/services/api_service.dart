import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  /// Real Google Maps API Key
  static const String googleMapsApiKey = 'AIzaSyBa6Sfh7UbFlueqmLXSJbWEEoIYoeIpEXs';

  // Live Spring Boot Java Backend on Cloud Server (3.85.81.10)
  static const String serverHost = 'http://3.85.81.10';
  static const String liveServerBaseUrl = 'http://3.85.81.10:8080/api/v1';

  static String get defaultBaseUrl {
    return liveServerBaseUrl;
  }

  String _baseUrl = defaultBaseUrl;
  String? _token;
  final Map<String, String> _headers = {'Content-Type': 'application/json'};

  String? get currentToken => _token;
  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) => _baseUrl = url;

  /// Sets real Bearer JWT token
  void setToken(String token) {
    _token = token;
    _headers['Authorization'] = 'Bearer $token';
  }

  void clearToken() {
    _token = null;
    _headers.remove('Authorization');
  }

  /// Parses real JWT claims (Payload) in client
  Map<String, dynamic>? parseJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = _decodeBase64(parts[1]);
      final payloadMap = jsonDecode(payload);
      if (payloadMap is Map<String, dynamic>) {
        return payloadMap;
      }
    } catch (_) {}
    return null;
  }

  bool isTokenExpired(String token) {
    final claims = parseJwt(token);
    if (claims == null || !claims.containsKey('exp')) return false;
    final exp = claims['exp'] as int;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now > exp;
  }

  String _decodeBase64(String str) {
    String output = str.replaceAll('-', '+').replaceAll('_', '/');
    switch (output.length % 4) {
      case 0:
        break;
      case 2:
        output += '==';
        break;
      case 3:
        output += '=';
        break;
      default:
        throw Exception('Illegal base64url string!');
    }
    return utf8.decode(base64Url.decode(output));
  }

  Future<Map<String, dynamic>> get(String path) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    return _handle(response);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    return _handle(response);
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    return _handle(response);
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    return _handle(response);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    return _handle(response);
  }

  Map<String, dynamic> _handle(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return {
          'data': decoded,
          'rows': decoded,
          'vehicles': decoded,
          'events': decoded,
          'trips': decoded,
          'count': decoded.length,
        };
      }
      return decoded as Map<String, dynamic>;
    } else {
      dynamic errorData;
      try {
        errorData = jsonDecode(response.body);
      } catch (_) {}
      throw ApiException(
        statusCode: response.statusCode,
        message: (errorData is Map)
            ? (errorData['message'] ?? errorData['error'] ?? 'Request failed')
            : 'Request failed (${response.statusCode})',
      );
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
