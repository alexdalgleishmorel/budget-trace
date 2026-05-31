/// Entry point that swaps the app's HTTP layer for the in-memory demo backend.
/// Called once from `main()`. A no-op unless this is a `DEMO_MODE` build, so it
/// is safe to invoke unconditionally.
library;

import 'package:http/http.dart' as http;

import '../api_base.dart';
import 'demo_backend.dart';
import 'demo_http_client.dart';

/// Install the demo backend as the shared [http.Client] factory. After this,
/// every service client built without an explicit client talks to the
/// in-memory [DemoBackend] instead of the network.
void installDemoBackend() {
  if (!kDemoMode) return;
  final client = DemoHttpClient(DemoBackend.instance);
  httpClientOverride = () => client;
}
