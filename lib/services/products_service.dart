import '../config/api_config.dart';
import '../models/product.dart';
import '../models/user.dart';
import 'api_client.dart';

class ProductsService {
  ProductsService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<ProductListResult> fetchProducts({
    required String token,
    required PosexUser user,
    String search = '',
    int skip = 0,
    int limit = 100,
  }) async {
    final businessId = user.businessId;
    if (businessId == null) {
      throw ApiException('Your account has no business assigned.');
    }

    final query = <String, String>{
      'business_id': '$businessId',
      'skip': '$skip',
      'limit': '$limit',
      'is_active': 'true',
    };

    final branchId = user.branchId;
    if (branchId != null) {
      query['branch_id'] = '$branchId';
    }

    final trimmed = search.trim();
    if (trimmed.isNotEmpty) {
      query['search'] = trimmed;
    }

    final data = await _api.getJson(
      ApiConfig.productsList,
      query: query,
      token: token,
    );

    final rows = data['data'];
    final items = <PosexProduct>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is Map<String, dynamic>) {
          items.add(PosexProduct.fromJson(row));
        }
      }
    }

    return ProductListResult(
      items: items,
      total: _asInt(data['total']),
      skip: _asInt(data['skip']),
      limit: _asInt(data['limit']),
    );
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}
