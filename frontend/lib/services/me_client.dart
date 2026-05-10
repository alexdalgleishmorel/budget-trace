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

/// One entry in [Me.availableModels] — drives the Settings dropdown.
class ModelOption {
  const ModelOption({
    required this.id,
    required this.displayName,
    required this.inputPerMtok,
    required this.outputPerMtok,
  });

  final String id;
  final String displayName;
  final double inputPerMtok;
  final double outputPerMtok;

  factory ModelOption.fromJson(Map<String, dynamic> j) => ModelOption(
        id: j['id'] as String,
        displayName: j['display_name'] as String,
        inputPerMtok: (j['input_per_mtok'] as num).toDouble(),
        outputPerMtok: (j['output_per_mtok'] as num).toDouble(),
      );
}

/// Snapshot of the current user. Returned by `GET /me` and on every
/// `PATCH /me`. Key values themselves never cross the wire — only the
/// `*_set` booleans are exposed.
class Me {
  const Me({
    required this.features,
    required this.theme,
    required this.anthropicApiKeySet,
    required this.anthropicAdminApiKeySet,
    required this.anthropicModel,
    required this.availableModels,
    required this.aiSpentUsd,
    required this.aiSpentSource,
  });

  final FeatureFlags features;
  final String theme; // 'system' | 'light' | 'dark'
  final bool anthropicApiKeySet;
  final bool anthropicAdminApiKeySet;
  final String anthropicModel;
  final List<ModelOption> availableModels;
  final double aiSpentUsd;
  final String aiSpentSource; // 'estimated' | 'authoritative'

  bool get isSpendEstimated => aiSpentSource == 'estimated';

  static const initial = Me(
    features: FeatureFlags.off,
    theme: 'system',
    anthropicApiKeySet: false,
    anthropicAdminApiKeySet: false,
    anthropicModel: 'claude-sonnet-4-6',
    availableModels: [],
    aiSpentUsd: 0.0,
    aiSpentSource: 'estimated',
  );

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        features: FeatureFlags.fromJson(j['features'] as Map<String, dynamic>),
        theme: j['theme'] as String,
        anthropicApiKeySet: j['anthropic_api_key_set'] as bool,
        anthropicAdminApiKeySet:
            j['anthropic_admin_api_key_set'] as bool? ?? false,
        anthropicModel: j['anthropic_model'] as String? ?? 'claude-sonnet-4-6',
        availableModels: (j['available_models'] as List? ?? const [])
            .map((e) => ModelOption.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        aiSpentUsd: (j['ai_spent_usd'] as num?)?.toDouble() ?? 0.0,
        aiSpentSource: j['ai_spent_source'] as String? ?? 'estimated',
      );
}

class MeClient {
  MeClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Me> get() async {
    final resp = await _client.get(Uri.parse('$apiBaseUrl/me'));
    return Me.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  /// Partial update. Each parameter is independently optional.
  ///
  /// Pass `apiKeyExplicit: true` to send the [anthropicApiKey] field — `null`
  /// then clears the stored key, a non-empty string sets it. Same pattern
  /// for [anthropicAdminApiKey] / [adminKeyExplicit] and [anthropicModel] /
  /// [modelExplicit] (where `null` resets to env/default). Empty strings
  /// are rejected by the backend — pass `null` to clear/reset.
  Future<Me> update({
    FeatureFlags? features,
    String? theme,
    String? anthropicApiKey,
    bool apiKeyExplicit = false,
    String? anthropicAdminApiKey,
    bool adminKeyExplicit = false,
    String? anthropicModel,
    bool modelExplicit = false,
  }) async {
    final body = <String, dynamic>{};
    if (features != null) body['features'] = features.toJson();
    if (theme != null) body['theme'] = theme;
    if (apiKeyExplicit) body['anthropic_api_key'] = anthropicApiKey;
    if (adminKeyExplicit) body['anthropic_admin_api_key'] = anthropicAdminApiKey;
    if (modelExplicit) body['anthropic_model'] = anthropicModel;
    final resp = await _client.patch(
      Uri.parse('$apiBaseUrl/me'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return Me.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  void dispose() => _client.close();
}
