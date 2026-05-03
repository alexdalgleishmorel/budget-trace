import 'package:http/http.dart' as http;

import 'api_base.dart';

/// Per-user feature flag bag. Returned by `GET /me/features`.
class FeatureFlags {
  const FeatureFlags({
    required this.aiImport,
    required this.aiMutations,
  });

  final bool aiImport;
  final bool aiMutations;

  static const off = FeatureFlags(aiImport: false, aiMutations: false);

  factory FeatureFlags.fromJson(Map<String, dynamic> j) => FeatureFlags(
        aiImport: j['ai_import'] as bool? ?? false,
        aiMutations: j['ai_mutations'] as bool? ?? false,
      );
}

class FeaturesClient {
  FeaturesClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<FeatureFlags> get() async {
    final resp = await _client.get(Uri.parse('$apiBaseUrl/me/features'));
    final json = decodeOrThrow(resp) as Map<String, dynamic>;
    return FeatureFlags.fromJson(json);
  }

  void dispose() => _client.close();
}
