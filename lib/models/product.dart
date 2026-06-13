class PosexProduct {
  const PosexProduct({
    required this.id,
    required this.itemCode,
    required this.productName,
    this.variantName,
    this.barcode,
    this.stock = 0,
    this.sellingPrice = 0,
    this.averageCost = 0,
    this.minStockLevel = 0,
    this.categoryName,
    this.supplierName,
    this.unit = 'PCS',
    this.isActive = true,
    this.productImages = const [],
  });

  final int id;
  final String itemCode;
  final String productName;
  final String? variantName;
  final String? barcode;
  final double stock;
  final double sellingPrice;
  final double averageCost;
  final double minStockLevel;
  final String? categoryName;
  final String? supplierName;
  final String unit;
  final bool isActive;
  final List<String> productImages;

  String get displayName {
    final variant = variantName?.trim();
    if (variant != null && variant.isNotEmpty) {
      return '$productName · $variant';
    }
    return productName;
  }

  bool get isLowStock {
    final min = minStockLevel > 0 ? minStockLevel : 10;
    return stock <= min;
  }

  factory PosexProduct.fromJson(Map<String, dynamic> json) {
    final imagesRaw = json['product_images'];
    final images = <String>[];
    if (imagesRaw is List) {
      for (final item in imagesRaw) {
        final value = item?.toString().trim();
        if (value != null && value.isNotEmpty) images.add(value);
      }
    }

    return PosexProduct(
      id: _asInt(json['id']),
      itemCode: json['item_code']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? 'Unnamed product',
      variantName: json['variant_name']?.toString(),
      barcode: json['barcode']?.toString(),
      stock: _asDouble(json['stock']),
      sellingPrice: _asDouble(json['selling_price']),
      averageCost: _asDouble(json['average_cost']),
      minStockLevel: _asDouble(json['min_stock_level']),
      categoryName: json['category_name']?.toString(),
      supplierName: json['supplier_name']?.toString(),
      unit: json['unit']?.toString() ?? 'PCS',
      isActive: json['is_active'] != false,
      productImages: images,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}

class ProductListResult {
  const ProductListResult({
    required this.items,
    required this.total,
    required this.skip,
    required this.limit,
  });

  final List<PosexProduct> items;
  final int total;
  final int skip;
  final int limit;

  bool get hasMore => skip + items.length < total;
}
