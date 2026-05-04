import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_base.dart';

/// The single AI master flag. Replaces the old `ai_import` + `ai_mutations`
/// pair — when `ai` is on, the user gets PDF/AI parsing, the Insights chat,
/// and auto-categorization on import.
class FeatureFlags {
  const FeatureFlags({required this.ai});

  final bool ai;

  static const off = FeatureFlags(ai: false);

  factory FeatureFlags.fromJson(Map<String, dynamic> j) =>
      FeatureFlags(ai: j['ai'] as bool? ?? false);

  Map<String, dynamic> toJson() => {'ai': ai};
}

/// Snapshot of the current user. Returned by `GET /me` and on every
/// `PATCH /me`. The Anthropic API key value itself never crosses the wire —
/// only [anthropicApiKeySet] is exposed.
class Me {
  const Me({
    required this.features,
    required this.theme,
    required this.anthropicApiKeySet,
  });

  final FeatureFlags features;
  final String theme; // 'system' | 'light' | 'dark'
  final bool anthropicApiKeySet;

  static const initial = Me(
    features: FeatureFlags.off,
    theme: 'system',
    anthropicApiKeySet: false,
  );

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        features: FeatureFlags.fromJson(j['features'] as Map<String, dynamic>),
        theme: j['theme'] as String,
        anthropicApiKeySet: j['anthropic_api_key_set'] as bool,
      );
}

class MeClient {
  MeClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Me> get() async {
    final resp = await _client.get(Uri.parse('$apiBaseUrl/me'));
    return Me.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  /// Partial update. Each parameter is independently optional. Pass
  /// `apiKeyExplicit: true` to send the [anthropicApiKey] field — `null`
  /// then clears the stored key, a non-empty string sets it. Empty string
  /// is rejected by the backend.
  Future<Me> update({
    FeatureFlags? features,
    String? theme,
    String? anthropicApiKey,
    bool apiKeyExplicit = false,
  }) async {
    final body = <String, dynamic>{};
    if (features != null) body['features'] = features.toJson();
    if (theme != null) body['theme'] = theme;
    if (apiKeyExplicit) body['anthropic_api_key'] = anthropicApiKey;
    final resp = await _client.patch(
      Uri.parse('$apiBaseUrl/me'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return Me.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  void dispose() => _client.close();
}
