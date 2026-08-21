import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/models/user.dart';

class AuthTokens {
  const AuthTokens({required this.access, required this.refresh});

  final String access;
  final String refresh;
}

/// Хранение JWT и профиля в shared_preferences.
class TokenStorage {
  static const _kAccess = 'auth.access';
  static const _kRefresh = 'auth.refresh';
  static const _kUser = 'auth.user';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<AuthTokens?> readTokens() async {
    final prefs = await _p;
    final access = prefs.getString(_kAccess);
    final refresh = prefs.getString(_kRefresh);
    if (access == null || refresh == null) return null;
    return AuthTokens(access: access, refresh: refresh);
  }

  Future<String?> readRefreshToken() async =>
      (await _p).getString(_kRefresh);

  Future<User?> readUser() async {
    final raw = (await _p).getString(_kUser);
    if (raw == null) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  Future<void> save({required AuthTokens tokens, User? user}) async {
    final prefs = await _p;
    await prefs.setString(_kAccess, tokens.access);
    await prefs.setString(_kRefresh, tokens.refresh);
    if (user != null) {
      await prefs.setString(_kUser, jsonEncode(user.toJson()));
    }
  }

  Future<void> saveTokens(AuthTokens tokens) async {
    final prefs = await _p;
    await prefs.setString(_kAccess, tokens.access);
    await prefs.setString(_kRefresh, tokens.refresh);
  }

  Future<void> clear() async {
    final prefs = await _p;
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kUser);
  }
}
