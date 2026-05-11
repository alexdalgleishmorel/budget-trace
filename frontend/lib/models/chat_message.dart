import 'dashboard.dart';

enum ChatRole { user, assistant }

/// One chat turn shown in the Insights transcript.
///
/// User messages are always concrete strings. Assistant messages start as
/// [pending]=true while waiting for the backend response, then get replaced
/// with the resolved text and (optionally) a [WidgetPayload] — the AI
/// picks the most intuitive widget type and the frontend renders it via
/// the same `WidgetCard` used on dashboards.
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    this.id,
    this.widget,
    this.pending = false,
    this.errored = false,
  });

  ChatMessage.user(this.text)
      : role = ChatRole.user,
        id = null,
        widget = null,
        pending = false,
        errored = false;

  ChatMessage.assistantPending()
      : role = ChatRole.assistant,
        text = '',
        id = null,
        widget = null,
        pending = true,
        errored = false;

  /// Server-assigned message id. Null for optimistic local turns that
  /// haven't been acknowledged yet, and for help-text / error stand-ins
  /// the client invents. The "Save to dashboard" flow needs this to call
  /// `POST /chat/messages/{id}/save-to-dashboard`.
  final int? id;
  final ChatRole role;
  final String text;
  final WidgetPayload? widget;
  final bool pending;
  final bool errored;

  ChatMessage copyWith({
    int? id,
    String? text,
    WidgetPayload? widget,
    bool? pending,
    bool? errored,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        role: role,
        text: text ?? this.text,
        widget: widget ?? this.widget,
        pending: pending ?? this.pending,
        errored: errored ?? this.errored,
      );
}
