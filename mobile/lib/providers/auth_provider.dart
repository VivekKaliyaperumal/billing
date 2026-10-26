import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sync_models.dart';
import '../services/api_client.dart';

class AccountUser {
  const AccountUser({required this.id, required this.email, required this.name, required this.role});
  final String id;
  final String email;
  final String name;

  /// `owner` or `cashier`.
  final String role;

  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(
    id: j['id'] as String,
    email: j['email'] as String,
    name: j['name'] as String,
    role: j['role'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name, 'role': role};
}

/// The signed-in account, if any. Signing in is optional: signed out, the
/// app works on this phone only, exactly as before. The user and shop are
/// cached so the app knows who is signed in when it starts offline.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._api, this._prefs) {
    _api.onSessionExpired = _expired;
  }

  static const _accountKey = 'sync_account';

  final ApiClient _api;
  final SharedPreferences _prefs;

  AccountUser? _user;
  ShopInfo? _shop;
  bool _sessionExpired = false;

  AccountUser? get user => _user;
  ShopInfo? get shop => _shop;
  bool get isSignedIn => _user != null;

  /// True once the server stopped accepting this login (password changed,
  /// account disabled); the user must sign in again to keep syncing.
  bool get sessionExpired => _sessionExpired;

  /// Owner-only actions are always available when not signed in: the phone
  /// is then the shop's only copy of its data.
  bool get isOwner => _user == null || _user!.role == 'owner';

  /// Restores the saved login without using the network.
  Future<void> restore() async {
    await _api.loadTokens();
    final raw = _prefs.getString(_accountKey);
    if (raw == null || !_api.hasSession) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _user = AccountUser.fromJson(j['user'] as Map<String, dynamic>);
      _shop = ShopInfo.fromJson(j['shop'] as Map<String, dynamic>);
    } catch (_) {
      _user = null;
      _shop = null;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final res = await _api.post('/auth/login', {'email': email.trim(), 'password': password, 'client': 'mobile'});
    await _accept(res);
  }

  /// Creates a new shop with this person as its owner.
  Future<void> signUp({
    required String shopName,
    required String name,
    required String email,
    required String password,
    required String currency,
  }) async {
    final res = await _api.post('/auth/signup', {
      'shopName': shopName.trim(),
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'currency': currency,
      'client': 'mobile',
    });
    await _accept(res);
  }

  /// Ends the login on the server (best effort) and on this phone. Data on
  /// the phone is kept.
  Future<void> signOut() async {
    final token = _api.refreshToken;
    if (token != null) {
      try {
        await _api.request('POST', '/auth/logout', body: {'refreshToken': token}, auth: false);
      } on ApiException {
        // Offline: the token simply expires on the server.
      }
    }
    await _api.clearTokens();
    await _prefs.remove(_accountKey);
    _user = null;
    _shop = null;
    _sessionExpired = false;
    notifyListeners();
  }

  /// Keeps the cached shop current after a sync.
  void updateShop(ShopInfo shop) {
    if (_user == null) return;
    _shop = shop;
    _save();
    notifyListeners();
  }

  Future<void> _accept(Map<String, dynamic> res) async {
    await _api.saveTokens(res['accessToken'] as String, res['refreshToken'] as String);
    _user = AccountUser.fromJson(res['user'] as Map<String, dynamic>);
    _shop = ShopInfo.fromJson(res['shop'] as Map<String, dynamic>);
    _sessionExpired = false;
    _save();
    notifyListeners();
  }

  void _save() {
    unawaited(_prefs.setString(_accountKey, jsonEncode({'user': _user!.toJson(), 'shop': _shop!.toJson()})));
  }

  void _expired() {
    if (_user == null) return;
    _sessionExpired = true;
    _user = null;
    _shop = null;
    unawaited(_prefs.remove(_accountKey));
    notifyListeners();
  }
}
