import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/windows_shell_service.dart';
import '../update/update_service.dart';

const _accent = Color(0xFFF97316);

/// Custom Windows title bar with ⋮ menu before min / max / close.
class WindowsTitleBar extends StatefulWidget {
  const WindowsTitleBar({
    super.key,
    required this.updateService,
    this.onCheckForUpdate,
    this.onInstallUpdate,
    this.updateReady = false,
  });

  final UpdateService updateService;
  final Future<void> Function()? onCheckForUpdate;
  final Future<void> Function()? onInstallUpdate;
  final bool updateReady;

  @override
  State<WindowsTitleBar> createState() => _WindowsTitleBarState();
}

class _WindowsTitleBarState extends State<WindowsTitleBar> {
  bool _startOnStartup = true;

  @override
  void initState() {
    super.initState();
    _loadStartup();
  }

  Future<void> _loadStartup() async {
    final enabled = await WindowsShellService.isStartOnStartupEnabled();
    if (mounted) setState(() => _startOnStartup = enabled);
  }

  Future<void> _showAppInfo() async {
    final info = await WindowsShellService.getAppInfo();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text('App information', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoLine('App', info.appName),
            _infoLine('Version', '${info.version} (${info.buildNumber})'),
            _infoLine('Install folder', info.installDir),
            const SizedBox(height: 8),
            const Text(
              'PosEx loads https://posex.lk/test/ with a local print server on port 9753.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text('Clear all offline data?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This removes saved login, IndexedDB/offline sync data, printer settings, and cached updates. The app will restart.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear & restart', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await WindowsShellService.clearAllOfflineDataAndRestart();
  }

  Future<void> _openMenu() async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.sizeOf(context).width - 280,
        36,
        16,
        0,
      ),
      color: const Color(0xFF151515),
      items: [
        const PopupMenuItem(value: 'info', child: Text('App information')),
        PopupMenuItem(
          value: 'update',
          child: Text(widget.updateReady ? 'Install update now' : 'Check for updates'),
        ),
        const PopupMenuItem(
          value: 'clear',
          child: Text('Clear all offline data', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    );

    switch (action) {
      case 'info':
        await _showAppInfo();
      case 'update':
        if (widget.updateReady) {
          await widget.onInstallUpdate?.call();
        } else {
          await widget.onCheckForUpdate?.call();
        }
      case 'clear':
        await _confirmClearData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    return DragToMoveArea(
      child: Container(
        height: 36,
        color: const Color(0xFF0A0A0A),
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            const Text(
              'PosEx',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            if (widget.updateReady) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Update ready',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
            const Spacer(),
            Switch(
              value: _startOnStartup,
              activeTrackColor: _accent.withValues(alpha: 0.45),
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? _accent
                    : Colors.white54,
              ),
              onChanged: (v) async {
                setState(() => _startOnStartup = v);
                await WindowsShellService.setStartOnStartup(v);
              },
            ),
            const Text('Start on startup', style: TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Menu',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: _openMenu,
            ),
            _CaptionButton(
              icon: Icons.remove,
              onPressed: () => windowManager.minimize(),
            ),
            _CaptionButton(
              icon: Icons.crop_square,
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _CaptionButton(
              icon: Icons.close,
              hoverColor: Colors.red,
              onPressed: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover ? (widget.hoverColor ?? Colors.white24) : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 36,
          color: bg,
          alignment: Alignment.center,
          child: Icon(widget.icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}
