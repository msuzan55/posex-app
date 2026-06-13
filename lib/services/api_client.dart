import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? ApiConfig.resolveBaseUrl();

  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> postForm(
    String path,
    Map<String, String> fields, {
    String? token,
  }) async {
    final response = await http.post(
      _uri(path),
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: fields,
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    required String token,
  }) async {
    final response = await http.get(
      _uri(path, query),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _decodeMap(response);
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final body = response.body.isEmpty ? '{}' : response.body;
    final decoded = jsonDecode(body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) return decoded;
      throw ApiException('Unexpected response from server.');
    }

    throw ApiException(_extractError(decoded), statusCode: response.statusCode);
  }

  String _extractError(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      final detail = decoded['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          return first['msg'].toString();
        }
      }
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return 'Request failed';
  }
}
