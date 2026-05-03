import 'chart_spec.dart';

enum ChatRole { user, assistant }

/// One chat turn shown in the Insights transcript.
///
/// User messages are always concrete strings. Assistant messages start as
/// [pending]=true while waiting for the backend response, then get replaced
/// with the resolved text and (optionally) a [ChartSpec].
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    this.chart,
    this.pending = false,
    this.errored = false,
  });

  ChatMessage.user(this.text)
      : role = ChatRole.user,
        chart = null,
        pending = false,
        errored = false;

  ChatMessage.assistantPending()
      : role = ChatRole.assistant,
        text = '',
        chart = null,
        pending = true,
        errored = false;

  final ChatRole role;
  final String text;
  final ChartSpec? chart;
  final bool pending;
  final bool errored;

  ChatMessage copyWith({
    String? text,
    ChartSpec? chart,
    bool? pending,
    bool? errored,
  }) =>
      ChatMessage(
        role: role,
        text: text ?? this.text,
        chart: chart ?? this.chart,
        pending: pending ?? this.pending,
        errored: errored ?? this.errored,
      );
}
