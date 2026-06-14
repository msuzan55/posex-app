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

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

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
          'pwaBasePath': '/app/',
          'endpointHint': endpoint,
        }),
      );
      if (res.statusCode >= 400) {
        debugPrint('[Push] register failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('[Push] register error: $e');
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
