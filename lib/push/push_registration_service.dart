import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

const _apiBase = 'https://posex.lk';
const _fcmEndpointPrefix = 'fcm-native:';

/// Background FCM handler (top-level).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class NativePushStatus {
  const NativePushStatus({
    required this.enabled,
    required this.permissionGranted,
    required this.hasFcmToken,
    required this.registeredWithServer,
    this.error,
  });

  final bool enabled;
  final bool permissionGranted;
  final bool hasFcmToken;
  final bool registeredWithServer;
  final String? error;
}

/// Registers the device FCM token with the API (same notifications as PWA).
class PushRegistrationService {
  PushRegistrationService._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _firebaseReady = false;
  static String? _authToken;
  static bool _registeredWithServer = false;
  static String? _lastError;

  static bool get isRegisteredWithServer => _registeredWithServer;

  static Future<bool> _ensureFirebase() async {
    if (DefaultFirebaseOptions.android.appId.contains('placeholder')) {
      _lastError = 'Firebase not configured in this build';
      return false;
    }
    if (_firebaseReady) return true;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      const androidInit = AndroidInitializationSettings('@drawable/ic_stat_print');
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: (_) {},
      );

      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      FirebaseMessaging.onMessageOpenedApp.listen((_) {});
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

      _firebaseReady = true;
      return true;
    } catch (e) {
      _lastError = 'Firebase init failed: $e';
      debugPrint('[Push] $_lastError');
      return false;
    }
  }

  static Future<void> init() async {
    if (!await _ensureFirebase()) return;
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerToken(token);
  }

  static Future<void> setAuthToken(String? token) async {
    _authToken = (token != null && token.trim().isNotEmpty) ? token.trim() : null;
    if (_authToken == null) {
      _registeredWithServer = false;
      return;
    }
    if (!await _ensureFirebase()) return;
    final fcm = await FirebaseMessaging.instance.getToken();
    if (fcm != null) await _registerToken(fcm);
  }

  static Future<void> _registerToken(String token) async {
    final auth = _authToken;
    if (auth == null) {
      _lastError = 'Log in to register push notifications';
      _registeredWithServer = false;
      return;
    }

    final endpoint = '$_fcmEndpointPrefix$token';
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/api/v1/notifications/subscribe-fcm'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $auth',
        },
        body: jsonEncode({
          'token': token,
          'pwaBasePath': '/test/',
          'endpointHint': endpoint,
        }),
      );
      if (res.statusCode >= 400) {
        _lastError = 'Server registration failed (${res.statusCode})';
        debugPrint('[Push] register failed: ${res.statusCode} ${res.body}');
        _registeredWithServer = false;
      } else {
        _lastError = null;
        _registeredWithServer = true;
      }
    } catch (e) {
      _lastError = 'Network error registering push';
      debugPrint('[Push] register error: $e');
      _registeredWithServer = false;
    }
  }

  static Future<bool> _permissionGranted() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Called from WebView bridge when user taps Enable in Settings.
  static Future<NativePushStatus> enableFromUser() async {
    if (!await _ensureFirebase()) {
      return getStatus();
    }

    var granted = await _permissionGranted();
    if (!granted) {
      final req = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = req.authorizationStatus == AuthorizationStatus.authorized ||
          req.authorizationStatus == AuthorizationStatus.provisional;
    }
    if (!granted) {
      _lastError = 'Notification permission not granted';
      return getStatus();
    }

    if (_authToken == null) {
      _lastError = 'Please log in first, then enable push again';
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registerToken(token);
    } else {
      _lastError = 'Could not get FCM device token';
    }

    return getStatus();
  }

  static Future<NativePushStatus> getStatus() async {
    if (DefaultFirebaseOptions.android.appId.contains('placeholder')) {
      return const NativePushStatus(
        enabled: false,
        permissionGranted: false,
        hasFcmToken: false,
        registeredWithServer: false,
        error: 'Firebase not configured',
      );
    }

    if (!await _ensureFirebase()) {
      return NativePushStatus(
        enabled: false,
        permissionGranted: false,
        hasFcmToken: false,
        registeredWithServer: false,
        error: _lastError,
      );
    }

    final granted = await _permissionGranted();
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    final hasToken = fcmToken != null && fcmToken.isNotEmpty;
    if (granted && hasToken && _authToken == null && !_registeredWithServer) {
      _lastError ??= 'Log in, then tap Enable again';
    }

    return NativePushStatus(
      enabled: granted && hasToken && _registeredWithServer,
      permissionGranted: granted,
      hasFcmToken: hasToken,
      registeredWithServer: _registeredWithServer,
      error: _registeredWithServer ? null : _lastError,
    );
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    const details = AndroidNotificationDetails(
      'posex_push',
      'PosEx notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_print',
    );
    await _localNotifications.show(
      message.hashCode,
      n.title,
      n.body,
      const NotificationDetails(android: details),
    );
  }
}
