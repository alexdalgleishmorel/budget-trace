import 'package:flutter/material.dart';
import '../models/budget_category.dart';
import '../models/budget_cycle.dart';
import '../models/transaction.dart';
import '../screens/account_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/expenses_screen.dart';
import '../screens/insights_screen.dart';
import '../screens/widgets_screen.dart';
import '../services/categories_client.dart';
import '../services/category_tree_builder.dart';
import '../services/me_client.dart';
import '../services/transactions_client.dart';
import '../theme/app_theme.dart';
import '../utils/cycle_labels.dart';
import 'bottom_tabs.dart';
import 'demo_banner.dart';
import 'glass.dart';
import 'side_nav.dart';

const kDesktopBreakpoint = 600.0;

/// Top-level shell. Owns the loaded category tree and the current cycle's
/// transaction list; takes the user [Me] from the parent (so theme + AI flag
/// changes from AccountScreen flow back up to MaterialApp). Tab indices are
/// stable across the app: 0=Categories, 1=Expenses, 2=Widgets, 3=Insights.
/// The Widgets tab is hidden when `me.features.widgets` is off (the gap in
/// indices is irrelevant — nav lists filter the entry out).
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.me,
    required this.meClient,
    required this.onMeChanged,
    required this.onRefreshMe,
  });

  final Me me;
  final MeClient meClient;
  final ValueChanged<Me> onMeChanged;
  final Future<void> Function() onRefreshMe;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  // Re-tapping the Categories nav item while already on tab 0 should pop
  // the screen's drill-down state to root. Since `_pathIds` lives inside
  // `_CategoriesScreenState`, AppShell can't reach it directly — we send a
  // monotonically-increasing pulse instead, and CategoriesScreen resets its
  // path in `didUpdateWidget` whenever the value changes.
  int _categoriesNavPulse = 0;

  // Cycle window. Default to the current month (latest entry in the rolling
  // 12-month window). User can switch via the cycle dropdown.
  late List<String> _cycleLabels;
  late String _cycleLabel;

  late final CategoriesClient _categoriesClient;
  late final TransactionsClient _transactionsClient;

  BudgetCategory? _root;
  String? _categoryError;

  List<Transaction> _transactions = const [];
  String? _transactionsError;

  @override
  void initState() {
    super.initState();
    _categoriesClient = CategoriesClient();
    _transactionsClient = TransactionsClient();
    _cycleLabels = cycleLabelsForLast(12);
    // Provisional default — refined async via _pickInitialCycle so we land
    // on a cycle that actually has data (the seed ends a few days back, and
    // a real user's most recent import is rarely "today").
    _cycleLabel = _cycleLabels.last;
    _loadCategories();
    _pickInitialCycle();
  }

  Future<void> _pickInitialCycle() async {
    String? latest;
    try {
      latest = await _transactionsClient.latestDate();
    } catch (_) {
      // Ignore — fall through to the calendar default and let
      // _loadTransactions surface the underlying connectivity error.
    }
    if (mounted && latest != null) {
      final label = _labelForDate(latest);
      if (_cycleLabels.contains(label)) {
        setState(() => _cycleLabel = label);
      }
    }
    await _loadTransactions();
  }

  static String _labelForDate(String iso) {
    // iso is YYYY-MM-DD; cycle labels are "Month YYYY".
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final year = int.parse(iso.substring(0, 4));
    final month = int.parse(iso.substring(5, 7));
    return '${months[month - 1]} $year';
  }

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    // No tab redirect needed — the Insights tab handles AI-off by rendering
    // the AiPromo banner in place of the chat.
  }

  @override
  void dispose() {
    _categoriesClient.dispose();
    _transactionsClient.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final dtos = await _categoriesClient.list();
      if (!mounted) return;
      setState(() {
        _root = buildTree(dtos);
        _categoryError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _categoryError = e.toString());
    }
  }

  Future<void> _loadTransactions() async {
    try {
      final range = cycleRangeForLabel(_cycleLabel);
      final dtos = await _transactionsClient.list(
        startDate: range?.start,
        endDate: range?.end,
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        _transactions = dtos.map((d) => d.toTransaction()).toList();
        _transactionsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _transactionsError = e.toString());
    }
  }

  void _onCycleChange(String label) {
    setState(() => _cycleLabel = label);
    _loadTransactions();
  }

  /// After mutating either categories or transactions, screens call this so
  /// the shell re-fetches both. Re-fetching both is overkill for some
  /// operations (e.g. assigning a category doesn't change the tree) but
  /// keeps the wiring simple and is cheap against the local backend. Also
  /// refreshes `me` so the global AI-spend chip catches usage incurred by
  /// AI parser / auto-categorize during an import.
  Future<void> _refetchAll() async {
    await Future.wait([
      _loadCategories(),
      _loadTransactions(),
      widget.onRefreshMe(),
    ]);
  }

  /// Nav-tap handler shared by `BottomTabsBar` and `SideNav`. Tapping the
  /// already-active Categories tab bumps the pulse counter, which the
  /// Categories screen observes via `didUpdateWidget` to pop its drill-down
  /// back to root.
  void _onNav(int i) {
    setState(() {
      if (_tab == 0 && i == 0) _categoriesNavPulse++;
      _tab = i;
    });
  }

  Future<void> _openAccount() async {
    final route = MaterialPageRoute<void>(
      builder: (_) => AccountScreen(
        me: widget.me,
        client: widget.meClient,
        onMeChanged: widget.onMeChanged,
      ),
      fullscreenDialog: true,
    );
    await Navigator.of(context).push(route);
  }

  BudgetCycle get _cycle => BudgetCycle(
        label: _cycleLabel,
        root: _root!,
        transactions: _transactions,
      );

  Widget _buildScreen(int tab) {
    final root = _root;

    if (tab == 0) {
      if (_categoryError != null) {
        return _BackendError(message: _categoryError!, onRetry: _loadCategories);
      }
      if (root == null) {
        return const _LoadingPanel();
      }
      return CategoriesScreen(
        root: root,
        client: _categoriesClient,
        onChanged: _loadCategories,
        navPulse: _categoriesNavPulse,
        onOpenAccount: _openAccount,
      );
    }

    if (tab == 1) {
      if (_categoryError != null) {
        return _BackendError(message: _categoryError!, onRetry: _refetchAll);
      }
      if (_transactionsError != null) {
        return _BackendError(
            message: _transactionsError!, onRetry: _loadTransactions);
      }
      if (root == null) {
        return const _LoadingPanel();
      }
      return ExpensesScreen(
        cycle: _cycle,
        transactions: _transactions,
        client: _transactionsClient,
        aiEnabled: widget.me.features.ai,
        // AI parsing is usable only once a provider key is set AND a model is
        // picked. Until then the dropzone falls back to CSV-only + a setup nudge.
        aiReady: widget.me.features.ai &&
            widget.me.selectedProviderKeyAvailable &&
            widget.me.selectedModel.isNotEmpty,
        aiSpentUsd: widget.me.aiSpentUsd,
        onChanged: _refetchAll,
        cycleLabels: _cycleLabels,
        onCycleChange: _onCycleChange,
        onOpenCategories: () => setState(() => _tab = 0),
        onOpenAccount: _openAccount,
      );
    }

    if (tab == 2) {
      if (!widget.me.features.widgets) {
        // Widgets flag was flipped off (or never on). Redirect quietly to
        // Categories so we don't render an empty pane.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _tab = 0);
        });
        return const _LoadingPanel();
      }
      return WidgetsScreen(
        onLastDashboardChanged: () => widget.onRefreshMe(),
        onOpenAccount: _openAccount,
      );
    }

    if (tab == 3) {
      return InsightsScreen(
        aiEnabled: widget.me.features.ai,
        apiKeySet: widget.me.selectedProviderKeyAvailable,
        modelSelected: widget.me.selectedModel.isNotEmpty,
        onOpenAccount: _openAccount,
        onSpendChanged: () => widget.onRefreshMe(),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= kDesktopBreakpoint;

        if (isDesktop) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: AppBackground(
              child: Column(
                children: [
                  const DemoBanner(),
                  Expanded(
                    child: Row(
                      children: [
                        SideNav(
                          current: _tab,
                          onNav: _onNav,
                          cycleLabel: _cycleLabel,
                          cycleLabels: _cycleLabels,
                          onCycleChange: _onCycleChange,
                          onOpenAccount: _openAccount,
                          showWidgets: widget.me.features.widgets,
                        ),
                        Expanded(child: _buildScreen(_tab)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: AppBackground(
            child: Column(
              children: [
                const DemoBanner(),
                Expanded(child: _buildScreen(_tab)),
                BottomTabsBar(
                  current: _tab,
                  onNav: _onNav,
                  showWidgets: widget.me.features.widgets,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 22, height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _BackendError extends StatelessWidget {
  const _BackendError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Backend unreachable',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: bt.ink),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: bt.ink4),
            ),
            const SizedBox(height: 16),
            GlassButton(
              label: 'Retry',
              onPressed: () {
                onRetry();
              },
              variant: GlassButtonVariant.secondary,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}
