import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import '../services/dashboards_client.dart';
import '../theme/app_theme.dart';
import '../widgets/cat_icon.dart';
import 'dashboard_screen.dart';

/// Tab root for the Widgets feature.
///
/// Behavior:
/// - 0 dashboards → "Create your first dashboard" empty state.
/// - 1 dashboard  → auto-open it.
/// - 2+ dashboards → list with a "New dashboard" affordance. If the user's
///   `last_dashboard_id` matches one in the list, auto-open it on first
///   paint (and only on the very first paint — once they navigate back here
///   intentionally we stay on the list).
class WidgetsScreen extends StatefulWidget {
  const WidgetsScreen({
    super.key,
    required this.lastDashboardId,
    required this.onLastDashboardChanged,
  });

  final int? lastDashboardId;

  /// Called whenever the backend's `last_dashboard_id` may have changed
  /// server-side (i.e. after opening a dashboard). Triggers the parent to
  /// re-fetch /me so the cached value stays current across tab swaps.
  final VoidCallback onLastDashboardChanged;

  @override
  State<WidgetsScreen> createState() => _WidgetsScreenState();
}

class _WidgetsScreenState extends State<WidgetsScreen> {
  late final DashboardsClient _client;
  List<DashboardSummary>? _dashboards;
  String? _error;
  bool _autoOpenDone = false;

  @override
  void initState() {
    super.initState();
    _client = DashboardsClient();
    _load();
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _client.list();
      if (!mounted) return;
      setState(() {
        _dashboards = list;
        _error = null;
      });
      _maybeAutoOpen();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _maybeAutoOpen() {
    if (_autoOpenDone || _dashboards == null) return;
    final list = _dashboards!;
    // Exactly one → open it. Multiple + a last-viewed in the list → open it.
    int? target;
    if (list.length == 1) {
      target = list.single.id;
    } else if (list.length > 1 && widget.lastDashboardId != null) {
      final hit =
          list.where((d) => d.id == widget.lastDashboardId).toList();
      if (hit.isNotEmpty) target = hit.first.id;
    }
    if (target != null) {
      _autoOpenDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(target!));
    }
  }

  Future<void> _open(int dashboardId) async {
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DashboardScreen(
        client: _client, dashboardId: dashboardId,
      ),
    ));
    widget.onLastDashboardChanged();
    // Refresh on return so a newly-created/renamed dashboard shows up.
    if (mounted) _load();
  }

  Future<void> _createNew() async {
    final name = await _promptName(context, title: 'New dashboard');
    if (name == null || name.isEmpty) return;
    try {
      final created = await _client.create(name: name);
      if (!mounted) return;
      await _open(created.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    if (_error != null) {
      return _ErrorBody(message: _error!, onRetry: _load);
    }
    final list = _dashboards;
    if (list == null) {
      return const Center(
        child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return SafeArea(
      child: LayoutBuilder(
        builder: (_, c) {
          final isDesktop = c.maxWidth >= 600;
          final padding = isDesktop
              ? const EdgeInsets.fromLTRB(28, 22, 28, 28)
              : const EdgeInsets.fromLTRB(18, 10, 18, 18);
          return Padding(
            padding: padding,
            child: list.isEmpty
                ? _EmptyState(onCreate: _createNew)
                : _ListBody(
                    bt: bt,
                    dashboards: list,
                    onOpen: _open,
                    onCreate: _createNew,
                  ),
          );
        },
      ),
    );
  }
}

class _ListBody extends StatelessWidget {
  const _ListBody({
    required this.bt,
    required this.dashboards,
    required this.onOpen,
    required this.onCreate,
  });

  final BudgetTheme bt;
  final List<DashboardSummary> dashboards;
  final void Function(int) onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Widgets',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.025,
                  color: bt.ink,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: onCreate,
              icon: BudgetIcons.build('plus', size: 14, color: bt.bg),
              label: const Text('New dashboard'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: dashboards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final d = dashboards[i];
              return Material(
                color: bt.surface,
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                child: InkWell(
                  onTap: () => onOpen(d.id),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: bt.rule),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: bt.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Updated ${d.updatedAt.substring(0, 10)}',
                                style: TextStyle(fontSize: 11, color: bt.ink4),
                              ),
                            ],
                          ),
                        ),
                        BudgetIcons.build('chevron-right',
                            size: 16, color: bt.ink4),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BudgetIcons.build('grid', size: 28, color: bt.ink3),
            const SizedBox(height: 14),
            Text(
              'No dashboards yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: bt.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Dashboards collect widgets — charts, big-number tiles, and '
              'tables — that you can resize and arrange. Start with one to '
              'see your spending at a glance.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: bt.ink4, height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onCreate,
              child: const Text('Create your first dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load dashboards',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: bt.ink)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: bt.ink4)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Tiny in-house prompt — kept here since we already lean on AlertDialog
/// in several places and an extra utility file would be overkill.
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
}
