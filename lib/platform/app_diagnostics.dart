import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

/// Persistent logs + crash detection for PosEx (especially Windows desktop).
///
/// Logs live under application support: `logs/posex-YYYY-MM-DD.log`
/// If the app exits without calling [markCleanExit], the next launch reports
/// that the previous session ended abnormally.
class AppDiagnostics with WindowListener {
  AppDiagnostics._();

  static final AppDiagnostics instance = AppDiagnostics._();

  static bool _initialized = false;
  static File? _logFile;
  static Directory? _logDir;
  static File? _sessionMarker;
  static File? _lastFatalFile;

  /// Set when the previous run did not shut down cleanly.
  String? previousSessionIssue;

  /// Most recent fatal message written this run (also saved for next launch).
  String? lastFatalMessage;

  bool get isInitialized => _initialized;

  Directory? get logDirectory => _logDir;

  String? get logFilePath => _logFile?.path;

  static Future<void> init() async {
    if (_initialized) return;
    await instance._init();
  }

  Future<void> _init() async {
    final support = await getApplicationSupportDirectory();
    _logDir = Directory('${support.path}${Platform.pathSeparator}logs');
    await _logDir!.create(recursive: true);

    _sessionMarker = File('${support.path}${Platform.pathSeparator}session.marker');
    _lastFatalFile = File('${support.path}${Platform.pathSeparator}last-fatal-error.txt');

    await _detectPreviousAbnormalExit();
    await _writeSessionMarker();

    _logFile = File('${_logDir!.path}${Platform.pathSeparator}${_dailyLogName()}');
    await _pruneOldLogs();

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      logFlutterError(details);
      previousFlutterError?.call(details);
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      logError('Uncaught platform error', error, stack);
      return previousPlatformError?.call(error, stack) ?? false;
    };

    _initialized = true;

    PackageInfo? info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {}

    await log(
      'INFO',
      'PosEx started '
      '(platform=${Platform.operatingSystem} '
      'version=${info?.version ?? '?'} '
      'build=${info?.buildNumber ?? '?'} '
      'exe=${Platform.resolvedExecutable})',
    );

    if (previousSessionIssue != null) {
      await log('WARN', previousSessionIssue!);
    }

    final savedFatal = await _readLastFatalError();
    if (savedFatal != null && savedFatal.isNotEmpty) {
      await log('WARN', 'Last fatal error from previous run: $savedFatal');
    }
  }

  Future<void> _detectPreviousAbnormalExit() async {
    final marker = _sessionMarker;
    if (marker == null || !marker.existsSync()) return;

    String markerText;
    try {
      markerText = (await marker.readAsString()).trim();
    } catch (_) {
      markerText = '(could not read session marker)';
    }

    final fatal = await _readLastFatalError();
    if (_isSpuriousSessionIssue(markerText, fatal)) {
      await _clearSessionMarker();
      if (fatal != null && _isSpuriousSessionIssue(fatal, null)) {
        await clearLastFatalError();
      }
      return;
    }

    previousSessionIssue =
        'PosEx did not close normally last time ($markerText). '
        'It may have crashed, been force-closed, or lost power. '
        'Check the log file for details.';

    if (fatal != null && fatal.isNotEmpty) {
      previousSessionIssue = '$previousSessionIssue\n\nLast error:\n$fatal';
    }
  }

  bool _isSpuriousSessionIssue(String? markerText, String? fatal) {
    final combined = '${markerText ?? ''}\n${fatal ?? ''}'.toLowerCase();
    if (combined.trim().isEmpty) return false;
    if (combined.contains(r'\temp\') || combined.contains(r'\tmp\')) {
      return true;
    }
    if (combined.contains(r'rar$')) return true;
    if (combined.contains('zip/rar archive') ||
        combined.contains('temporary archive')) {
      return true;
    }
    if (combined.contains('extract the full zip') ||
        combined.contains('posex-setup.exe')) {
      return true;
    }
    return false;
  }

  Future<void> _clearSessionMarker() async {
    final marker = _sessionMarker;
    if (marker != null && marker.existsSync()) {
      try {
        await marker.delete();
      } catch (_) {}
    }
  }

  static Future<void> attachWindowListener() async {
    if (!Platform.isWindows || !_initialized) return;
    windowManager.addListener(instance);
  }

  Future<void> _writeSessionMarker() async {
    final marker = _sessionMarker;
    if (marker == null) return;
    final stamp = DateTime.now().toIso8601String();
    await marker.writeAsString(
      'started $stamp pid=$pid exe=${Platform.resolvedExecutable}',
    );
  }

  Future<String?> _readLastFatalError() async {
    final file = _lastFatalFile;
    if (file == null || !file.existsSync()) return null;
    try {
      return (await file.readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLastFatalError(String message) async {
    lastFatalMessage = message;
    final file = _lastFatalFile;
    if (file == null) return;
    try {
      await file.writeAsString(message);
    } catch (_) {}
  }

  Future<void> clearLastFatalError() async {
    lastFatalMessage = null;
    final file = _lastFatalFile;
    if (file != null && file.existsSync()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  String _dailyLogName() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return 'posex-$y-$m-$d.log';
  }

  Future<void> _pruneOldLogs() async {
    final dir = _logDir;
    if (dir == null || !dir.existsSync()) return;

    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith('posex-') || !name.endsWith('.log')) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {}
    }
  }

  static Future<void> log(String level, String message) async {
    await instance._appendLog(level, message);
  }

  static void logFlutterError(FlutterErrorDetails details) {
    final buffer = StringBuffer(details.exceptionAsString());
    if (details.stack != null) {
      buffer.writeln();
      buffer.write(details.stack);
    }
    unawaited(instance._appendLog('FLUTTER', buffer.toString()));
  }

  static Future<void> logError(
    String context,
    Object error,
    StackTrace? stack,
  ) async {
    final buffer = StringBuffer('$context: $error');
    if (stack != null) {
      buffer.writeln();
      buffer.write(stack);
    }
    await instance._appendLog('ERROR', buffer.toString());
  }

  Future<void> _appendLog(String level, String message) async {
    final stamp = DateTime.now().toIso8601String();
    final line = '[$stamp] [$level] $message\n';

    if (kDebugMode) {
      debugPrint('[PosEx] $line'.trim());
    }

    final file = _logFile;
    if (file == null) return;
    try {
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<void> logLifecycle(String state) async {
    await log('LIFECYCLE', state);
  }

  static Future<void> logStartupFailure(String reason, {StackTrace? stack}) async {
    await logError('Startup failure', reason, stack);
    await instance._writeLastFatalError(reason);
  }

  Future<void> markCleanExit() async {
    await log('INFO', 'PosEx closed normally');
    final marker = _sessionMarker;
    if (marker != null && marker.existsSync()) {
      try {
        await marker.delete();
      } catch (_) {}
    }
  }

  Future<void> openLogFolder() async {
    final dir = _logDir;
    if (dir == null) return;

    if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
      return;
    }
    if (Platform.isAndroid) {
      await log('INFO', 'Log folder: ${dir.path}');
    }
  }

  Future<void> copyRecentLogToClipboard({int maxLines = 80}) async {
    final file = _logFile;
    if (file == null || !file.existsSync()) return;

    try {
      final lines = await file.readAsLines();
      final tail = lines.length <= maxLines
          ? lines
          : lines.sublist(lines.length - maxLines);
      await Clipboard.setData(ClipboardData(text: tail.join('\n')));
    } catch (_) {}
  }

  Future<void> showWindowsAlert(String title, String message) async {
    if (!Platform.isWindows) return;
    await log('FATAL', '$title — $message');

    final safeMessage = message
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll("'", "''");
    final safeTitle = title.replaceAll("'", "''");

    try {
      await Process.run('powershell', [
        '-NoProfile',
        '-Sta',
        '-Command',
        "Add-Type -AssemblyName PresentationFramework; "
        "[System.Windows.MessageBox]::Show('$safeMessage','$safeTitle','OK','Error') | Out-Null",
      ]);
    } catch (_) {}
  }

  @override
  void onWindowClose() {
    unawaited(markCleanExit());
  }
}
