import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import '../services/dashboards_client.dart';
import '../theme/app_theme.dart';
import '../widgets/cat_icon.dart';
import '../widgets/glass.dart';
import '../widgets/mobile_settings_icon.dart';
import 'dashboard_screen.dart';

/// Tab root for the Widgets feature.
///
/// Behavior:
/// - 0 dashboards → "Create your first dashboard" empty state.
/// - 1+ dashboards → searchable table. The user always lands on the overview;
///   opening a specific dashboard is an explicit tap. Rename and delete
///   live here (per-row icon buttons) — they used to be a dropdown on the
///   dashboard screen but moved here to keep that header tight.
class WidgetsScreen extends StatefulWidget {
  const WidgetsScreen({
    super.key,
    required this.onLastDashboardChanged,
    required this.onOpenAccount,
  });

  /// Called whenever the backend's `last_dashboard_id` may have changed
  /// server-side (i.e. after opening a dashboard). Triggers the parent to
  /// re-fetch /me so the cached value stays current across tab swaps.
  final VoidCallback onLastDashboardChanged;

  /// Pushes the Account screen — wired to the mobile header's settings
  /// icon (matches Categories / Expenses / Insights mobile pattern).
  /// Desktop has its own Account button in the side nav.
  final VoidCallback onOpenAccount;

  @override
  State<WidgetsScreen> createState() => _WidgetsScreenState();
}

class _WidgetsScreenState extends State<WidgetsScreen> {
  late final DashboardsClient _client;
  final TextEditingController _filterCtrl = TextEditingController();

  List<DashboardSummary>? _dashboards;
  String _filter = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = DashboardsClient();
    _load();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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

  Future<void> _rename(DashboardSummary d) async {
    final next = await _promptName(
      context,
      title: 'Rename dashboard',
      initial: d.name,
    );
    if (next == null || next.isEmpty || next == d.name) return;
    try {
      await _client.update(d.id, name: next);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed: $e')),
      );
    }
  }

  Future<void> _delete(DashboardSummary d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete dashboard?'),
        content: Text('"${d.name}" and all its widgets will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.delete(d.id);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  List<DashboardSummary> _visibleDashboards(List<DashboardSummary> all) {
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return all;
    return [for (final d in all) if (d.name.toLowerCase().contains(q)) d];
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
                ? _EmptyState(
                    onCreate: _createNew,
                    isDesktop: isDesktop,
                    onOpenAccount: widget.onOpenAccount,
                  )
                : _ListBody(
                    bt: bt,
                    isDesktop: isDesktop,
                    onOpenAccount: widget.onOpenAccount,
                    dashboards: _visibleDashboards(list),
                    totalCount: list.length,
                    filter: _filter,
                    filterCtrl: _filterCtrl,
                    onFilterChanged: (q) => setState(() => _filter = q),
                    onOpen: _open,
                    onCreate: _createNew,
                    onRename: _rename,
                    onDelete: _delete,
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
    required this.isDesktop,
    required this.onOpenAccount,
    required this.dashboards,
    required this.totalCount,
    required this.filter,
    required this.filterCtrl,
    required this.onFilterChanged,
    required this.onOpen,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
  });

  final BudgetTheme bt;
  final bool isDesktop;
  final VoidCallback onOpenAccount;
  final List<DashboardSummary> dashboards;

  /// Total number of dashboards (pre-filter). Used to render the empty-
  /// search state with a useful message ("nothing matches X").
  final int totalCount;
  final String filter;
  final TextEditingController filterCtrl;
  final ValueChanged<String> onFilterChanged;
  final void Function(int) onOpen;
  final VoidCallback onCreate;
  final void Function(DashboardSummary) onRename;
  final void Function(DashboardSummary) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          bt: bt,
          isDesktop: isDesktop,
          onCreate: onCreate,
          onOpenAccount: onOpenAccount,
        ),
        SizedBox(height: isDesktop ? 14 : 12),
        // Search bar — local string filter, case-insensitive substring
        // match against the dashboard name.
        TextField(
          controller: filterCtrl,
          onChanged: onFilterChanged,
          decoration: InputDecoration(
            hintText: 'Search dashboards',
            hintStyle: TextStyle(color: bt.ink4),
            isDense: true,
            prefixIcon: Padding(
              padding: const EdgeInsets.all(10),
              child: BudgetIcons.build('search', size: 16, color: bt.ink4),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36, minHeight: 36,
            ),
            suffixIcon: filter.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close, size: 16, color: bt.ink3),
                    onPressed: () {
                      filterCtrl.clear();
                      onFilterChanged('');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: bt.fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: bt.fieldBorder),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: dashboards.isEmpty
              ? _NoMatches(bt: bt, filter: filter, totalCount: totalCount)
              : _DashboardTable(
                  bt: bt,
                  dashboards: dashboards,
                  onOpen: onOpen,
                  onRename: onRename,
                  onDelete: onDelete,
                ),
        ),
      ],
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({
    required this.bt,
    required this.filter,
    required this.totalCount,
  });

  final BudgetTheme bt;
  final String filter;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final msg = totalCount == 0
        ? 'No dashboards yet.'
        : 'No dashboards match "$filter".';
    return Center(
      child: Text(msg, style: TextStyle(fontSize: 13, color: bt.ink4)),
    );
  }
}

class _DashboardTable extends StatelessWidget {
  const _DashboardTable({
    required this.bt,
    required this.dashboards,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final BudgetTheme bt;
  final List<DashboardSummary> dashboards;
  final void Function(int) onOpen;
  final void Function(DashboardSummary) onRename;
  final void Function(DashboardSummary) onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.t1,
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TableHeader(bt: bt),
          Divider(height: 1, color: bt.glassBorder),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: dashboards.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: bt.glassBorder),
              itemBuilder: (_, i) => _TableRow(
                bt: bt,
                dashboard: dashboards[i],
                onOpen: () => onOpen(dashboards[i].id),
                onRename: () => onRename(dashboards[i]),
                onDelete: () => onDelete(dashboards[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.bt});
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: bt.ink4,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('NAME', style: style)),
          Expanded(flex: 2, child: Text('LAST UPDATED', style: style)),
          const SizedBox(width: 84), // matches icon-button cluster width
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.bt,
    required this.dashboard,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final BudgetTheme bt;
  final DashboardSummary dashboard;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        hoverColor: bt.glass2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  dashboard.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: bt.ink,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  dashboard.updatedAt.substring(0, 10),
                  style: TextStyle(fontSize: 12, color: bt.ink3),
                ),
              ),
              SizedBox(
                width: 84,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Rename',
                      visualDensity: VisualDensity.compact,
                      onPressed: onRename,
                      icon: BudgetIcons.build('edit',
                          size: 16, strokeWidth: 1.6, color: bt.ink3),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: BudgetIcons.build('trash',
                          size: 16, strokeWidth: 1.6, color: bt.neg),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onCreate,
    required this.isDesktop,
    required this.onOpenAccount,
  });
  final VoidCallback onCreate;
  final bool isDesktop;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mobile gets the same compact header as the populated list state —
        // settings icon on the left, "+ New" on the right. Without it the
        // empty state has no way to reach Account on mobile.
        if (!isDesktop) ...[
          _Header(
            bt: bt,
            isDesktop: false,
            onCreate: onCreate,
            onOpenAccount: onOpenAccount,
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: Center(
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
                  GlassButton(
                    label: 'Create your first dashboard',
                    onPressed: onCreate,
                    variant: GlassButtonVariant.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tab header shared between the populated list and the mobile empty state.
/// Desktop keeps the page title; mobile drops it (the bottom nav already
/// labels the tab) and puts the Account settings icon in its place.
class _Header extends StatelessWidget {
  const _Header({
    required this.bt,
    required this.isDesktop,
    required this.onCreate,
    required this.onOpenAccount,
  });

  final BudgetTheme bt;
  final bool isDesktop;
  final VoidCallback onCreate;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
          GlassButton(
            label: 'New dashboard',
            onPressed: onCreate,
            variant: GlassButtonVariant.primary,
            icon: BudgetIcons.build('plus', size: 14, strokeWidth: 1.8),
          ),
        ],
      );
    }
    // Mobile: settings icon (top-left) + compact "+ New" primary (top-right).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MobileSettingsIcon(onTap: onOpenAccount),
        const Spacer(),
        GlassButton(
          label: 'New dashboard',
          onPressed: onCreate,
          variant: GlassButtonVariant.primary,
          compact: true,
          icon: BudgetIcons.build('plus', size: 13, strokeWidth: 1.8),
        ),
      ],
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
