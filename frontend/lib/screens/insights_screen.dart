import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/dashboard.dart';
import '../services/chat_client.dart';
import '../services/dashboards_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_promo.dart';
import '../widgets/ai_spend_chip.dart';
import '../widgets/cat_icon.dart';
import '../widgets/dash_widgets/widget_card.dart';
import '../widgets/glass.dart';
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
    required this.modelSelected,
    required this.onOpenAccount,
    required this.onSpendChanged,
  });

  /// Whether the master `ai` feature flag is on. When false, the tab is
  /// still reachable but renders an [AiPromo] empty state instead of the
  /// chat — the user enables AI in Account to unlock it.
  final bool aiEnabled;

  /// Whether the selected provider has an API key available (stored on the
  /// user or present in env). When false (but AI is on), the chat input is
  /// disabled and the empty-state guides the user to Account instead of
  /// letting them hit a 400 on submit.
  final bool apiKeySet;

  /// Whether a model has been picked. AI calls need both a key and a model;
  /// when no model is selected the input is disabled and the empty-state
  /// points the user to Account to fetch + pick one.
  final bool modelSelected;

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
  // Sessions surfaced in the desktop sidebar. Loaded once on mount and
  // refreshed whenever the active session changes (new message, switched
  // session, or a fresh chat started).
  List<ChatSession> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _client = ChatClient();
    _dashboardsClient = DashboardsClient();
    if (widget.aiEnabled) _loadSessions();
  }

  /// Best-effort sessions refresh. Silently swallows errors — the sidebar
  /// is a navigational aid, not a primary surface. If we can't reach the
  /// API we just keep the previous list (or show empty on first load).
  Future<void> _loadSessions() async {
    try {
      final s = await _client.listSessions();
      if (!mounted) return;
      setState(() => _sessions = s);
    } catch (_) {
      // No-op — the History view is still the canonical place to see
      // every session and surfaces its own error if listing fails.
    }
  }

  /// Title for the active session (used in the header h2). Falls back to
  /// "New chat" when nothing's been sent yet or the session isn't in the
  /// cached list (e.g. mid-load).
  String get _activeSessionTitle {
    final sid = _activeSessionId;
    if (sid == null) return 'New chat';
    for (final s in _sessions) {
      if (s.id == sid) return s.title;
    }
    return 'New chat';
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
      barrierColor: const Color(0x8C080614),
      builder: (ctx) => _SaveToDashboardModal(
        dashboards: dashboards,
        payload: payload,
        onCreateNew: () async {
          final name = await _promptForNewDashboardName(ctx);
          if (name == null || name.isEmpty) return null;
          try {
            final created = await _dashboardsClient.create(name: name);
            return created.id;
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('Could not create: $e')),
              );
            }
            return null;
          }
        },
      ),
    );
  }

  Future<String?> _promptForNewDashboardName(BuildContext ctx) {
    return showDialog<String>(
      context: ctx,
      barrierColor: const Color(0x8C080614),
      builder: (innerCtx) => const _NewDashboardModal(),
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
      // Refresh the sidebar so the new session (or updated title / spend
      // for an existing one) reflects this turn.
      unawaited(_loadSessions());
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

        if (!widget.aiEnabled) {
          // AI off — short-circuit the whole tab to a promo. The chat UI is
          // meaningless without AI; the user opens Account to enable.
          return SafeArea(
            child: Padding(
              padding: isDesktop
                  ? const EdgeInsets.fromLTRB(28, 22, 28, 28)
                  : const EdgeInsets.fromLTRB(18, 22, 18, 18),
              child: AiPromo.insights(onOpenAccount: widget.onOpenAccount),
            ),
          );
        }

        final chatColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: isDesktop
                  ? const EdgeInsets.fromLTRB(24, 22, 24, 12)
                  : const EdgeInsets.fromLTRB(18, 10, 18, 8),
              child: _Header(
                isDesktop: isDesktop,
                sessionTitle: _activeSessionTitle,
                onNewChat: _startNewChat,
                onHistory: _openHistory,
                onOpenAccount: widget.onOpenAccount,
                sessionSpentUsd: _sessionSpentUsd,
                showSpend: _activeSessionId != null || _sessionSpentUsd > 0,
              ),
            ),
            Expanded(
              child: _ChatPanel(
                isDesktop: isDesktop,
                messages: _messages,
                controller: _controller,
                focusNode: _focusNode,
                scrollController: _scrollController,
                onSubmit: _submit,
                busy: _busy,
                apiKeySet: widget.apiKeySet,
                modelSelected: widget.modelSelected,
                onOpenAccount: widget.onOpenAccount,
                onSaveWidget: _saveWidget,
              ),
            ),
          ],
        );

        if (!isDesktop) {
          return SafeArea(child: chatColumn);
        }
        return SafeArea(
          child: Row(
            children: [
              _SessionsSidebar(
                sessions: _sessions,
                activeId: _activeSessionId,
                onSelect: _loadSession,
                onNewChat: _startNewChat,
              ),
              Expanded(child: chatColumn),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isDesktop,
    required this.sessionTitle,
    required this.onNewChat,
    required this.onHistory,
    required this.onOpenAccount,
    required this.sessionSpentUsd,
    required this.showSpend,
  });

  final bool isDesktop;
  final String sessionTitle;
  final VoidCallback onNewChat;
  final VoidCallback onHistory;
  final Future<void> Function() onOpenAccount;
  final double sessionSpentUsd;
  final bool showSpend;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    // Eyebrow + session h2 on the left, action cluster on the right —
    // matches the wireframe's "Sessions / Biggest expenses recap" layout.
    // History + new-chat are 36×36 pills (glass-2 / accent gradient).
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'INSIGHTS',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.06 * 11,
            fontWeight: FontWeight.w500,
            color: bt.ink3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sessionTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isDesktop ? 22 : 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.015,
            color: bt.ink,
          ),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSpend) ...[
          AiSpendChip.detailed(
            amountUsd: sessionSpentUsd,
            label: 'this chat',
          ),
          const SizedBox(width: 8),
        ],
        _HeaderButton(tooltip: 'History', icon: 'history', onPressed: onHistory),
        const SizedBox(width: 6),
        _NewChatButton(onPressed: onNewChat),
      ],
    );

    if (isDesktop) {
      return Row(
        children: [
          Expanded(child: titleBlock),
          actions,
        ],
      );
    }
    // Mobile: settings icon top-left, title + actions below it stacked
    // into a Row sharing the available width.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MobileSettingsIcon(onTap: () => onOpenAccount()),
            const Spacer(),
            actions,
          ],
        ),
        const SizedBox(height: 10),
        titleBlock,
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
    // 36×36 pill — glass-2 fill, ink-2 stroke. Matches the wireframe's
    // history button next to the accent-gradient new-chat one.
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: GlassSurface(
              tier: GlassTier.t2,
              radius: 999,
              elevated: false,
              sheen: false,
              child: Center(
                child: BudgetIcons.build(icon,
                    size: 14, strokeWidth: 1.6, color: bt.ink2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent-gradient 36×36 round button used for the "new chat" action and
/// the input bar's send icon. Stroke icon defaults to white via the
/// inherited [IconTheme].
class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Tooltip(
      message: 'New chat',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bt.accentGrad,
                stops: bt.accentGradStops,
              ),
              boxShadow: [
                BoxShadow(
                  color: bt.accent.withValues(alpha: 0.30),
                  blurRadius: 14,
                  spreadRadius: -3,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: BudgetIcons.build('plus',
                size: 14, strokeWidth: 2, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.isDesktop,
    required this.messages,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.onSubmit,
    required this.busy,
    required this.apiKeySet,
    required this.modelSelected,
    required this.onOpenAccount,
    required this.onSaveWidget,
  });

  final bool isDesktop;
  final List<ChatMessage> messages;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final VoidCallback onSubmit;
  final bool busy;
  final bool apiKeySet;
  final bool modelSelected;
  final Future<void> Function() onOpenAccount;
  final Future<void> Function(ChatMessage) onSaveWidget;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    // Chat needs both a provider key AND a picked model. The text field stays
    // typable whenever the user is allowed to chat (`ready`) — NOT gated on
    // `busy`, because toggling `enabled` off mid-focus leaves the field stuck
    // unresponsive. Only the send button respects `busy`.
    final ready = apiKeySet && modelSelected;
    final transcriptPadX = isDesktop ? 24.0 : 18.0;

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? (!apiKeySet
                  ? _NoApiKeyEmpty(bt: bt, onOpenAccount: onOpenAccount)
                  : !modelSelected
                      ? _NoModelEmpty(bt: bt, onOpenAccount: onOpenAccount)
                      : _EmptyTranscript(bt: bt))
              : ListView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                      transcriptPadX, 8, transcriptPadX, 12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                    child: _TranscriptItem(
                      message: messages[i],
                      bt: bt,
                      isDesktop: isDesktop,
                      onSaveWidget: onSaveWidget,
                    ),
                  ),
                ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            transcriptPadX,
            8,
            transcriptPadX,
            isDesktop ? 20 : 16,
          ),
          child: _InputBar(
            controller: controller,
            focusNode: focusNode,
            onSubmit: onSubmit,
            enabled: ready,
            canSend: ready && !busy,
            apiKeySet: apiKeySet,
            modelSelected: modelSelected,
          ),
        ),
      ],
    );
  }
}

/// Glass-pill input bar matching the wireframe — sparkle icon on the left,
/// transparent TextField, accent-gradient send button on the right.
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.enabled,
    required this.canSend,
    required this.apiKeySet,
    required this.modelSelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  /// Whether the user may chat at all (key + model). Controls the text field —
  /// independent of `busy` so typing never gets locked mid-response.
  final bool enabled;

  /// Whether a send is allowed right now (`enabled` and not mid-response).
  final bool canSend;

  final bool apiKeySet;
  final bool modelSelected;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return GlassSurface(
      tier: GlassTier.t1,
      radius: 999,
      elevated: false,
      sheen: false,
      padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BudgetIcons.build('sparkle',
              size: 14, strokeWidth: 1.8, color: bt.accent),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onSubmitted: (_) => onSubmit(),
              textInputAction: TextInputAction.send,
              enabled: enabled,
              cursorColor: bt.accent,
              style: TextStyle(fontSize: 14, color: bt.ink),
              decoration: InputDecoration(
                hintText: !apiKeySet
                    ? 'Set an API key in Account to chat'
                    : !modelSelected
                        ? 'Pick a model in Account to chat'
                        : 'Ask about your spending…',
                hintStyle: TextStyle(fontSize: 14, color: bt.ink4),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(enabled: canSend, onPressed: onSubmit),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onPressed});
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bt.accentGrad,
                stops: bt.accentGradStops,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: bt.accent.withValues(alpha: 0.30),
                        blurRadius: 14,
                        spreadRadius: -3,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: BudgetIcons.build('arrow-up',
                size: 14, strokeWidth: 2, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Desktop-only left rail. Shows the most recent chat sessions; tapping
/// one loads its transcript. The currently-active session is rendered
/// with a glass-2 fill + border. A "New chat" affordance lives below the
/// list so users can clear the transcript without hunting for the
/// header's plus button.
class _SessionsSidebar extends StatelessWidget {
  const _SessionsSidebar({
    required this.sessions,
    required this.activeId,
    required this.onSelect,
    required this.onNewChat,
  });

  final List<ChatSession> sessions;
  final int? activeId;
  final void Function(int) onSelect;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: bt.glassBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Text(
              'SESSIONS',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.06 * 11,
                fontWeight: FontWeight.w500,
                color: bt.ink3,
              ),
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Text(
                      'No saved chats yet. Ask a question to start one.',
                      style: TextStyle(
                          fontSize: 12, color: bt.ink4, height: 1.5),
                    ),
                  )
                : ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (_, i) {
                      final s = sessions[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _SessionRow(
                          session: s,
                          active: s.id == activeId,
                          onTap: () => onSelect(s.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.active,
    required this.onTap,
  });

  final ChatSession session;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? bt.ink : bt.ink2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _relativeDate(session.updatedAt),
            style: TextStyle(fontSize: 11, color: bt.ink3),
          ),
        ],
      ),
    );

    final shell = active
        ? GlassSurface(
            tier: GlassTier.t2,
            radius: 10,
            elevated: false,
            sheen: false,
            child: body,
          )
        : body;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: active ? null : bt.glass1,
        child: shell,
      ),
    );
  }

  static String _relativeDate(DateTime dt) {
    // Server timestamps are UTC (…Z). Convert to local before comparing dates,
    // otherwise a user behind UTC sees the UTC "tomorrow" and gets "-1 days".
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(local.year, local.month, local.day);
    final diff = today.difference(d).inDays;
    // Clamp tiny clock skew (timestamp slightly ahead of now) to "today".
    if (diff <= 0) return 'today';
    if (diff == 1) return 'yesterday';
    if (diff < 7) return '$diff days ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }
}

class _NoApiKeyEmpty extends StatelessWidget {
  const _NoApiKeyEmpty({required this.bt, required this.onOpenAccount});
  final BudgetTheme bt;
  final Future<void> Function() onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return _EmptyShell(
      headline: 'API key needed',
      body:
          'Insights uses your selected AI model. Add an API key for that '
          "model's provider in Account, then come back to chat about your "
          'spending.',
      cta: GlassButton(
        label: 'Open Account',
        onPressed: onOpenAccount,
        variant: GlassButtonVariant.primary,
        compact: true,
      ),
    );
  }
}

class _NoModelEmpty extends StatelessWidget {
  const _NoModelEmpty({required this.bt, required this.onOpenAccount});
  final BudgetTheme bt;
  final Future<void> Function() onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return _EmptyShell(
      headline: 'Pick a model',
      body:
          'You\'ve set a key — now fetch your provider\'s models and pick one '
          'in Account, then come back to chat about your spending.',
      cta: GlassButton(
        label: 'Open Account',
        onPressed: onOpenAccount,
        variant: GlassButtonVariant.primary,
        compact: true,
      ),
    );
  }
}

class _EmptyTranscript extends StatelessWidget {
  const _EmptyTranscript({required this.bt});
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return const _EmptyShell(
      headline: 'Ask your money anything',
      body:
          'Try "where am I overspending?" or "how much can I save?" '
          'Charts render inline. Type "help" to see what I can do.',
    );
  }
}

/// Shared layout for the empty / no-key states. 64×64 accent-gradient
/// sparkle tile + h2 headline + body text + optional CTA, all centered
/// in the available space. Matches the wireframe's enabled-state empty
/// transcript more than the previous "small icon + caption" layout.
class _EmptyShell extends StatelessWidget {
  const _EmptyShell({
    required this.headline,
    required this.body,
    this.cta,
  });

  final String headline;
  final String body;
  final Widget? cta;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GradientIconTile(
                size: 64,
                radius: 20,
                child: BudgetIcons.build('sparkle',
                    size: 26, strokeWidth: 1.8, color: Colors.white),
              ),
              const SizedBox(height: 18),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.015,
                  color: bt.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: bt.ink3,
                  height: 1.55,
                ),
              ),
              if (cta != null) ...[
                const SizedBox(height: 18),
                cta!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TranscriptItem extends StatelessWidget {
  const _TranscriptItem({
    required this.message,
    required this.bt,
    required this.isDesktop,
    required this.onSaveWidget,
  });
  final ChatMessage message;
  final BudgetTheme bt;
  final bool isDesktop;
  final Future<void> Function(ChatMessage) onSaveWidget;

  @override
  Widget build(BuildContext context) {
    if (message.role == ChatRole.user) {
      return _UserBubble(text: message.text, isDesktop: isDesktop);
    }
    return _AssistantBubble(
      message: message,
      isDesktop: isDesktop,
      onSaveWidget: onSaveWidget,
    );
  }
}

/// Right-aligned user message bubble. Accent-gradient fill, white text,
/// 18 px radius with a 6 px bottom-right corner.
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text, required this.isDesktop});
  final String text;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 520 : double.infinity,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: bt.accentGrad,
                  stops: bt.accentGradStops,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: bt.accent.withValues(alpha: 0.22),
                    blurRadius: 20,
                    spreadRadius: -4,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1,
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Left-aligned assistant bubble. 30×30 accent-gradient avatar with a
/// sparkle glyph + a tier-1 glass card containing the markdown body and
/// (optionally) an inline widget preview with a "Save to dashboard" CTA
/// strip at the bottom.
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.message,
    required this.isDesktop,
    required this.onSaveWidget,
  });
  final ChatMessage message;
  final bool isDesktop;
  final Future<void> Function(ChatMessage) onSaveWidget;

  /// Fixed render height for AI-produced widgets in the transcript.
  /// Same default as the mobile dashboard list — tall enough for charts
  /// and tables, short enough for big-number tiles to feel right.
  static const _widgetHeight = 260.0;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final payload = message.widget;

    final bubbleBody = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.pending)
            Text(
              'Thinking…',
              style: TextStyle(
                fontSize: 13,
                color: bt.ink4,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            _AssistantBody(message: message, bt: bt),
          if (payload != null) ...[
            const SizedBox(height: 12),
            // Tier-2 inset glass container — matches the wireframe's
            // .glass-2 inline widget. Tall enough for a chart/table; the
            // outer GlassSurface clips its own border-radius so the
            // "Save to dashboard…" strip sits flush against the bottom.
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: bt.glassBorder),
                  color: bt.glass2,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: _widgetHeight,
                      child: WidgetCard(
                        widget: _fakeDashboardWidget(payload),
                        previewData: payload.asData(),
                      ),
                    ),
                    if (message.id != null)
                      _SaveToDashboardStrip(
                        onTap: () => onSaveWidget(message),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AssistantAvatar(),
        const SizedBox(width: 10),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 600 : double.infinity,
            ),
            child: GlassSurface(
              tier: GlassTier.t1,
              radius: 18,
              child: bubbleBody,
            ),
          ),
        ),
      ],
    );
  }
}

class _AssistantAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bt.accentGrad,
          stops: bt.accentGradStops,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: BudgetIcons.build('sparkle',
          size: 14, strokeWidth: 1.8, color: Colors.white),
    );
  }
}

/// Full-width CTA strip at the bottom of an inline widget. Glass-3 fill
/// with accent-coloured text, matching the wireframe's "Save as widget"
/// row.
class _SaveToDashboardStrip extends StatelessWidget {
  const _SaveToDashboardStrip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: bt.glass3,
            border: Border(top: BorderSide(color: bt.glassBorder)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BudgetIcons.build('plus',
                  size: 12, strokeWidth: 2, color: bt.accent),
              const SizedBox(width: 8),
              Text(
                'Save to dashboard',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: bt.accent,
                ),
              ),
            ],
          ),
        ),
      ),
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
          fontFamily: 'SF Mono',
          fontFamilyFallback: const ['Menlo', 'monospace'],
          fontSize: 12,
          color: bt.ink2,
          backgroundColor: bt.glass1,
        ),
        codeblockDecoration: BoxDecoration(
          color: bt.glass1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: bt.glassBorder),
        ),
        blockquote: TextStyle(fontSize: 13, color: bt.ink3, height: 1.45),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: bt.accent, width: 3)),
        ),
        a: TextStyle(color: bt.accent, decoration: TextDecoration.underline),
      ),
    );
  }
}

// ── Shared modal chrome ──────────────────────────────────────────────────────
//
// Matches the visual treatment used by the category / transaction edit
// modals: a tier-strong glass shell with a 24 dp radius, a header strip
// (border-bottom, title + close pill), a scrollable body, and a glass-1
// footer strip (border-top) for action buttons. Pulled out as a shared
// helper here so the save-to-dashboard and new-dashboard prompts read
// identically to the form modals.

class _ModalShell extends StatelessWidget {
  const _ModalShell({
    required this.title,
    required this.child,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassSurface(
          tier: GlassTier.strong,
          radius: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: bt.glassBorder)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.015,
                          color: bt.ink,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: BudgetIcons.build('close',
                            size: 18, strokeWidth: 1.8, color: bt.ink3),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                  child: child,
                ),
              ),
              if (footer != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                  decoration: BoxDecoration(
                    color: bt.glass1,
                    border: Border(top: BorderSide(color: bt.glassBorder)),
                  ),
                  child: footer!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveToDashboardModal extends StatelessWidget {
  const _SaveToDashboardModal({
    required this.dashboards,
    required this.payload,
    required this.onCreateNew,
  });

  final List<DashboardSummary> dashboards;
  final WidgetPayload payload;
  /// Returns the id of a newly-created dashboard, or null when the user
  /// cancels the inner "New dashboard" prompt or the create fails.
  final Future<int?> Function() onCreateNew;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return _ModalShell(
      title: 'Save to dashboard',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GlassButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
            variant: GlassButtonVariant.secondary,
            compact: true,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            payload.isSnapshot
                ? 'This widget is a snapshot — its data is frozen and '
                    "won't follow the dashboard's time range."
                : "Re-runs against the dashboard's time range on every "
                    'refresh.',
            style: TextStyle(fontSize: 12, color: bt.ink3, height: 1.5),
          ),
          const SizedBox(height: 14),
          if (dashboards.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No dashboards yet — create one below to save this widget to.',
                style: TextStyle(fontSize: 12, color: bt.ink4, height: 1.5),
              ),
            )
          else
            for (var i = 0; i < dashboards.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              _DashboardRow(
                name: dashboards[i].name,
                onTap: () => Navigator.of(context).pop(dashboards[i].id),
              ),
            ],
          const SizedBox(height: 10),
          _DashboardRow(
            name: 'Create new dashboard…',
            iconName: 'plus',
            accent: true,
            onTap: () async {
              final created = await onCreateNew();
              if (!context.mounted) return;
              if (created != null) Navigator.of(context).pop(created);
            },
          ),
        ],
      ),
    );
  }
}

class _DashboardRow extends StatelessWidget {
  const _DashboardRow({
    required this.name,
    required this.onTap,
    this.iconName,
    this.accent = false,
  });

  final String name;
  final VoidCallback onTap;
  /// Optional leading icon — used for the "Create new dashboard…" affordance.
  final String? iconName;
  /// When true, renders the row in accent colour (the create-new affordance
  /// reads as primary against the regular dashboard list rows).
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final fg = accent ? bt.accent : bt.ink;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: bt.glass2,
        child: GlassSurface(
          tier: GlassTier.t1,
          radius: 12,
          elevated: false,
          sheen: false,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (iconName != null) ...[
                BudgetIcons.build(iconName!,
                    size: 14, strokeWidth: 1.8, color: fg),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
              if (!accent)
                BudgetIcons.build('chevron-right',
                    size: 14, strokeWidth: 1.8, color: bt.ink4),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewDashboardModal extends StatefulWidget {
  const _NewDashboardModal();

  @override
  State<_NewDashboardModal> createState() => _NewDashboardModalState();
}

class _NewDashboardModalState extends State<_NewDashboardModal> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return _ModalShell(
      title: 'New dashboard',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GlassButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
            variant: GlassButtonVariant.secondary,
            compact: true,
          ),
          const SizedBox(width: 8),
          GlassButton(
            label: 'Create',
            onPressed: _submit,
            variant: GlassButtonVariant.primary,
            compact: true,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'NAME',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.06 * 11,
              fontWeight: FontWeight.w500,
              color: bt.ink3,
            ),
          ),
          const SizedBox(height: 8),
          GlassField(
            controller: _ctrl,
            autofocus: true,
            placeholder: 'e.g. Monthly overview',
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    );
  }
}

