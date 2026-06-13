import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService})
    : _authService = authService ?? AuthService();

  final AuthService _authService;

  AuthStatus status = AuthStatus.unknown;
  PosexUser? user;
  String? token;
  String? errorMessage;
  bool isBusy = false;

  Future<void> bootstrap() async {
    isBusy = true;
    notifyListeners();

    try {
      final restored = await _authService.restoreSession();
      if (restored != null) {
        user = restored;
        token = await _authService.loadStoredToken();
        status = AuthStatus.authenticated;
      } else {
        status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      status = AuthStatus.unauthenticated;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    errorMessage = null;
    isBusy = true;
    notifyListeners();

    try {
      final result = await _authService.login(
        username: username,
        password: password,
      );
      token = result.token;
      user = result.user;
      status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (error) {
      errorMessage = error.message;
      status = AuthStatus.unauthenticated;
      return false;
    } catch (_) {
      errorMessage = 'Could not sign in. Check your connection.';
      status = AuthStatus.unauthenticated;
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _authService.clearSession();
    user = null;
    token = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
