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

/// Registers the device FCM token with the API (same notifications as PWA).
class PushRegistrationService {
  PushRegistrationService._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String? _authToken;
  static bool _registeredWithServer = false;

  static bool get isRegisteredWithServer => _registeredWithServer;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (DefaultFirebaseOptions.android.appId.contains('placeholder')) {
      debugPrint('[Push] Firebase skipped — configure google-services / app id');
      return;
    }

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('[Push] Firebase init skipped: $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (_) {},
    );

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen((_) {});

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerToken(token);

    FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);
  }

  static void setAuthToken(String? token) {
    _authToken = (token != null && token.trim().isNotEmpty) ? token.trim() : null;
    FirebaseMessaging.instance.getToken().then((t) {
      if (t != null) _registerToken(t);
    });
  }

  static Future<void> _registerToken(String token) async {
    final auth = _authToken;
    if (auth == null) return;

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
        debugPrint('[Push] register failed: ${res.statusCode} ${res.body}');
        _registeredWithServer = false;
      } else {
        _registeredWithServer = true;
      }
    } catch (e) {
      debugPrint('[Push] register error: $e');
      _registeredWithServer = false;
    }
  }

  /// Called from WebView bridge when user taps Enable in Settings.
  static Future<bool> enableFromUser() async {
    await init();
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return false;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerToken(token);
    return _registeredWithServer || token != null;
  }

  static Future<bool> queryStatus() async {
    if (DefaultFirebaseOptions.android.appId.contains('placeholder')) return false;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      return granted && (_registeredWithServer || (_authToken != null && await FirebaseMessaging.instance.getToken() != null));
    } catch (_) {
      return false;
    }
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    const details = AndroidNotificationDetails(
      'posex_push',
      'PosEx notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _localNotifications.show(
      message.hashCode,
      n.title,
      n.body,
      const NotificationDetails(android: details),
    );
  }
}
