import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/dashboard.dart';

/// Talks to the backend's `/chat/sessions` REST surface.
///
/// The backend persists every turn, so the frontend only ever needs to:
///   - list sessions for the history view,
///   - create a new (empty) session before the first user turn,
///   - load all messages for a session when the user taps it,
///   - append a user turn and receive the assistant's reply in one round-trip.
class ChatClient {
  ChatClient({String? baseUrl})
      : _baseUrl = baseUrl ?? _defaultBaseUrl,
        _client = http.Client();

  /// Override at build time:
  /// `flutter run --dart-define=API_BASE_URL=http://localhost:8000`
  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  final String _baseUrl;
  final http.Client _client;

  Future<List<ChatSession>> listSessions() async {
    final resp = await _client.get(Uri.parse('$_baseUrl/chat/sessions'));
    _check(resp);
    final list = jsonDecode(resp.body) as List;
    return list
        .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChatSession> createSession() async {
    final resp = await _client.post(Uri.parse('$_baseUrl/chat/sessions'));
    _check(resp);
    return ChatSession.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<List<ChatMessage>> getMessages(int sessionId) async {
    final resp = await _client.get(
      Uri.parse('$_baseUrl/chat/sessions/$sessionId/messages'),
    );
    _check(resp);
    final list = jsonDecode(resp.body) as List;
    return list
        .map((e) => _messageFromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Append [text] as a user turn, run the AI, persist + return the assistant
  /// reply. The user message reflected back is also returned (with its
  /// server-assigned id and sequence) so the UI can replace its optimistic copy.
  /// `costUsd` is the dollar cost of the AI call(s) for this turn alone;
  /// `sessionSpentUsd` is the running cumulative for the whole session.
  Future<
      ({
        ChatMessage userMessage,
        ChatMessage assistantMessage,
        double costUsd,
        double sessionSpentUsd,
      })> appendMessage(int sessionId, String text) async {
    final resp = await _client.post(
      Uri.parse('$_baseUrl/chat/sessions/$sessionId/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    _check(resp);
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return (
      userMessage: _messageFromJson(json['user_message'] as Map<String, dynamic>),
      assistantMessage:
          _messageFromJson(json['assistant_message'] as Map<String, dynamic>),
      costUsd: (json['cost_usd'] as num?)?.toDouble() ?? 0.0,
      sessionSpentUsd: (json['session_spent_usd'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Static help text describing the AI's capabilities. The backend
  /// introspects its own tool registry, so this is always up-to-date with
  /// whatever capabilities the assistant currently has.
  Future<String> getHelp() async {
    final resp = await _client.get(Uri.parse('$_baseUrl/chat/help'));
    _check(resp);
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['text'] as String? ?? '';
  }

  Future<void> deleteSession(int sessionId) async {
    final resp = await _client.delete(
      Uri.parse('$_baseUrl/chat/sessions/$sessionId'),
    );
    _check(resp);
  }

  void dispose() => _client.close();

  void _check(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Backend ${resp.statusCode}: ${resp.body}');
    }
  }

  ChatMessage _messageFromJson(Map<String, dynamic> json) {
    final role = (json['role'] as String) == 'user'
        ? ChatRole.user
        : ChatRole.assistant;
    final widget = (json['widget'] as Map<String, dynamic>?) != null
        ? WidgetPayload.fromJson(json['widget'] as Map<String, dynamic>)
        : null;
    return ChatMessage(
      role: role,
      text: json['text'] as String? ?? '',
      widget: widget,
      errored: json['errored'] as bool? ?? false,
    );
  }
}
