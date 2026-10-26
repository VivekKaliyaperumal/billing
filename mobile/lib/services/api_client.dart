import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../app_info.dart';

/// A failed API call. [status] is 0 when the server could not be reached.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);
  final int status;

  /// The server's stable error code, e.g. `phone_taken`, or `network`.
  final String code;

  /// Safe to show to the user.
  final String message;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'ApiException($status, $code): $message';
}

/// HTTP client for the sync server. Sends the access token as a Bearer
/// header and, when it has expired, swaps the refresh token for new ones
/// once and retries. Tokens live in the platform's secure storage.
class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage, this._baseUrl = apiBaseUrl})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'tb_access_token';
  static const _refreshKey = 'tb_refresh_token';
  static const _timeout = Duration(seconds: 20);

  final http.Client _client;
  final FlutterSecureStorage _storage;
  final String _baseUrl;

  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  /// Called when the server no longer accepts the refresh token.
  void Function()? onSessionExpired;

  bool get hasSession => _refresh != null;
  String? get refreshToken => _refresh;

  Future<void> loadTokens() async {
    try {
      _access = await _storage.read(key: _accessKey);
      _refresh = await _storage.read(key: _refreshKey);
    } catch (_) {
      // Unreadable keystore (e.g. after a backup restore to a new phone):
      // treat as signed out rather than crash.
      _access = null;
      _refresh = null;
    }
  }

  Future<void> saveTokens(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clearTokens() async {
    _access = null;
    _refresh = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async =>
      _asMap(await request('GET', path, query: query));

  /// [body] is encoded as JSON, unless it is already a JSON string.
  Future<Map<String, dynamic>> post(String path, Object? body, {Duration? timeout, Map<String, String>? query}) async =>
      _asMap(await request('POST', path, body: body, timeout: timeout, query: query));

  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration? timeout,
    bool auth = true,
  }) async {
    var res = await _send(method, path, body: body, query: query, timeout: timeout, auth: auth);
    if (res.statusCode == 401 && auth && _refresh != null && await _refreshTokens()) {
      res = await _send(method, path, body: body, query: query, timeout: timeout, auth: auth);
    }
    final decoded = _decode(res);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    final err = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    throw ApiException(
      res.statusCode,
      err['code'] as String? ?? 'error',
      err['message'] as String? ?? 'Something went wrong. Please try again.',
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration? timeout,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri);
    req.headers['Accept'] = 'application/json';
    if (auth && _access != null) req.headers['Authorization'] = 'Bearer $_access';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = body is String ? body : jsonEncode(body);
    }
    try {
      final streamed = await _client.send(req).timeout(timeout ?? _timeout);
      return await http.Response.fromStream(streamed).timeout(timeout ?? _timeout);
    } on SocketException {
      throw const ApiException(0, 'network', 'No internet connection. Changes are kept on this phone.');
    } on TimeoutException {
      throw const ApiException(0, 'network', 'The server took too long to respond. Changes are kept on this phone.');
    } on http.ClientException {
      throw const ApiException(0, 'network', 'Could not reach the server. Changes are kept on this phone.');
    } on HandshakeException {
      throw const ApiException(0, 'network', 'Could not make a secure connection to the server.');
    }
  }

  /// Only one refresh runs at a time; concurrent 401s wait for it.
  Future<bool> _refreshTokens() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final token = _refresh;
    if (token == null) return false;
    final http.Response res;
    try {
      res = await _send('POST', '/auth/refresh', body: {'refreshToken': token, 'client': 'mobile'}, auth: false);
    } on ApiException {
      return false;
    }
    if (res.statusCode == 200) {
      final j = _asMap(_decode(res));
      await saveTokens(j['accessToken'] as String, j['refreshToken'] as String);
      return true;
    }
    if (res.statusCode == 401) {
      await clearTokens();
      onSessionExpired?.call();
    }
    return false;
  }

  static Object? _decode(http.Response res) {
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _asMap(Object? v) => v is Map<String, dynamic> ? v : <String, dynamic>{};
}
