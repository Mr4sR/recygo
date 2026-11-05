import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Thin client for the RecyGo Rust backend (`BACKEND_BASE_URL`).
/// Auth reuses the Supabase session JWT; the backend verifies it server-side.
class ApiException implements Exception {
  final int status;
  final String message;
  const ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  String get _base => Env.backendBaseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> _headers({bool json = true}) {
    String? token;
    try {
      token = Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      token = null;
    }
    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  String _errorMessage(http.Response r) {
    try {
      final decoded = jsonDecode(r.body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    if (r.statusCode == 401) return 'Session expired. Please sign in again.';
    return 'AI service is temporarily unavailable.';
  }

  Future<dynamic> getJson(String path) async {
    final r = await http
        .get(Uri.parse('$_base$path'), headers: _headers())
        .timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(r.statusCode, _errorMessage(r));
    }
    return jsonDecode(r.body);
  }

  Future<dynamic> postJson(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 65),
  }) async {
    final r = await http
        .post(
          Uri.parse('$_base$path'),
          headers: _headers(),
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(r.statusCode, _errorMessage(r));
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  Future<dynamic> patchJson(String path, Map<String, dynamic> body) async {
    final r = await http
        .patch(
          Uri.parse('$_base$path'),
          headers: _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(r.statusCode, _errorMessage(r));
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  Future<void> deleteJson(String path) async {
    final r = await http
        .delete(Uri.parse('$_base$path'), headers: _headers())
        .timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(r.statusCode, _errorMessage(r));
    }
  }

  /// Proxy upload through the backend (server presigns for RustFS).
  /// Returns the public CDN URL.
  Future<String> uploadBytes(
    Uint8List bytes, {
    required String filename,
    required String folder,
    String contentType = 'image/jpeg',
  }) async {
    final uri = Uri.parse(
      '$_base/v1/media/upload',
    ).replace(queryParameters: {'filename': filename, 'folder': folder});
    final r = await http
        .post(
          uri,
          headers: {..._headers(json: false), 'Content-Type': contentType},
          body: bytes,
        )
        .timeout(const Duration(seconds: 60));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(r.statusCode, _errorMessage(r));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map && decoded['publicUrl'] != null) {
      return decoded['publicUrl'].toString();
    }
    throw const ApiException(502, 'Media storage is unavailable.');
  }
}

final apiClient = ApiClient();

Map<String, dynamic> asJsonMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

List<dynamic> asJsonList(dynamic v) => v is List ? v : const [];
