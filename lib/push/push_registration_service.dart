import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';

const _apiBase = 'https://posex.lk';
const _fcmEndpointPrefix = 'fcm-native:';
const _channelId = 'posex_push';
const _prefsPrefix = 'posex_push_group_v1_';
const _maxGroupedItems = 8;

const _groupLabels = <String, String>{
  'sales': 'Sales',
  'edited_bills': 'Edited bills',
  'exchange_tokens': 'Exchange tokens',
  'refunds': 'Refunds',
  'supplier_bills': 'Supplier bills',
  'new_suppliers': 'New suppliers',
  'expenses': 'Expenses',
  'cash_register_closed': 'Cash register closed',
  'cash_register_opened': 'Cash register opened',
  'daily_totals': 'Daily totals',
  'employee_clock': 'Employee clock',
  'new_employees': 'New employees',
  'employee_loans': 'Employee loans',
  'employee_dayoffs': 'Employee day-offs',
  'salary_paid': 'Salary paid',
  'new_customers': 'New customers',
  'credit_payments': 'Credit payments',
  'held_bills': 'Held bills',
};

/// Background FCM handler (top-level) — shows grouped local notifications.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PushRegistrationService.ensureLocalNotificationsReady();
  await PushRegistrationService.displayFromRemoteMessage(message);
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
  static bool _localReady = false;
  static String? _authToken;
  static bool _registeredWithServer = false;
  static String? _lastError;

  static bool get isRegisteredWithServer => _registeredWithServer;

  static Future<void> ensureLocalNotificationsReady() async {
    if (_localReady) return;
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_print');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (_) {},
    );
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'PosEx notifications',
        description: 'Sales, refunds, register and employee alerts',
        importance: Importance.high,
      ),
    );
    _localReady = true;
  }

  static Future<bool> _ensureFirebase() async {
    if (!Platform.isAndroid) {
      _lastError = 'Push notifications are available on Android only';
      return false;
    }
    if (DefaultFirebaseOptions.android.appId.contains('placeholder')) {
      _lastError = 'Firebase not configured in this build';
      return false;
    }
    if (_firebaseReady) return true;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await ensureLocalNotificationsReady();

      FirebaseMessaging.onMessage.listen(displayFromRemoteMessage);
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
    if (!Platform.isAndroid) {
      return const NativePushStatus(
        enabled: false,
        permissionGranted: false,
        hasFcmToken: false,
        registeredWithServer: false,
        error: 'Push notifications are available on Android only',
      );
    }
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

  /// Show / update a grouped notification from an FCM message.
  static Future<void> displayFromRemoteMessage(RemoteMessage message) async {
    try {
      await ensureLocalNotificationsReady();
      final data = message.data;
      final n = message.notification;
      final title = (data['title'] ?? n?.title ?? 'PosEx').toString().trim();
      final body = (data['body'] ?? n?.body ?? 'New notification').toString().trim();
      final ntype = (data['notification_type'] ?? '').toString().trim();
      await _showGroupedNotification(
        title: title.isEmpty ? 'PosEx' : title,
        body: body.isEmpty ? 'New notification' : body,
        notificationType: ntype,
      );
    } catch (e) {
      debugPrint('[Push] display failed: $e');
    }
  }

  static Future<void> _showGroupedNotification({
    required String title,
    required String body,
    required String notificationType,
  }) async {
    final groupKey = notificationType.isNotEmpty ? notificationType : 'general';
    final label = _groupLabels[groupKey] ?? title;
    final lines = await _appendGroupLine(groupKey, body);
    final count = lines.length;
    final showTitle = count > 1 ? '$label ($count)' : title;
    final summary = count > 1 ? '$count new $label' : body;
    final notificationId = groupKey.hashCode & 0x7fffffff;

    final details = AndroidNotificationDetails(
      _channelId,
      'PosEx notifications',
      channelDescription: 'Sales, refunds, register and employee alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_print',
      groupKey: 'posex_$groupKey',
      setAsGroupSummary: count > 1,
      styleInformation: InboxStyleInformation(
        lines,
        contentTitle: showTitle,
        summaryText: summary,
      ),
      autoCancel: true,
    );

    await _localNotifications.show(
      notificationId,
      showTitle,
      count > 1 ? lines.last : body,
      NotificationDetails(android: details),
      payload: groupKey,
    );
  }

  static Future<List<String>> _appendGroupLine(String groupKey, String line) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsPrefix$groupKey';
    final existing = prefs.getStringList(key) ?? <String>[];
    final cleaned = line.trim();
    if (cleaned.isNotEmpty) {
      existing.add(cleaned);
    }
    final trimmed = existing.length > _maxGroupedItems
        ? existing.sublist(existing.length - _maxGroupedItems)
        : existing;
    await prefs.setStringList(key, trimmed);
    return trimmed;
  }
}
