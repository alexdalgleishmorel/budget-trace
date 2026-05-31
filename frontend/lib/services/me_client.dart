import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_base.dart';

/// Feature flags returned by `GET /me`. `ai` gates the Insights chat,
/// the AI parser, and auto-categorize. `widgets` gates the Widgets tab
/// and the `/dashboards/*` REST surface; it defaults on server-side.
class FeatureFlags {
  const FeatureFlags({required this.ai, required this.widgets});

  final bool ai;
  final bool widgets;

  static const off = FeatureFlags(ai: false, widgets: false);

  factory FeatureFlags.fromJson(Map<String, dynamic> j) => FeatureFlags(
        ai: j['ai'] as bool? ?? false,
        widgets: j['widgets'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'ai': ai, 'widgets': widgets};
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
    this.discovered = false,
    this.pricingAvailable = true,
  });

  final String id;
  final String provider;        // matches a [ProviderStatus.id] above
  final String displayName;
  final double inputPerMtok;
  final double outputPerMtok;

  /// True when pulled live via "Refresh models" rather than the curated
  /// baseline. [pricingAvailable] is false for discovered models whose rates
  /// aren't in the cost table (spend then under-counts) — surfaced as a badge.
  final bool discovered;
  final bool pricingAvailable;

  factory ModelOption.fromJson(Map<String, dynamic> j) => ModelOption(
        id: j['id'] as String,
        provider: j['provider'] as String? ?? '',
        displayName: j['display_name'] as String,
        inputPerMtok: (j['input_per_mtok'] as num).toDouble(),
        outputPerMtok: (j['output_per_mtok'] as num).toDouble(),
        discovered: j['discovered'] as bool? ?? false,
        pricingAvailable: j['pricing_available'] as bool? ?? true,
      );
}

/// Per-provider outcome of a `POST /me/models/refresh`.
class ProviderRefreshResult {
  const ProviderRefreshResult({
    required this.provider,
    required this.ok,
    required this.discoveredCount,
    required this.skipped,
    this.error,
  });

  final String provider;
  final bool ok;
  final int discoveredCount;
  final bool skipped;       // true when the provider has no key configured
  final String? error;

  factory ProviderRefreshResult.fromJson(Map<String, dynamic> j) =>
      ProviderRefreshResult(
        provider: j['provider'] as String,
        ok: j['ok'] as bool? ?? false,
        discoveredCount: j['discovered_count'] as int? ?? 0,
        skipped: j['skipped'] as bool? ?? false,
        error: j['error'] as String?,
      );
}

/// Result of `POST /me/models/refresh`: the selected provider's fetch outcome
/// plus its (now refreshed) model list.
class ModelsRefreshResult {
  const ModelsRefreshResult({
    required this.provider,
    required this.availableModels,
  });

  final ProviderRefreshResult provider;
  final List<ModelOption> availableModels;

  factory ModelsRefreshResult.fromJson(Map<String, dynamic> j) =>
      ModelsRefreshResult(
        provider: ProviderRefreshResult.fromJson(
            j['provider'] as Map<String, dynamic>),
        availableModels: (j['available_models'] as List? ?? const [])
            .map((e) => ModelOption.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
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
    required this.selectedProvider,
    required this.selectedProviderKeyAvailable,
    required this.selectedModel,
    required this.availableModels,
    required this.aiSpentUsd,
    this.lastDashboardId,
  });

  final FeatureFlags features;
  final String theme; // 'system' | 'light' | 'dark'

  /// One entry per provider known by the backend. The frontend renders a
  /// row per entry — data-driven, so a new provider on the backend appears
  /// without a frontend change.
  final List<ProviderStatus> providers;

  /// The generic provider the user picked (anthropic | openai | google). Its
  /// key is used for every AI call, and [availableModels] holds its fetched
  /// catalog.
  final String selectedProvider;

  /// Whether [selectedProvider] has a key available (stored or env). When
  /// false, AI calls fail with `ai_key_missing` — the UI warns and models
  /// can't be fetched.
  final bool selectedProviderKeyAvailable;

  /// The fetched model that drives every AI call. Empty string until the user
  /// fetches the provider's catalog and picks one.
  final String selectedModel;

  /// The selected provider's fetched models (the model dropdown's contents).
  final List<ModelOption> availableModels;

  /// Locally-estimated cumulative AI spend in USD. Computed from token
  /// counts × the selected model's published per-MTok price at insert time.
  /// Not the same as your provider bill.
  final double aiSpentUsd;

  /// The dashboard the user was last viewing, persisted server-side so the
  /// Widgets tab returns to the same spot on reopen. Null when the user
  /// hasn't viewed any dashboard yet (or the last one was deleted).
  final int? lastDashboardId;

  static const initial = Me(
    features: FeatureFlags.off,
    theme: 'system',
    providers: [],
    selectedProvider: 'anthropic',
    selectedProviderKeyAvailable: false,
    selectedModel: '',
    availableModels: [],
    aiSpentUsd: 0.0,
    lastDashboardId: null,
  );

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        features: FeatureFlags.fromJson(j['features'] as Map<String, dynamic>),
        theme: j['theme'] as String,
        providers: (j['providers'] as List? ?? const [])
            .map((e) => ProviderStatus.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        selectedProvider: j['selected_provider'] as String? ?? 'anthropic',
        selectedProviderKeyAvailable:
            j['selected_provider_key_available'] as bool? ?? false,
        selectedModel: j['selected_model'] as String? ?? '',
        availableModels: (j['available_models'] as List? ?? const [])
            .map((e) => ModelOption.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        aiSpentUsd: (j['ai_spent_usd'] as num?)?.toDouble() ?? 0.0,
        lastDashboardId: j['last_dashboard_id'] as int?,
      );

  Me copyWith({int? lastDashboardId}) => Me(
        features: features,
        theme: theme,
        providers: providers,
        selectedProvider: selectedProvider,
        selectedProviderKeyAvailable: selectedProviderKeyAvailable,
        selectedModel: selectedModel,
        availableModels: availableModels,
        aiSpentUsd: aiSpentUsd,
        lastDashboardId: lastDashboardId ?? this.lastDashboardId,
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
  /// [selectedProvider] switches the active provider (the backend clears the
  /// selected model when it changes). Pass `selectedModelExplicit: true` to
  /// send [selectedModel] — `null` then clears it. Empty strings are rejected
  /// by the backend; pass `null` instead.
  ///
  /// [providerKeys] is a partial map. Only the providers you include get
  /// changed: `'<provider>': '<key>'` sets, `'<provider>': null` clears.
  Future<Me> update({
    FeatureFlags? features,
    String? theme,
    String? selectedProvider,
    String? selectedModel,
    bool selectedModelExplicit = false,
    Map<String, String?>? providerKeys,
  }) async {
    final body = <String, dynamic>{};
    if (features != null) body['features'] = features.toJson();
    if (theme != null) body['theme'] = theme;
    if (selectedProvider != null) body['selected_provider'] = selectedProvider;
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

  /// Pull the latest models from every configured provider. The backend lists
  /// each provider's live catalog (using the stored/env key), prices what it
  /// can, and persists newly-found models. Per-provider failures are reported
  /// in the result rather than thrown.
  Future<ModelsRefreshResult> refreshModels() async {
    final resp = await _client.post(Uri.parse('$apiBaseUrl/me/models/refresh'));
    return ModelsRefreshResult.fromJson(
        decodeOrThrow(resp) as Map<String, dynamic>);
  }

  void dispose() => _client.close();
}
