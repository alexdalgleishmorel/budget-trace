import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/chat_message.dart';
import '../models/dashboard.dart';
import '../services/chat_client.dart';
import '../services/dashboards_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_promo.dart';
import '../widgets/ai_spend_chip.dart';
import '../widgets/cat_icon.dart';
import '../widgets/dash_widgets/widget_card.dart';
import '../widgets/mobile_settings_icon.dart';
import 'dashboard_screen.dart';
import 'insights_history_view.dart';

/// Insights tab — chat with the AI about your spending.
///
/// One [InsightsScreen] state holds:
///   - the active session id (null until the first message is sent)
///   - the in-memory transcript for that session
///
/// Sessions are persisted server-side (`/chat/sessions`). The history view is
/// always loaded fresh from the API; tapping a row reloads its messages here.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    required this.aiEnabled,
    required this.apiKeySet,
    required this.onOpenAccount,
    required this.onSpendChanged,
  });

  /// Whether the master `ai` feature flag is on. When false, the tab is
  /// still reachable but renders an [AiPromo] empty state instead of the
  /// chat — the user enables AI in Account to unlock it.
  final bool aiEnabled;

  /// Whether the selected model's provider has an API key available
  /// (stored on the user or present in env). When false (but AI is on),
  /// the chat input is disabled and the empty-state guides the user to
  /// Account instead of letting them hit a 400 on submit.
  final bool apiKeySet;

  /// Push the AccountScreen — used by the no-key empty state's CTA.
  final Future<void> Function() onOpenAccount;

  /// Notify the shell that AI spend may have changed so it can re-fetch
  /// `/me` and refresh the global spend chip in the nav.
  final VoidCallback onSpendChanged;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  late final ChatClient _client;
  late final DashboardsClient _dashboardsClient;

  int? _activeSessionId;
  bool _busy = false;
  double _sessionSpentUsd = 0.0;

  @override
  void initState() {
    super.initState();
    _client = ChatClient();
    _dashboardsClient = DashboardsClient();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _client.dispose();
    _dashboardsClient.dispose();
    super.dispose();
  }

  Future<void> _saveWidget(ChatMessage message) async {
    final payload = message.widget;
    final messageId = message.id;
    if (payload == null || messageId == null) return;

    final dashboardId = await _showSaveToDashboardSheet(payload);
    if (dashboardId == null) return;

    try {
      await _dashboardsClient.saveChatWidgetToDashboard(
        messageId: messageId,
        dashboardId: dashboardId,
      );
      if (!mounted) return;
      final bt = context.bt;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Explicit duration — the default 4s sometimes doesn't fire
          // when the snackbar contains a custom Row layout. Keep it
          // bounded so the bar always clears itself.
          duration: const Duration(seconds: 6),
          // Manual dismiss icon as a safety net — the auto-timer can be
          // finicky with custom `content`, and the user shouldn't be
          // stuck waiting if it stalls.
          showCloseIcon: true,
          // SnackBarAction can only colour its label text; to get a
          // filled-green CTA matching the AiPromo button we drop in a
          // custom Row instead.
          content: Row(
            children: [
              const Expanded(
                child: Text('Added to dashboard'),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DashboardScreen(
                      client: _dashboardsClient,
                      dashboardId: dashboardId,
                    ),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: bt.pos,
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Text(
                    'View dashboard',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: bt.bg,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  /// Returns the chosen dashboard id, or null on cancel. Fetches the
  /// user's dashboards fresh so the picker can't show stale entries.
  Future<int?> _showSaveToDashboardSheet(WidgetPayload payload) async {
    List<DashboardSummary> dashboards;
    try {
      dashboards = await _dashboardsClient.list();
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load dashboards: $e')),
      );
      return null;
    }
    if (!mounted) return null;

    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save to dashboard'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  payload.isSnapshot
                      ? 'This widget is a snapshot — its data is frozen and '
                          "won't follow the dashboard's time range."
                      : "Re-runs against the dashboard's time range on every "
                          'refresh.',
                  style: TextStyle(fontSize: 12, color: context.bt.ink3),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in dashboards)
                      ListTile(
                        dense: true,
                        title: Text(d.name),
                        onTap: () => Navigator.of(ctx).pop(d.id),
                      ),
                    ListTile(
                      dense: true,
                      title: const Text('Create new dashboard…'),
                      onTap: () async {
                        final name = await _promptForNewDashboardName(ctx);
                        if (name == null || name.isEmpty) return;
                        try {
                          final created =
                              await _dashboardsClient.create(name: name);
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop(created.id);
                        } catch (e) {
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Could not create: $e')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForNewDashboardName(BuildContext ctx) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (innerCtx) => AlertDialog(
        title: const Text('New dashboard'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.of(innerCtx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(innerCtx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(innerCtx).pop(ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
  }

  Future<void> _startNewChat() async {
    setState(() {
      _activeSessionId = null;
      _messages.clear();
      _sessionSpentUsd = 0.0;
    });
    _focusNode.requestFocus();
  }

  Future<void> _openHistory() async {
    final picked = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => InsightsHistoryView(
          client: _client,
          activeSessionId: _activeSessionId,
        ),
      ),
    );
    if (picked == null) return;
    await _loadSession(picked);
  }

  Future<void> _loadSession(int sessionId) async {
    setState(() => _busy = true);
    try {
      // Fetch messages and the session list in parallel so we can both
      // populate the transcript and pick up the running spend total.
      final msgsFuture = _client.getMessages(sessionId);
      final sessionsFuture = _client.listSessions();
      final msgs = await msgsFuture;
      final sessions = await sessionsFuture;
      double spent = 0.0;
      for (final s in sessions) {
        if (s.id == sessionId) {
          spent = s.spentUsd;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _activeSessionId = sessionId;
        _messages
          ..clear()
          ..addAll(msgs);
        _sessionSpentUsd = spent;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Could not load chat: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isHelpCommand(String input) {
    final t = input.toLowerCase();
    return t == 'help' || t == '/help';
  }

  Future<void> _showHelp(String userText) async {
    setState(() {
      _messages.add(ChatMessage.user(userText));
      _messages.add(ChatMessage.assistantPending());
      _busy = true;
    });
    _focusNode.requestFocus();
    _scrollToBottom();
    try {
      final help = await _client.getHelp();
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] =
            ChatMessage(role: ChatRole.assistant, text: help);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = ChatMessage(
          role: ChatRole.assistant,
          text: 'Could not load help: $e',
          errored: true,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();

    if (_isHelpCommand(text)) {
      await _showHelp(text);
      return;
    }

    // Optimistic: show the user turn + a pending assistant placeholder.
    setState(() {
      _messages.add(ChatMessage.user(text));
      _messages.add(ChatMessage.assistantPending());
      _busy = true;
    });
    _focusNode.requestFocus();
    _scrollToBottom();

    try {
      // Lazily create the session on the first send.
      var sid = _activeSessionId;
      if (sid == null) {
        final created = await _client.createSession();
        sid = created.id;
      }

      final reply = await _client.appendMessage(sid, text);
      if (!mounted) return;
      setState(() {
        _activeSessionId = sid;
        // Replace the optimistic user turn (penultimate) and pending assistant
        // (last) with the server-acknowledged versions.
        _messages[_messages.length - 2] = reply.userMessage;
        _messages[_messages.length - 1] = reply.assistantMessage;
        _sessionSpentUsd = reply.sessionSpentUsd;
      });
      widget.onSpendChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = ChatMessage(
          role: ChatRole.assistant,
          text: 'Network error: $e',
          errored: true,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 600;
        final headerPad = isDesktop
            ? const EdgeInsets.fromLTRB(28, 22, 28, 16)
            : const EdgeInsets.fromLTRB(18, 10, 18, 8);
        final bodyPad = isDesktop
            ? const EdgeInsets.fromLTRB(28, 0, 28, 28)
            : const EdgeInsets.fromLTRB(18, 0, 18, 18);

        if (!widget.aiEnabled) {
          // AI off — short-circuit the whole tab to a green promo. The chat
          // UI is meaningless without AI; the user opens Account to enable.
          return SafeArea(
            child: Padding(
              padding: bodyPad,
              child: AiPromo.insights(onOpenAccount: widget.onOpenAccount),
            ),
          );
        }

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: headerPad,
              child: _Header(
                isDesktop: isDesktop,
                onNewChat: _startNewChat,
                onHistory: _openHistory,
                onOpenAccount: widget.onOpenAccount,
                sessionSpentUsd: _sessionSpentUsd,
                showSpend: _activeSessionId != null || _sessionSpentUsd > 0,
              ),
            ),
            Expanded(
              child: Padding(
                padding: bodyPad,
                child: _ChatPanel(
                  messages: _messages,
                  controller: _controller,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  onSubmit: _submit,
                  busy: _busy,
                  apiKeySet: widget.apiKeySet,
                  onOpenAccount: widget.onOpenAccount,
                  onSaveWidget: _saveWidget,
                ),
              ),
            ),
          ],
        );

        return SafeArea(
          child: isDesktop
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: body,
                  ),
                )
              : body,
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isDesktop,
    required this.onNewChat,
    required this.onHistory,
    required this.onOpenAccount,
    required this.sessionSpentUsd,
    required this.showSpend,
  });

  final bool isDesktop;
  final VoidCallback onNewChat;
  final VoidCallback onHistory;
  final Future<void> Function() onOpenAccount;
  final double sessionSpentUsd;
  final bool showSpend;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    if (isDesktop) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Insights',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.025,
                color: bt.ink,
              ),
            ),
          ),
          if (showSpend) ...[
            AiSpendChip.detailed(
              amountUsd: sessionSpentUsd,
              label: 'this chat',
            ),
            const SizedBox(width: 8),
          ],
          _HeaderButton(tooltip: 'History', icon: 'menu', onPressed: onHistory),
          const SizedBox(width: 4),
          _HeaderButton(tooltip: 'New chat', icon: 'plus', onPressed: onNewChat),
        ],
      );
    }
    // Mobile: drop the page title; the bottom tab bar already labels the
    // tab. Settings icon takes its place top-left.
    return Row(
      children: [
        MobileSettingsIcon(onTap: () => onOpenAccount()),
        const Spacer(),
        if (showSpend) ...[
          AiSpendChip.detailed(
            amountUsd: sessionSpentUsd,
            label: 'this chat',
          ),
          const SizedBox(width: 8),
        ],
        _HeaderButton(tooltip: 'History', icon: 'menu', onPressed: onHistory),
        const SizedBox(width: 4),
        _HeaderButton(tooltip: 'New chat', icon: 'plus', onPressed: onNewChat),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final String icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: bt.rule),
          ),
          child: BudgetIcons.build(icon,
              size: 16, strokeWidth: 1.8, color: bt.ink2),
        ),
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.messages,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.onSubmit,
    required this.busy,
    required this.apiKeySet,
    required this.onOpenAccount,
    required this.onSaveWidget,
  });

  final List<ChatMessage> messages;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final VoidCallback onSubmit;
  final bool busy;
  final bool apiKeySet;
  final Future<void> Function() onOpenAccount;
  final Future<void> Function(ChatMessage) onSaveWidget;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final inputEnabled = apiKeySet && !busy;
    return Container(
      decoration: BoxDecoration(
        color: bt.surface,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: bt.ruleStrong),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? (apiKeySet
                      ? _EmptyTranscript(bt: bt)
                      : _NoApiKeyEmpty(bt: bt, onOpenAccount: onOpenAccount))
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      itemCount: messages.length,
                      itemBuilder: (_, i) => Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                        child: _TranscriptItem(
                          message: messages[i],
                          bt: bt,
                          onSaveWidget: onSaveWidget,
                        ),
                      ),
                    ),
            ),
            Divider(height: 1, color: bt.rule),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Text('›',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: bt.ink3,
                      )),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onSubmitted: (_) => onSubmit(),
                      textInputAction: TextInputAction.send,
                      enabled: inputEnabled,
                      cursorColor: bt.ink,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: bt.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: apiKeySet
                            ? 'Ask about your spending…'
                            : 'Set an API key in Account to chat',
                        hintStyle: TextStyle(
                            color: bt.ink4, fontFamily: 'monospace'),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: inputEnabled ? onSubmit : null,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 12),
                      child: BudgetIcons.build('arrow-up',
                          size: 16, strokeWidth: 2,
                          color: inputEnabled ? bt.ink3 : bt.ink4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoApiKeyEmpty extends StatelessWidget {
  const _NoApiKeyEmpty({required this.bt, required this.onOpenAccount});
  final BudgetTheme bt;
  final Future<void> Function() onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BudgetIcons.build('shield',
                size: 24, strokeWidth: 1.6, color: bt.ink4),
            const SizedBox(height: 14),
            Text(
              'API key needed',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: bt.ink2,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                'Insights uses your selected AI model. Add an API key for '
                'that model\'s provider in Account, then come back to chat '
                'about your spending.',
                style: TextStyle(fontSize: 12, color: bt.ink4, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onOpenAccount,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: bt.ink,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                child: Text(
                  'Open Account',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: bt.bg,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTranscript extends StatelessWidget {
  const _EmptyTranscript({required this.bt});
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BudgetIcons.build('sparkle',
                size: 24, strokeWidth: 1.6, color: bt.ink4),
            const SizedBox(height: 14),
            Text(
              'Welcome to Insights.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: bt.ink2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ask a question to get started — try “Where am I overspending?” or “How much can I save?” Charts render inline. Type “help” to see what I can do.',
              style: TextStyle(fontSize: 12, color: bt.ink4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptItem extends StatelessWidget {
  const _TranscriptItem({
    required this.message,
    required this.bt,
    required this.onSaveWidget,
  });
  final ChatMessage message;
  final BudgetTheme bt;
  final Future<void> Function(ChatMessage) onSaveWidget;

  /// Fixed render height for AI-produced widgets in the transcript.
  /// Same default as the mobile dashboard list — tall enough for charts
  /// and tables, short enough for big-number tiles to feel right.
  static const _widgetHeight = 260.0;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final prefix = isUser ? '›' : '✦';
    final prefixColor = isUser ? bt.ink4 : bt.ink3;

    if (message.pending) {
      return Padding(
        padding: const EdgeInsets.only(left: 21),
        child: Text(
          'Thinking…',
          style: TextStyle(
            fontSize: 12,
            color: bt.ink4,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final payload = message.widget;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(prefix,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: prefixColor,
            )),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isUser)
                Text(
                  message.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: message.errored ? bt.neg : bt.ink2,
                    height: 1.45,
                  ),
                )
              else
                _AssistantBody(message: message, bt: bt),
              if (payload != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: _widgetHeight,
                  child: WidgetCard(
                    widget: _fakeDashboardWidget(payload),
                    previewData: payload.asData(),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  // The save button only appears for server-acknowledged
                  // messages — optimistic / help-text / error placeholders
                  // have no `id` to reference.
                  child: message.id == null
                      ? const SizedBox.shrink()
                      : TextButton.icon(
                          onPressed: () => onSaveWidget(message),
                          icon: BudgetIcons.build('plus',
                              size: 12, color: bt.pos),
                          label: Text('Save to dashboard…',
                              style: TextStyle(fontSize: 11, color: bt.pos)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: const Size(0, 28),
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Build a stand-in [DashboardWidget] so [WidgetCard] can render an AI
/// payload without it being persisted to the dashboards layer.
DashboardWidget _fakeDashboardWidget(WidgetPayload p) => DashboardWidget(
      id: -1, dashboardId: -1, type: p.type, title: '',
      layout: const WidgetLayout(x: 0, y: 0, w: 4, h: 3),
      dataSource: const WidgetDataSource.metric(metricId: 'preview'),
      config: const {},
      createdAt: '', updatedAt: '',
    );

class _AssistantBody extends StatelessWidget {
  const _AssistantBody({required this.message, required this.bt});
  final ChatMessage message;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    final color = message.errored ? bt.neg : bt.ink;
    return MarkdownBody(
      data: message.text,
      selectable: true,
      onTapLink: (text, href, title) {},
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: 13, color: color, height: 1.45),
        h1: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: color, height: 1.3),
        h2: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: color, height: 1.3),
        h3: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: color, height: 1.3),
        listBullet: TextStyle(fontSize: 13, color: color, height: 1.45),
        em: TextStyle(fontStyle: FontStyle.italic, color: color),
        strong: TextStyle(fontWeight: FontWeight.w700, color: color),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: bt.ink2,
          backgroundColor: bt.surface2,
        ),
        codeblockDecoration: BoxDecoration(
          color: bt.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: bt.rule),
        ),
        blockquote: TextStyle(fontSize: 13, color: bt.ink3, height: 1.45),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: bt.rule, width: 3)),
        ),
        a: TextStyle(color: bt.ink, decoration: TextDecoration.underline),
      ),
    );
  }
}

