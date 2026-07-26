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
const _seenIdsKey = 'posex_push_seen_ids_v1';
const _maxSeenIds = 80;

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

  static int _notificationIdForGroup(String groupKey) =>
      groupKey.hashCode & 0x7fffffff;

  static Future<void> ensureLocalNotificationsReady() async {
    if (_localReady) return;
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_print');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTappedBackground,
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

  @pragma('vm:entry-point')
  static void _onNotificationTappedBackground(NotificationResponse response) {
    // ignore: discarded_futures
    clearGroup(response.payload);
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // ignore: discarded_futures
    clearGroup(response.payload);
  }

  /// Clear stored lines + dismiss tray notification for a group (or all).
  static Future<void> clearGroup([String? groupKey]) async {
    try {
      await ensureLocalNotificationsReady();
      final prefs = await SharedPreferences.getInstance();
      if (groupKey != null && groupKey.trim().isNotEmpty) {
        final key = groupKey.trim();
        await prefs.remove('$_prefsPrefix$key');
        await _localNotifications.cancel(_notificationIdForGroup(key));
        return;
      }
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefsPrefix)).toList();
      for (final k in keys) {
        final gk = k.substring(_prefsPrefix.length);
        await prefs.remove(k);
        await _localNotifications.cancel(_notificationIdForGroup(gk));
      }
    } catch (e) {
      debugPrint('[Push] clearGroup failed: $e');
    }
  }

  /// Call when app is opened / resumed so tray + stash stay in sync.
  static Future<void> onAppOpened() async {
    try {
      await ensureLocalNotificationsReady();
      final launch = await _localNotifications.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response?.payload != null) {
        await clearGroup(response!.payload);
      }
      // Also handle FCM tap that opened the app.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        final ntype = (initial.data['notification_type'] ?? '').toString().trim();
        await clearGroup(ntype.isEmpty ? 'general' : ntype);
      }
    } catch (e) {
      debugPrint('[Push] onAppOpened failed: $e');
    }
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
      FirebaseMessaging.onMessageOpenedApp.listen((message) async {
        final ntype = (message.data['notification_type'] ?? '').toString().trim();
        await clearGroup(ntype.isEmpty ? 'general' : ntype);
      });
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
    await onAppOpened();
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

      // Drop FCM retries / double-delivery of the same message id.
      final messageId = (message.messageId ?? '').trim();
      if (messageId.isNotEmpty && await _wasAlreadySeen(messageId)) {
        debugPrint('[Push] skip duplicate messageId=$messageId');
        return;
      }
      if (messageId.isNotEmpty) {
        await _markSeen(messageId);
      }

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

  static Future<bool> _wasAlreadySeen(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenIdsKey) ?? <String>[];
    return seen.contains(messageId);
  }

  static Future<void> _markSeen(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenIdsKey) ?? <String>[];
    seen.remove(messageId);
    seen.add(messageId);
    final trimmed = seen.length > _maxSeenIds
        ? seen.sublist(seen.length - _maxSeenIds)
        : seen;
    await prefs.setStringList(_seenIdsKey, trimmed);
  }

  static Future<void> _showGroupedNotification({
    required String title,
    required String body,
    required String notificationType,
  }) async {
    final groupKey = notificationType.isNotEmpty ? notificationType : 'general';
    final cleaned = body.trim();
    if (cleaned.isEmpty) return;

    // Replace any previous notification for this type — only the latest stays.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_prefsPrefix$groupKey', [cleaned]);
    final notificationId = _notificationIdForGroup(groupKey);
    await _localNotifications.cancel(notificationId);

    final details = AndroidNotificationDetails(
      _channelId,
      'PosEx notifications',
      channelDescription: 'Sales, refunds, register and employee alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_print',
      styleInformation: BigTextStyleInformation(
        cleaned,
        contentTitle: title,
        summaryText: _groupLabels[groupKey],
      ),
      autoCancel: true,
      onlyAlertOnce: false,
    );

    await _localNotifications.show(
      notificationId,
      title,
      cleaned,
      NotificationDetails(android: details),
      payload: groupKey,
    );
  }
}
