import 'package:flutter/material.dart';

import '../models/chat_session.dart';
import '../services/chat_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_spend_chip.dart';
import '../widgets/cat_icon.dart';

/// History list of past Insights conversations. Always loads from the REST
/// API on open — no caching. Tapping a row pops with that session's id;
/// the parent then loads the full transcript.
class InsightsHistoryView extends StatefulWidget {
  const InsightsHistoryView({
    super.key,
    required this.client,
    this.activeSessionId,
  });

  final ChatClient client;
  final int? activeSessionId;

  @override
  State<InsightsHistoryView> createState() => _InsightsHistoryViewState();
}

class _InsightsHistoryViewState extends State<InsightsHistoryView> {
  Future<List<ChatSession>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.client.listSessions();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.client.listSessions();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Scaffold(
      backgroundColor: bt.bg,
      appBar: AppBar(
        backgroundColor: bt.bg,
        elevation: 0,
        title: Text(
          'Chat history',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: bt.ink,
          ),
        ),
        leading: IconButton(
          icon: BudgetIcons.build('chevron-left',
              size: 18, strokeWidth: 1.8, color: bt.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ChatSession>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Error(message: '${snap.error}', onRetry: _refresh, bt: bt);
            }
            final sessions = snap.data ?? [];
            if (sessions.isEmpty) {
              return _Empty(bt: bt);
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              itemCount: sessions.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: bt.rule),
              itemBuilder: (_, i) => _SessionTile(
                session: sessions[i],
                isActive: sessions[i].id == widget.activeSessionId,
                bt: bt,
                onTap: () => Navigator.of(context).pop(sessions[i].id),
                onDelete: () async {
                  await widget.client.deleteSession(sessions[i].id);
                  await _refresh();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.isActive,
    required this.bt,
    required this.onTap,
    required this.onDelete,
  });

  final ChatSession session;
  final bool isActive;
  final BudgetTheme bt;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: bt.ink,
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: bt.surface2,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: bt.rule),
                          ),
                          child: Text(
                            'current',
                            style: TextStyle(fontSize: 10, color: bt.ink3),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_relative(session.updatedAt)} · '
                          '${session.messageCount} '
                          'message${session.messageCount == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 11, color: bt.ink4),
                        ),
                      ),
                      if (session.spentUsd > 0)
                        AiSpendChip.compact(
                          amountUsd: session.spentUsd,
                          isEstimate: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: BudgetIcons.build('trash',
                  size: 16, strokeWidth: 1.6, color: bt.ink4),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete chat?'),
                    content: Text('"${session.title}" will be removed.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _relative(DateTime when) {
    final now = DateTime.now().toUtc();
    final diff = now.difference(when.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${when.toLocal().year}-${when.toLocal().month.toString().padLeft(2, '0')}-${when.toLocal().day.toString().padLeft(2, '0')}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.bt});
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              BudgetIcons.build('search',
                  size: 22, strokeWidth: 1.6, color: bt.ink4),
              const SizedBox(height: 12),
              Text(
                'No previous chats yet.',
                style: TextStyle(fontSize: 13, color: bt.ink3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry, required this.bt});
  final String message;
  final Future<void> Function() onRetry;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  'Could not load history.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: bt.ink2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(fontSize: 12, color: bt.neg),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
