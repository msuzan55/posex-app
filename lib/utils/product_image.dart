import '../config/api_config.dart';

String? resolveProductImageUrl(String baseUrl, List<String> productImages) {
  if (productImages.isEmpty) return null;
  final raw = productImages.first.trim();
  if (raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) return '$baseUrl$raw';
  return '${ApiConfig.productUploadPrefix(baseUrl)}$raw';
}
