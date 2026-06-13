import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/user.dart';
import 'api_client.dart';

class AuthService {
  AuthService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  static const _tokenKey = 'posex_access_token';
  static const _userKey = 'posex_user';

  final ApiClient _api;

  Future<({String token, PosexUser user})> login({
    required String username,
    required String password,
  }) async {
    final data = await _api.postForm(ApiConfig.authLogin, {
      'username': username.trim(),
      'password': password,
    });

    final token = data['access_token']?.toString();
    final userJson = data['user'];
    if (token == null || token.isEmpty || userJson is! Map<String, dynamic>) {
      throw ApiException('Invalid response from server.');
    }

    final user = PosexUser.fromJson(userJson);
    await _persistSession(token, user);
    return (token: token, user: user);
  }

  Future<PosexUser?> loadStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return PosexUser.fromJson(json);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> loadStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<PosexUser?> restoreSession() async {
    final token = await loadStoredToken();
    if (token == null || token.isEmpty) return null;

    try {
      final data = await _api.getJson(ApiConfig.authMe, token: token);
      final user = PosexUser.fromJson(data);
      await _persistSession(token, user);
      return user;
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Future<void> _persistSession(String token, PosexUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }
}
