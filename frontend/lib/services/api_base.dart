import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL for the backend. Override at build time:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8000
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Backend error envelope shape: `{error: {code, message, details?}}`.
class ApiException implements Exception {
  ApiException({required this.statusCode, required this.code, required this.message});

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode $code: $message)';
}

/// Decode a response. Throws [ApiException] for any non-2xx status.
dynamic decodeOrThrow(http.Response resp) {
  if (resp.statusCode >= 200 && resp.statusCode < 300) {
    if (resp.body.isEmpty) return null;
    return jsonDecode(resp.body);
  }
  String code = 'http_${resp.statusCode}';
  String message = resp.body;
  try {
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final detail = body['detail'];
    if (detail is Map<String, dynamic>) {
      code = detail['code'] as String? ?? code;
      message = detail['message'] as String? ?? message;
    } else if (detail is String) {
      message = detail;
    }
  } catch (_) {
    // Body wasn't JSON — fall through with the raw body as the message.
  }
  throw ApiException(statusCode: resp.statusCode, code: code, message: message);
}
