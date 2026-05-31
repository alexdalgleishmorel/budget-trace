/// A [http.Client] that intercepts every service-client request in the demo
/// build and answers it from the in-memory [DemoBackend], so the Flutter web
/// app runs with no backend at all. Wired in by `demo_bootstrap.dart`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'demo_backend.dart';

class DemoHttpClient extends http.BaseClient {
  DemoHttpClient(this._backend);

  final DemoBackend _backend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _backend.ensureLoaded();

    final method = request.method.toUpperCase();
    final segments = request.url.pathSegments;
    final query = request.url.queryParameters;

    // Read the body up front: JSON for normal requests, file bytes for the
    // multipart CSV import.
    Map<String, dynamic> body = const {};
    List<int>? uploadBytes;
    if (request is http.Request && request.body.isNotEmpty) {
      final decoded = jsonDecode(request.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } else if (request is http.MultipartRequest && request.files.isNotEmpty) {
      uploadBytes = await request.files.first.finalize().toBytes();
    }

    int status = 200;
    Object? payload;
    try {
      payload = _route(method, segments, query, body, uploadBytes);
    } on DemoApiException catch (e) {
      status = e.status;
      payload = {
        'detail': {'code': e.code, 'message': e.message},
      };
    } catch (e) {
      status = 500;
      payload = {
        'detail': {'code': 'demo_error', 'message': e.toString()},
      };
    }

    final bytes = payload == null ? <int>[] : utf8.encode(jsonEncode(payload));
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
      reasonPhrase: status == 200 ? 'OK' : 'Demo',
    );
  }

  Object? _route(
    String method,
    List<String> seg,
    Map<String, String> query,
    Map<String, dynamic> body,
    List<int>? uploadBytes,
  ) {
    final b = _backend;
    bool is_(List<String> pattern) {
      if (pattern.length != seg.length) return false;
      for (var i = 0; i < pattern.length; i++) {
        if (pattern[i] != '*' && pattern[i] != seg[i]) return false;
      }
      return true;
    }

    int id(int i) => int.parse(seg[i]);

    // ── /me ──
    if (is_(['me']) && method == 'GET') return b.me();
    if (is_(['me']) && method == 'PATCH') return b.patchMe(body);
    if (is_(['me', 'models', 'refresh']) && method == 'POST') return b.refreshModels();

    // ── /widget-metrics ──
    if (is_(['widget-metrics']) && method == 'GET') return b.widgetMetrics();

    // ── /categories ──
    if (is_(['categories']) && method == 'GET') return b.listCategories();
    if (is_(['categories']) && method == 'POST') return b.createCategory(body);
    if (is_(['categories', 'seed_defaults']) && method == 'POST') return b.seedDefaults();
    if (is_(['categories', '*']) && method == 'PATCH') return b.updateCategory(id(1), body);
    if (is_(['categories', '*']) && method == 'DELETE') return b.deleteCategory(id(1));

    // ── /transactions ──
    if (is_(['transactions', 'latest_date']) && method == 'GET') return b.latestDate();
    if (is_(['transactions']) && method == 'GET') return b.listTransactions(query);
    if (is_(['transactions', 'bulk_rename']) && method == 'POST') return b.bulkRename(body);
    if (is_(['transactions', 'import']) && method == 'POST') {
      return b.importCsv(uploadBytes ?? const []);
    }
    if (is_(['transactions', '*']) && method == 'PATCH') return b.updateTransaction(id(1), body);
    if (is_(['transactions', '*']) && method == 'DELETE') {
      b.deleteTransaction(id(1));
      return null;
    }

    // ── /dashboards ──
    if (is_(['dashboards']) && method == 'GET') return b.listDashboards();
    if (is_(['dashboards']) && method == 'POST') return b.createDashboard(body);
    if (is_(['dashboards', '*']) && method == 'GET') return b.getDashboard(id(1));
    if (is_(['dashboards', '*']) && method == 'PATCH') return b.updateDashboard(id(1), body);
    if (is_(['dashboards', '*']) && method == 'DELETE') {
      b.deleteDashboard(id(1));
      return null;
    }
    if (is_(['dashboards', '*', 'layout']) && method == 'PUT') {
      b.putLayout(id(1), body);
      return null;
    }
    if (is_(['dashboards', '*', 'widgets']) && method == 'POST') {
      return b.createWidget(id(1), body);
    }
    if (is_(['dashboards', '*', 'widgets', '*', 'data']) && method == 'GET') {
      return b.getWidgetData(id(1), id(3));
    }
    if (is_(['dashboards', '*', 'widgets', '*']) && method == 'PATCH') {
      return b.updateWidget(id(1), id(3), body);
    }
    if (is_(['dashboards', '*', 'widgets', '*']) && method == 'DELETE') {
      b.deleteWidget(id(1), id(3));
      return null;
    }

    // ── /chat ──
    if (is_(['chat', 'sessions']) && method == 'GET') return b.listSessions();
    if (is_(['chat', 'sessions']) && method == 'POST') return b.createSession();
    if (is_(['chat', 'help']) && method == 'GET') return b.chatHelp();
    if (is_(['chat', 'sessions', '*', 'messages']) && method == 'GET') {
      return b.getMessages(id(2));
    }
    if (is_(['chat', 'sessions', '*', 'messages']) && method == 'POST') {
      return b.appendMessage(id(2), body['text'] as String? ?? '');
    }
    if (is_(['chat', 'sessions', '*']) && method == 'DELETE') {
      b.deleteSession(id(2));
      return null;
    }
    if (is_(['chat', 'messages', '*', 'save-to-dashboard']) && method == 'POST') {
      return b.saveChatWidget(id(2), body['dashboard_id'] as int);
    }

    throw DemoApiException(404, 'not_found', 'no demo route for $method /${seg.join('/')}');
  }
}
