import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/app_diagnostics.dart';

const _accent = Color(0xFFF97316);

/// Full-width error panel when PosEx fails to start or load the web app.
class StartupErrorPanel extends StatelessWidget {
  const StartupErrorPanel({
    super.key,
    required this.title,
    required this.message,
    this.previousSessionNote,
    this.onRetry,
    this.onDismiss,
  });

  final String title;
  final String message;
  final String? previousSessionNote;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  Future<void> _openLogs() async {
    await AppDiagnostics.instance.openLogFolder();
  }

  Future<void> _copyDetails() async {
    final buffer = StringBuffer();
    if (previousSessionNote != null && previousSessionNote!.isNotEmpty) {
      buffer.writeln(previousSessionNote);
      buffer.writeln();
    }
    buffer.writeln('$title: $message');
    buffer.writeln();
    buffer.writeln('Log file: ${AppDiagnostics.instance.logFilePath ?? 'unknown'}');
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    await AppDiagnostics.log('INFO', 'User copied startup error details');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A0A0A),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              if (previousSessionNote != null &&
                  previousSessionNote!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A1810),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Previous session',
                        style: TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        previousSessionNote!,
                        style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
              if (AppDiagnostics.instance.logFilePath != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Log: ${AppDiagnostics.instance.logFilePath}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
              const Spacer(),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (onRetry != null)
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                    ),
                  OutlinedButton.icon(
                    onPressed: _openLogs,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open logs folder'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _copyDetails,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy error'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                  ),
                  if (onDismiss != null)
                    TextButton(
                      onPressed: onDismiss,
                      child: const Text('Dismiss', style: TextStyle(color: Colors.white54)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
