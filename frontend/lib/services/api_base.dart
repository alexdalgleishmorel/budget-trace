import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL for the backend. Override at build time:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8000
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Whether this build is the static, backend-less demo. Set at build time:
///   flutter build web --dart-define=DEMO_MODE=true
/// When false (the default), the app behaves normally and talks to a real
/// backend at [apiBaseUrl].
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

/// Optional override for the [http.Client] every service client uses. The demo
/// build sets this from its bootstrap to swap in an in-memory mock client; on a
/// normal build it stays null and clients use a real [http.Client]. Kept
/// generic on purpose so this file never imports demo-only code.
http.Client Function()? httpClientOverride;

/// Build the [http.Client] a service client should use when one isn't injected.
/// Returns the demo override when present, otherwise a real client.
http.Client makeHttpClient() => httpClientOverride?.call() ?? http.Client();

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
