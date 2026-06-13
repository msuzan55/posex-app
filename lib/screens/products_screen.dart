import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/products_service.dart';
import '../widgets/product_card.dart';
import 'login_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _productsService = ProductsService();

  final List<PosexProduct> _products = [];
  Timer? _searchDebounce;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _total = 0;
  String? _error;
  String _searchQuery = '';

  static const _pageSize = 100;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadProducts(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadProducts(reset: false);
    }
  }

  Future<void> _loadProducts({required bool reset}) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    final user = auth.user;
    if (token == null || user == null) return;

    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _products.clear();
        _hasMore = true;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final result = await _productsService.fetchProducts(
        token: token,
        user: user,
        search: _searchQuery,
        skip: reset ? 0 : _products.length,
        limit: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _products
            ..clear()
            ..addAll(result.items);
        } else {
          _products.addAll(result.items);
        }
        _total = result.total;
        _hasMore = result.hasMore;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Failed to load products.');
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchQuery = value.trim();
      _loadProducts(reset: true);
    });
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Products'),
            if (user != null)
              Text(
                user.displayName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _loadProducts(reset: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search name, item code, barcode…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {});
                _onSearchChanged(value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  _loading ? 'Loading…' : '$_total products',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_products.isNotEmpty)
                  Text(
                    'Showing ${_products.length}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && _products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _loadProducts(reset: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📦', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'No products found',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? 'Your catalog will appear here after login.'
                  : 'Try a different search term.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadProducts(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _products.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _products.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return ProductCard(
            product: _products[index],
            baseUrl: ApiConfig.resolveBaseUrl(),
          );
        },
      ),
    );
  }
}
