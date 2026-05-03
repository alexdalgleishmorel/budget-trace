import 'package:flutter/material.dart';
import '../screens/categories_screen.dart';
import '../screens/expenses_screen.dart';
import '../screens/insights_screen.dart';
import '../models/budget_category.dart';
import '../models/budget_cycle.dart';
import '../models/transaction.dart';
import '../services/categories_client.dart';
import '../services/category_tree_builder.dart';
import '../services/features_client.dart';
import '../services/transactions_client.dart';
import '../theme/app_theme.dart';
import '../utils/cycle_labels.dart';
import 'bottom_tabs.dart';
import 'side_nav.dart';
import 'theme_toggle.dart';

const kDesktopBreakpoint = 600.0;

/// Top-level shell. Owns the loaded category tree, the current cycle's
/// transaction list, and the active tab. Both data sets come from the
/// backend; the screens hit the clients directly for mutations and call
/// `_loadCategories`/`_loadTransactions` to refetch.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  // Cycle window. Default to the current month (latest entry in the rolling
  // 12-month window). User can switch via the cycle dropdown.
  late List<String> _cycleLabels;
  late String _cycleLabel;

  late final CategoriesClient _categoriesClient;
  late final TransactionsClient _transactionsClient;
  late final FeaturesClient _featuresClient;

  BudgetCategory? _root;
  String? _categoryError;

  List<Transaction> _transactions = const [];
  String? _transactionsError;

  FeatureFlags _features = FeatureFlags.off;

  @override
  void initState() {
    super.initState();
    _categoriesClient = CategoriesClient();
    _transactionsClient = TransactionsClient();
    _featuresClient = FeaturesClient();
    _cycleLabels = cycleLabelsForLast(12);
    _cycleLabel = _cycleLabels.last;
    _loadCategories();
    _loadTransactions();
    _loadFeatures();
  }

  @override
  void dispose() {
    _categoriesClient.dispose();
    _transactionsClient.dispose();
    _featuresClient.dispose();
    super.dispose();
  }

  Future<void> _loadFeatures() async {
    try {
      final f = await _featuresClient.get();
      if (!mounted) return;
      setState(() => _features = f);
    } catch (_) {
      // Feature flag failure is non-fatal — fall back to all-off.
    }
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
  /// keeps the wiring simple and is cheap against the local backend.
  Future<void> _refetchAll() async {
    await Future.wait([_loadCategories(), _loadTransactions()]);
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
        features: _features,
        onChanged: _refetchAll,
        cycleLabels: _cycleLabels,
        onCycleChange: _onCycleChange,
      );
    }

    if (tab == 2) {
      return const InsightsScreen();
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
            body: Row(
              children: [
                SideNav(
                  current: _tab,
                  onNav: (i) => setState(() => _tab = i),
                  cycleLabel: _cycleLabel,
                  cycleLabels: _cycleLabels,
                  onCycleChange: _onCycleChange,
                  isDark: widget.isDark,
                  onToggleTheme: widget.onToggleTheme,
                ),
                Expanded(child: _buildScreen(_tab)),
              ],
            ),
          );
        }

        return Scaffold(
          body: Column(
            children: [
              Expanded(child: _buildScreen(_tab)),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ThemeToggle(
                      isDark: widget.isDark,
                      onToggle: widget.onToggleTheme,
                    ),
                  ],
                ),
              ),
              BottomTabsBar(
                current: _tab,
                onNav: (i) => setState(() => _tab = i),
              ),
            ],
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
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: bt.surface,
                  border: Border.all(color: bt.ruleStrong),
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500, color: bt.ink2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
