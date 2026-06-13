import 'package:flutter/material.dart';

import '../config/api_config.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PosEx'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Flutter shell is ready. Next steps: login, offline sync, barcode scan, and POS checkout.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'API: ${ApiConfig.productionBaseUrl}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ModuleTile(
            icon: Icons.shopping_cart_checkout,
            title: 'Sell',
            subtitle: 'Barcode checkout, payments, hold/recall',
            color: const Color(0xFFF97316),
            onTap: () => _showComingSoon(context, 'POS checkout'),
          ),
          _ModuleTile(
            icon: Icons.qr_code_scanner,
            title: 'Scan',
            subtitle: 'Stock lookup by barcode',
            color: const Color(0xFF3B82F6),
            onTap: () => _showComingSoon(context, 'Barcode scanner'),
          ),
          _ModuleTile(
            icon: Icons.receipt_long,
            title: 'Bills',
            subtitle: 'Bill history and refunds',
            color: const Color(0xFF8B5CF6),
            onTap: () => _showComingSoon(context, 'Bill history'),
          ),
          _ModuleTile(
            icon: Icons.sync,
            title: 'Sync',
            subtitle: 'Offline queue and WebSocket status',
            color: const Color(0xFF0D9488),
            onTap: () => _showComingSoon(context, 'Sync engine'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showComingSoon(context, 'Quick sale'),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('New sale'),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — coming soon')),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
