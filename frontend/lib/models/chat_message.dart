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
    this.widget,
    this.pending = false,
    this.errored = false,
  });

  ChatMessage.user(this.text)
      : role = ChatRole.user,
        widget = null,
        pending = false,
        errored = false;

  ChatMessage.assistantPending()
      : role = ChatRole.assistant,
        text = '',
        widget = null,
        pending = true,
        errored = false;

  final ChatRole role;
  final String text;
  final WidgetPayload? widget;
  final bool pending;
  final bool errored;

  ChatMessage copyWith({
    String? text,
    WidgetPayload? widget,
    bool? pending,
    bool? errored,
  }) =>
      ChatMessage(
        role: role,
        text: text ?? this.text,
        widget: widget ?? this.widget,
        pending: pending ?? this.pending,
        errored: errored ?? this.errored,
      );
}
