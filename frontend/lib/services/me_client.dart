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

/// One row in the per-provider key section of the Account screen.
class ProviderStatus {
  const ProviderStatus({
    required this.id,
    required this.displayName,
    required this.envVar,
    required this.apiKeySet,
    required this.envFallback,
  });

  final String id;          // 'anthropic' | 'openai' | 'google' | ...
  final String displayName; // 'Anthropic'
  final String envVar;      // 'ANTHROPIC_API_KEY'
  final bool apiKeySet;     // a key is stored on the user row
  final bool envFallback;   // the provider's env var is present

  factory ProviderStatus.fromJson(Map<String, dynamic> j) => ProviderStatus(
        id: j['id'] as String,
        displayName: j['display_name'] as String,
        envVar: j['env_var'] as String,
        apiKeySet: j['api_key_set'] as bool? ?? false,
        envFallback: j['env_fallback'] as bool? ?? false,
      );
}

/// One entry in [Me.availableModels] — drives the Settings dropdown.
class ModelOption {
  const ModelOption({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.inputPerMtok,
    required this.outputPerMtok,
  });

  final String id;
  final String provider;        // matches a [ProviderStatus.id] above
  final String displayName;
  final double inputPerMtok;
  final double outputPerMtok;

  factory ModelOption.fromJson(Map<String, dynamic> j) => ModelOption(
        id: j['id'] as String,
        provider: j['provider'] as String? ?? '',
        displayName: j['display_name'] as String,
        inputPerMtok: (j['input_per_mtok'] as num).toDouble(),
        outputPerMtok: (j['output_per_mtok'] as num).toDouble(),
      );
}

/// Snapshot of the current user. Returned by `GET /me` and on every
/// `PATCH /me`. Key values themselves never cross the wire — only the
/// `api_key_set` booleans per provider are exposed.
class Me {
  const Me({
    required this.features,
    required this.theme,
    required this.providers,
    required this.selectedModel,
    required this.selectedModelProvider,
    required this.selectedModelKeyAvailable,
    required this.availableModels,
    required this.aiSpentUsd,
  });

  final FeatureFlags features;
  final String theme; // 'system' | 'light' | 'dark'

  /// One entry per provider known by the backend. The frontend renders a
  /// row per entry — data-driven, so a new provider on the backend appears
  /// without a frontend change.
  final List<ProviderStatus> providers;

  /// The model that drives every AI call (chat, parser, auto-categorizer).
  final String selectedModel;

  /// Provider id of [selectedModel]. Derived server-side from the model
  /// registry.
  final String selectedModelProvider;

  /// Whether [selectedModelProvider] has a key available (stored or env).
  /// When false, AI calls will fail with `ai_key_missing` — the UI uses
  /// this to surface a warning under the model picker.
  final bool selectedModelKeyAvailable;

  final List<ModelOption> availableModels;

  /// Locally-estimated cumulative AI spend in USD. Computed from token
  /// counts × the selected model's published per-MTok price at insert time.
  /// Not the same as your provider bill.
  final double aiSpentUsd;

  static const initial = Me(
    features: FeatureFlags.off,
    theme: 'system',
    providers: [],
    selectedModel: 'claude-sonnet-4-6',
    selectedModelProvider: 'anthropic',
    selectedModelKeyAvailable: false,
    availableModels: [],
    aiSpentUsd: 0.0,
  );

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        features: FeatureFlags.fromJson(j['features'] as Map<String, dynamic>),
        theme: j['theme'] as String,
        providers: (j['providers'] as List? ?? const [])
            .map((e) => ProviderStatus.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        selectedModel: j['selected_model'] as String? ?? 'claude-sonnet-4-6',
        selectedModelProvider:
            j['selected_model_provider'] as String? ?? 'anthropic',
        selectedModelKeyAvailable:
            j['selected_model_key_available'] as bool? ?? false,
        availableModels: (j['available_models'] as List? ?? const [])
            .map((e) => ModelOption.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        aiSpentUsd: (j['ai_spent_usd'] as num?)?.toDouble() ?? 0.0,
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
  /// Pass `selectedModelExplicit: true` to send [selectedModel] — `null`
  /// then clears the override (the backend falls back to env / default).
  /// Empty strings are rejected by the backend; pass `null` instead.
  ///
  /// [providerKeys] is a partial map. Only the providers you include get
  /// changed: `'<provider>': '<key>'` sets, `'<provider>': null` clears.
  Future<Me> update({
    FeatureFlags? features,
    String? theme,
    String? selectedModel,
    bool selectedModelExplicit = false,
    Map<String, String?>? providerKeys,
  }) async {
    final body = <String, dynamic>{};
    if (features != null) body['features'] = features.toJson();
    if (theme != null) body['theme'] = theme;
    if (selectedModelExplicit) body['selected_model'] = selectedModel;
    if (providerKeys != null && providerKeys.isNotEmpty) {
      body['provider_keys'] = providerKeys;
    }
    final resp = await _client.patch(
      Uri.parse('$apiBaseUrl/me'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return Me.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  void dispose() => _client.close();
}
