class PosexUser {
  const PosexUser({
    required this.id,
    required this.username,
    required this.email,
    this.fullName,
    this.businessId,
    this.branchId,
  });

  final int id;
  final String username;
  final String email;
  final String? fullName;
  final int? businessId;
  final int? branchId;

  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return username;
  }

  factory PosexUser.fromJson(Map<String, dynamic> json) {
    return PosexUser(
      id: _asInt(json['id']),
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      fullName: json['full_name']?.toString(),
      businessId: _asNullableInt(json['business_id']),
      branchId: _asNullableInt(json['branch_id']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'full_name': fullName,
    'business_id': businessId,
    'branch_id': branchId,
  };

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse('$value');
  }
}
