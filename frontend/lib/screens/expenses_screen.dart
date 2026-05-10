import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/budget_category.dart';
import '../models/budget_cycle.dart';
import '../models/transaction.dart';
import '../services/transactions_client.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/leaf_categories.dart';
import '../widgets/budget_card.dart';
import '../widgets/cat_icon.dart';
import '../widgets/mobile_settings_icon.dart';
import '../widgets/category_chip.dart';
import '../widgets/cycle_dropdown.dart';
import '../widgets/dropzone.dart';
import '../widgets/transaction_edit_modal.dart';

/// Expenses tab. Reads transactions from AppShell's loaded list (the shell
/// owns fetching + cycle filtering) and pushes mutations directly through
/// [client], asking AppShell for a refetch via [onChanged] afterwards.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    required this.cycle,
    required this.transactions,
    required this.client,
    required this.aiEnabled,
    required this.aiSpentUsd,
    required this.onChanged,
    required this.cycleLabels,
    required this.onCycleChange,
    required this.onOpenCategories,
    required this.onOpenAccount,
  });

  final BudgetCycle cycle;
  final List<Transaction> transactions;
  final TransactionsClient client;
  final bool aiEnabled;

  /// Estimated cumulative AI spend so far. Surfaced as a metric inside
  /// the upload [Dropzone] when AI parsing is on, so the user sees running
  /// cost adjacent to the only other AI surface besides the chat.
  final double aiSpentUsd;

  final Future<void> Function() onChanged;
  final List<String> cycleLabels;
  final ValueChanged<String> onCycleChange;

  /// Switches the AppShell to the Categories tab. Used by the empty-state
  /// panel's inline "Categories" link.
  final VoidCallback onOpenCategories;

  /// Pushes the Account screen. Driven by the mobile header's settings
  /// icon (replaces the "Expenses" page title); desktop has its own
  /// Account button in the side nav.
  final VoidCallback onOpenAccount;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _search = '';
  String? _filterCat;

  List<Transaction> get _unknown => widget.transactions.where((t) => t.category == null).toList();
  List<Transaction> get _known => widget.transactions.where((t) => t.category != null).toList();

  List<Transaction> get _filtered {
    var list = _known;
    if (_search.isNotEmpty) {
      list = list.where((t) => t.merchant.toLowerCase().contains(_search.toLowerCase())).toList();
    }
    if (_filterCat != null) {
      list = list.where((t) => t.category == _filterCat).toList();
    }
    return list;
  }

  double get _total => widget.transactions.fold(0, (s, t) => s + t.amount);

  /// Chip dropdown picked a category name. Resolve to id, PATCH, refetch.
  /// Fire-and-forget from CategoryChip's perspective (its onChange is void).
  void _onAssign(Transaction t, String categoryName) {
    () async {
      final id = categoryIdForName(widget.cycle.root, categoryName);
      if (id == null) return;
      await widget.client.update(
        int.parse(t.id),
        categoryId: id,
        categoryExplicit: true,
      );
      await widget.onChanged();
    }();
  }

  Future<void> _openEditModal(Transaction t) async {
    await TransactionEditModal.show(
      context: context,
      transaction: t,
      root: widget.cycle.root,
      onSubmit: (merchant, category) async {
        final wantsRename = merchant != t.merchant;
        final wantsCategoryChange = category != t.category;
        if (wantsRename) {
          await widget.client.bulkRename(from: t.merchant, to: merchant);
        }
        if (wantsCategoryChange) {
          final id = category == null
              ? null
              : categoryIdForName(widget.cycle.root, category);
          await widget.client.update(
            int.parse(t.id),
            categoryId: id,
            categoryExplicit: true,
          );
        }
        if (wantsRename || wantsCategoryChange) {
          await widget.onChanged();
        }
      },
      onDelete: () async {
        await widget.client.delete(int.parse(t.id));
        await widget.onChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return _DesktopExpenses(
            cycle: widget.cycle,
            unknown: _unknown,
            filtered: widget.transactions,
            total: _total,
            onAssign: _onAssign,
            onEditTransaction: _openEditModal,
            client: widget.client,
            onImported: widget.onChanged,
            aiEnabled: widget.aiEnabled,
            aiSpentUsd: widget.aiSpentUsd,
            onOpenCategories: widget.onOpenCategories,
            onOpenAccount: widget.onOpenAccount,
          );
        }
        return _MobileExpenses(
          cycle: widget.cycle,
          unknown: _unknown,
          known: _filtered,
          total: _total,
          search: _search,
          filterCat: _filterCat,
          onSearchChange: (v) => setState(() => _search = v),
          onFilterChange: (v) => setState(() => _filterCat = v),
          onAssign: _onAssign,
          onEditTransaction: _openEditModal,
          cycleLabels: widget.cycleLabels,
          onCycleChange: widget.onCycleChange,
          client: widget.client,
          onImported: widget.onChanged,
          aiEnabled: widget.aiEnabled,
          aiSpentUsd: widget.aiSpentUsd,
          onOpenCategories: widget.onOpenCategories,
          onOpenAccount: widget.onOpenAccount,
        );
      },
    );
  }
}

// ── Mobile ────────────────────────────────────────────────────────────────────

class _MobileExpenses extends StatelessWidget {
  const _MobileExpenses({
    required this.cycle,
    required this.unknown,
    required this.known,
    required this.total,
    required this.search,
    required this.filterCat,
    required this.onSearchChange,
    required this.onFilterChange,
    required this.onAssign,
    required this.onEditTransaction,
    required this.cycleLabels,
    required this.onCycleChange,
    required this.client,
    required this.onImported,
    required this.aiEnabled,
    required this.aiSpentUsd,
    required this.onOpenCategories,
    required this.onOpenAccount,
  });

  final BudgetCycle cycle;
  final List<Transaction> unknown;
  final List<Transaction> known;
  final double total;
  final String search;
  final String? filterCat;
  final ValueChanged<String> onSearchChange;
  final ValueChanged<String?> onFilterChange;
  final void Function(Transaction, String) onAssign;
  final ValueChanged<Transaction> onEditTransaction;
  final List<String> cycleLabels;
  final ValueChanged<String> onCycleChange;
  final TransactionsClient client;
  final Future<void> Function() onImported;
  final VoidCallback onOpenCategories;
  final VoidCallback onOpenAccount;
  final bool aiEnabled;
  final double aiSpentUsd;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — settings icon left (replaces page title), cycle picker right.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                MobileSettingsIcon(onTap: onOpenAccount),
                const Spacer(),
                CycleDropdown(
                  value: cycle.label,
                  options: cycleLabels,
                  onChange: onCycleChange,
                ),
              ],
            ),
          ),
          // Total
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BudgetLabel('This cycle'),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('\$${fmtMoney(total)}',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 28, fontWeight: FontWeight.w500,
                            letterSpacing: -0.02, color: bt.ink)),
                    const SizedBox(width: 10),
                    Text('${unknown.length + known.length} transactions',
                        style: TextStyle(fontSize: 13, color: bt.ink3)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Dropzone(
                    compact: true,
                    client: client,
                    onImported: onImported,
                    aiEnabled: aiEnabled,
                    aiSpentUsd: aiSpentUsd,
                    onOpenAccount: onOpenAccount,
                  ),
                  if (unknown.isEmpty && known.isEmpty) ...[
                    const SizedBox(height: 18),
                    _NoExpensesPanel(
                      cycleLabel: cycle.label,
                      hasCategories: cycle.root.children.any((c) => !c.isUnknown),
                      onOpenCategories: onOpenCategories,
                    ),
                  ] else ...[
                    if (unknown.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _SectionHeader(
                        icon: 'alert',
                        iconColor: bt.warn,
                        title: 'Needs review',
                        count: '${unknown.length} of ${unknown.length + known.length}',
                        bt: bt,
                      ),
                      const SizedBox(height: 8),
                      BudgetCard(
                        clipContent: true,
                        child: Column(
                          children: unknown.mapIndexed((i, t) => _TxnRow(
                            txn: t,
                            root: cycle.root,
                            showDivider: i > 0,
                            onAssign: onAssign,
                            onEdit: () => onEditTransaction(t),
                            onOpenCategories: onOpenCategories,
                          )).toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _SectionHeader(title: 'All transactions', count: '${known.length}', bt: bt),
                    const SizedBox(height: 8),
                    _SearchBar(
                      value: search,
                      onChanged: onSearchChange,
                      root: cycle.root,
                      filterCat: filterCat,
                      onFilterChange: onFilterChange,
                      bt: bt,
                    ),
                    const SizedBox(height: 8),
                    BudgetCard(
                      clipContent: true,
                      child: Column(
                        children: known.mapIndexed((i, t) => _TxnRow(
                          txn: t,
                          root: cycle.root,
                          showDivider: i > 0,
                          onAssign: onAssign,
                          onEdit: () => onEditTransaction(t),
                          onOpenCategories: onOpenCategories,
                        )).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sort state ────────────────────────────────────────────────────────────────

enum _SortCol { date, merchant, category, amount }
enum _SortDir { asc, desc }

int _parseDay(String date) {
  // ISO 'YYYY-MM-DD' — sort by the whole string lexicographically. Fallback
  // for legacy 'Mar 14' format: parse the day number.
  if (date.contains('-')) return 0;
  final parts = date.split(' ');
  return parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
}

// ── Desktop ───────────────────────────────────────────────────────────────────

class _DesktopExpenses extends StatefulWidget {
  const _DesktopExpenses({
    required this.cycle,
    required this.unknown,
    required this.filtered,
    required this.total,
    required this.onAssign,
    required this.onEditTransaction,
    required this.client,
    required this.onImported,
    required this.aiEnabled,
    required this.aiSpentUsd,
    required this.onOpenCategories,
    required this.onOpenAccount,
  });

  final BudgetCycle cycle;
  final List<Transaction> unknown;
  final List<Transaction> filtered;
  final double total;
  final void Function(Transaction, String) onAssign;
  final ValueChanged<Transaction> onEditTransaction;
  final TransactionsClient client;
  final Future<void> Function() onImported;
  final bool aiEnabled;
  final double aiSpentUsd;
  final VoidCallback onOpenCategories;
  final VoidCallback onOpenAccount;

  @override
  State<_DesktopExpenses> createState() => _DesktopExpensesState();
}

class _DesktopExpensesState extends State<_DesktopExpenses> {
  String _search = '';
  String? _filterCat;
  _SortCol _sortCol = _SortCol.date;
  _SortDir _sortDir = _SortDir.asc;

  void _onSort(_SortCol col) {
    setState(() {
      if (_sortCol == col) {
        _sortDir = _sortDir == _SortDir.asc ? _SortDir.desc : _SortDir.asc;
      } else {
        _sortCol = col;
        _sortDir = _SortDir.asc;
      }
    });
  }

  List<Transaction> get _tableRows {
    var list = widget.filtered;
    if (_search.isNotEmpty) {
      list = list.where((t) => t.merchant.toLowerCase().contains(_search.toLowerCase())).toList();
    }
    if (_filterCat != null) {
      list = list.where((t) => t.category == _filterCat).toList();
    }
    list = [...list]..sort((a, b) {
      final cmp = switch (_sortCol) {
        _SortCol.date     => a.date.contains('-')
                                ? a.date.compareTo(b.date)
                                : _parseDay(a.date).compareTo(_parseDay(b.date)),
        _SortCol.merchant => a.merchant.compareTo(b.merchant),
        _SortCol.category => (a.category ?? '￿').compareTo(b.category ?? '￿'),
        _SortCol.amount   => a.amount.compareTo(b.amount),
      };
      return _sortDir == _SortDir.asc ? cmp : -cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Column(
      children: [
        // Top strip
        Container(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bt.rule))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BudgetLabel('Expenses'),
                    const SizedBox(height: 4),
                    Text(widget.cycle.label,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 30,
                            letterSpacing: -0.025, color: bt.ink)),
                    const SizedBox(height: 4),
                    Text('Real transactions from your linked statements.',
                        style: TextStyle(fontSize: 13, color: bt.ink3)),
                  ],
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                BudgetLabel('Unknown'),
                const SizedBox(height: 2),
                Text('${widget.unknown.length}',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 18,
                        fontWeight: FontWeight.w500, color: bt.warn)),
              ]),
              const SizedBox(width: 28),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                BudgetLabel('Total spent'),
                const SizedBox(height: 2),
                Text('\$${fmtMoney(widget.total)}',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 30,
                        fontWeight: FontWeight.w500, letterSpacing: -0.02, color: bt.ink)),
              ]),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              // Left aside
              Container(
                width: 340,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: bt.rule))),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BudgetLabel('Import'),
                    const SizedBox(height: 8),
                    Dropzone(
                      client: widget.client,
                      onImported: widget.onImported,
                      aiEnabled: widget.aiEnabled,
                      aiSpentUsd: widget.aiSpentUsd,
                      onOpenAccount: widget.onOpenAccount,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        BudgetIcons.build('alert', size: 14, strokeWidth: 2, color: bt.warn),
                        const SizedBox(width: 8),
                        Text('Needs review',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: bt.ink)),
                        const Spacer(),
                        Text('${widget.unknown.length} unknown',
                            style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: bt.ink4)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: BudgetCard(
                        clipContent: true,
                        child: widget.unknown.isEmpty
                            ? SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text('Nothing to review. Nice.',
                                      style: TextStyle(fontSize: 12.5, color: bt.ink4),
                                      textAlign: TextAlign.center),
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  children: widget.unknown.mapIndexed((i, t) => _TxnRow(
                                    txn: t,
                                    root: widget.cycle.root,
                                    showDivider: i > 0,
                                    onAssign: widget.onAssign,
                                    onEdit: () => widget.onEditTransaction(t),
                                    onOpenCategories: widget.onOpenCategories,
                                  )).toList(),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              // Main table
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('All transactions',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: bt.ink)),
                      const SizedBox(height: 10),
                      _SearchBar(
                        value: _search,
                        onChanged: (v) => setState(() => _search = v),
                        root: widget.cycle.root,
                        filterCat: _filterCat,
                        onFilterChange: (v) => setState(() => _filterCat = v),
                        bt: bt,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: BudgetCard(
                          clipContent: true,
                          child: Column(
                            children: [
                              _TableHeader(
                                bt: bt,
                                sortCol: _sortCol,
                                sortDir: _sortDir,
                                onSort: _onSort,
                              ),
                              Expanded(
                                child: _tableRows.isEmpty
                                    ? _NoExpensesPanel(
                                        cycleLabel: widget.cycle.label,
                                        hasCategories: widget.cycle.root.children
                                            .any((c) => !c.isUnknown),
                                        onOpenCategories: widget.onOpenCategories,
                                        embedded: true,
                                      )
                                    : SingleChildScrollView(
                                        child: Column(
                                          children: _tableRows.mapIndexed((i, t) => _TableRow(
                                            txn: t,
                                            root: widget.cycle.root,
                                            onAssign: widget.onAssign,
                                            onEdit: () => widget.onEditTransaction(t),
                                            onOpenCategories: widget.onOpenCategories,
                                            bt: bt,
                                          )).toList(),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Shared row components ─────────────────────────────────────────────────────

class _TxnRow extends StatelessWidget {
  const _TxnRow({
    required this.txn,
    required this.root,
    required this.showDivider,
    required this.onAssign,
    required this.onEdit,
    required this.onOpenCategories,
  });

  final Transaction txn;
  final BudgetCategory root;
  final bool showDivider;
  final void Function(Transaction, String) onAssign;
  final VoidCallback onEdit;
  final VoidCallback onOpenCategories;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Column(
      children: [
        if (showDivider) Divider(height: 1, color: bt.rule),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _EditPencil(onTap: onEdit, bt: bt),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(txn.merchant,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: bt.ink),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${txn.date} · \$${fmtMoneyDecimal(txn.amount)}',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: bt.ink4)),
                  ],
                ),
              ),
              CategoryChip(
                value: txn.category,
                root: root,
                onChange: (cat) => onAssign(txn, cat),
                onOpenCategories: onOpenCategories,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditPencil extends StatelessWidget {
  const _EditPencil({required this.onTap, required this.bt});
  final VoidCallback onTap;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bt.surface,
          border: Border.all(color: bt.ruleStrong),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        alignment: Alignment.center,
        child: BudgetIcons.build('edit',
            size: 13, strokeWidth: 1.8, color: bt.ink2),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.bt,
    required this.sortCol,
    required this.sortDir,
    required this.onSort,
  });
  final BudgetTheme bt;
  final _SortCol sortCol;
  final _SortDir sortDir;
  final ValueChanged<_SortCol> onSort;

  @override
  Widget build(BuildContext context) {
    Widget col(_SortCol c, String label, {double? width, bool rightAlign = false}) {
      final cell = _SortableHeader(
        label: label, col: c,
        sortCol: sortCol, sortDir: sortDir,
        onSort: onSort, bt: bt,
        rightAlign: rightAlign,
      );
      if (width != null) return SizedBox(width: width, child: cell);
      return Expanded(child: cell);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bt.rule))),
      child: Row(
        children: [
          // Reserve the same width the row uses for its leading edit pencil
          // (28) + spacing (10) so column headers line up with row columns.
          const SizedBox(width: 38),
          col(_SortCol.date,     'Date',     width: 88),
          col(_SortCol.merchant, 'Merchant'),
          col(_SortCol.category, 'Category', width: 180),
          col(_SortCol.amount,   'Amount',   width: 100, rightAlign: true),
        ],
      ),
    );
  }
}

class _SortableHeader extends StatefulWidget {
  const _SortableHeader({
    required this.label,
    required this.col,
    required this.sortCol,
    required this.sortDir,
    required this.onSort,
    required this.bt,
    this.rightAlign = false,
  });
  final String label;
  final _SortCol col;
  final _SortCol sortCol;
  final _SortDir sortDir;
  final ValueChanged<_SortCol> onSort;
  final BudgetTheme bt;
  final bool rightAlign;

  @override
  State<_SortableHeader> createState() => _SortableHeaderState();
}

class _SortableHeaderState extends State<_SortableHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.col == widget.sortCol;
    final labelColor = active ? widget.bt.ink2 : (_hovered ? widget.bt.ink3 : widget.bt.ink4);
    final iconKey = active
        ? (widget.sortDir == _SortDir.asc ? 'chevron-up' : 'chevron-down')
        : (_hovered ? 'chevron-down' : null);
    final iconColor = active
        ? widget.bt.ink3
        : widget.bt.ink4.withValues(alpha: 0.5);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onSort(widget.col),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              widget.rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Text(
              widget.label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.12 * 10.5,
                color: labelColor,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (iconKey != null) ...[
              const SizedBox(width: 3),
              BudgetIcons.build(iconKey, size: 10, strokeWidth: 2.2, color: iconColor),
            ],
          ],
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.txn,
    required this.root,
    required this.onAssign,
    required this.onEdit,
    required this.onOpenCategories,
    required this.bt,
  });

  final Transaction txn;
  final BudgetCategory root;
  final void Function(Transaction, String) onAssign;
  final VoidCallback onEdit;
  final VoidCallback onOpenCategories;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bt.ruleSoft))),
      child: Row(
        children: [
          _EditPencil(onTap: onEdit, bt: bt),
          const SizedBox(width: 10),
          SizedBox(
            width: 88,
            child: Text(txn.date,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: bt.ink3)),
          ),
          Expanded(
            child: Text(txn.merchant,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: bt.ink),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 180,
            child: CategoryChip(
              value: txn.category,
              root: root,
              onChange: (cat) => onAssign(txn, cat),
              onOpenCategories: onOpenCategories,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text('\$${fmtMoneyDecimal(txn.amount)}',
                style: TextStyle(fontFamily: 'monospace', fontSize: 14,
                    fontWeight: FontWeight.w500, color: bt.ink),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _NoExpensesPanel extends StatefulWidget {
  /// Shown when the current cycle has zero transactions. The mobile layout
  /// uses the standalone (`embedded: false`) form below the dropzone; the
  /// desktop table card uses `embedded: true` to fill the remaining space
  /// inside an already-bordered container.
  const _NoExpensesPanel({
    required this.cycleLabel,
    required this.hasCategories,
    required this.onOpenCategories,
    this.embedded = false,
  });

  final String cycleLabel;
  final bool hasCategories;
  final VoidCallback onOpenCategories;
  final bool embedded;

  @override
  State<_NoExpensesPanel> createState() => _NoExpensesPanelState();
}

class _NoExpensesPanelState extends State<_NoExpensesPanel> {
  // The recognizer drives the inline "Categories" tap target inside the
  // RichText body. Created in initState so it survives rebuilds and gets
  // disposed when the widget goes away — without this, hot-reload + frequent
  // rebuilds would leak gesture recognizers.
  late final TapGestureRecognizer _categoriesTap = TapGestureRecognizer()
    ..onTap = () => widget.onOpenCategories();

  @override
  void dispose() {
    _categoriesTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final title = widget.hasCategories
        ? 'No expenses in ${widget.cycleLabel}'
        : 'No expenses yet';

    final bodyStyle = TextStyle(fontSize: 12.5, color: bt.ink4, height: 1.5);
    final linkStyle = bodyStyle.copyWith(
      color: bt.ink2,
      fontWeight: FontWeight.w600,
    );

    final body = widget.hasCategories
        // No clickable link in the "categories exist" case — just prose.
        ? Text(
            'Drop a CSV statement above to import — or use the cycle picker '
            'to jump to a month that has data.',
            textAlign: TextAlign.center,
            style: bodyStyle,
          )
        : Text.rich(
            TextSpan(
              style: bodyStyle,
              children: [
                const TextSpan(text: 'Add a category in the '),
                TextSpan(
                  text: 'Categories',
                  style: linkStyle,
                  recognizer: _categoriesTap,
                ),
                const TextSpan(
                  text: ' tab first, then drop a statement above. '
                      'The AI auto-categorizer needs somewhere to file things.',
                ),
              ],
            ),
            textAlign: TextAlign.center,
          );

    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bt.surface2,
              border: Border.all(color: bt.ruleStrong),
              borderRadius: const BorderRadius.all(Radius.circular(12)),
            ),
            alignment: Alignment.center,
            child: BudgetIcons.build('expenses',
                size: 18, strokeWidth: 1.6, color: bt.ink3),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: bt.ink2,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: body,
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return Center(child: inner);
    }
    return BudgetCard(child: inner);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title, required this.count, required this.bt,
    this.icon, this.iconColor,
  });
  final String title, count;
  final BudgetTheme bt;
  final String? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          if (icon != null) ...[
            BudgetIcons.build(icon!, size: 14, strokeWidth: 2, color: iconColor ?? bt.ink),
            const SizedBox(width: 8),
          ],
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: bt.ink)),
          const Spacer(),
          Text(count, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: bt.ink4)),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.value,
    required this.onChanged,
    required this.root,
    required this.filterCat,
    required this.onFilterChange,
    required this.bt,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final BudgetCategory root;
  final String? filterCat;
  final ValueChanged<String?> onFilterChange;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: bt.surface2,
            borderRadius: BudgetRadius.inputBR,
            border: Border.all(color: bt.ruleStrong),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 11),
                child: BudgetIcons.build('search', size: 15, strokeWidth: 1.8, color: bt.ink4),
              ),
              Expanded(
                child: TextField(
                  onChanged: onChanged,
                  style: TextStyle(fontSize: 13, color: bt.ink),
                  decoration: InputDecoration(
                    hintText: 'Search merchant',
                    hintStyle: TextStyle(color: bt.ink4),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _CategoryDropdown(
          root: root,
          value: filterCat,
          onChanged: onFilterChange,
          bt: bt,
        ),
      ],
    );
  }
}

class _CategoryDropdown extends StatefulWidget {
  const _CategoryDropdown({
    required this.root, required this.value,
    required this.onChanged, required this.bt,
  });

  final BudgetCategory root;
  final String? value;
  final ValueChanged<String?> onChanged;
  final BudgetTheme bt;

  @override
  State<_CategoryDropdown> createState() => _CategoryDropdownState();
}

class _CategoryDropdownState extends State<_CategoryDropdown> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _open(BuildContext context) {
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (_) => _FilterOverlay(
        link: _link,
        bt: widget.bt,
        allCats: leafCategoriesOf(widget.root),
        current: widget.value,
        onSelect: (v) { widget.onChanged(v); _close(); },
        onDismiss: _close,
      ),
    );
    overlay.insert(_entry!);
    setState(() {});
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _entry != null;
    final hasCat = widget.value != null;
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: open ? _close : () => _open(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(
            color: hasCat ? widget.bt.surface : widget.bt.surface2,
            borderRadius: BudgetRadius.inputBR,
            border: Border.all(color: widget.bt.ruleStrong),
          ),
          child: Row(
            children: [
              BudgetIcons.build('filter', size: 13, strokeWidth: 1.7,
                  color: hasCat ? widget.bt.ink3 : widget.bt.ink4),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.value ?? 'All categories',
                  style: TextStyle(
                    fontSize: 13,
                    color: hasCat ? widget.bt.ink : widget.bt.ink3,
                    fontWeight: hasCat ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              if (hasCat)
                GestureDetector(
                  onTap: () { widget.onChanged(null); _close(); },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: BudgetIcons.build('x', size: 13, strokeWidth: 2, color: widget.bt.ink3),
                  ),
                )
              else
                BudgetIcons.build(
                  open ? 'chevron-up' : 'chevron-down',
                  size: 13, strokeWidth: 2, color: widget.bt.ink4,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterOverlay extends StatefulWidget {
  const _FilterOverlay({
    required this.link,
    required this.bt,
    required this.allCats,
    required this.current,
    required this.onSelect,
    required this.onDismiss,
  });

  final LayerLink link;
  final BudgetTheme bt;
  final List<({String name, String group})> allCats;
  final String? current;
  final ValueChanged<String?> onSelect;
  final VoidCallback onDismiss;

  @override
  State<_FilterOverlay> createState() => _FilterOverlayState();
}

class _FilterOverlayState extends State<_FilterOverlay> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.allCats
        : widget.allCats
            .where((c) =>
                c.name.toLowerCase().contains(_search.toLowerCase()) ||
                c.group.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDismiss,
      child: Stack(
        children: [
          CompositedTransformFollower(
            link: widget.link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 4),
            child: GestureDetector(
              onTap: () {},
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 260,
                  constraints: const BoxConstraints(maxHeight: 340),
                  decoration: BoxDecoration(
                    color: widget.bt.surface,
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                    border: Border.all(color: widget.bt.ruleStrong),
                    boxShadow: const [
                      BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FilterSearchField(
                          bt: widget.bt,
                          onChanged: (v) => setState(() => _search = v),
                        ),
                        Divider(height: 1, color: widget.bt.rule),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                if (_search.isEmpty)
                                  _FilterRow(
                                    label: 'All categories',
                                    active: widget.current == null,
                                    bt: widget.bt,
                                    onTap: () => widget.onSelect(null),
                                  ),
                                if (filtered.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 14),
                                    child: Text('No match',
                                        style: TextStyle(
                                            fontSize: 12.5, color: widget.bt.ink4)),
                                  )
                                else
                                  ...filtered.map((c) => _FilterRow(
                                        label: c.name,
                                        sublabel: c.group != c.name ? c.group : null,
                                        active: widget.current == c.name,
                                        bt: widget.bt,
                                        onTap: () => widget.onSelect(c.name),
                                      )),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSearchField extends StatelessWidget {
  const _FilterSearchField({required this.bt, required this.onChanged});
  final BudgetTheme bt;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Row(
          children: [
            BudgetIcons.build('search', size: 13, strokeWidth: 1.8, color: bt.ink4),
            const SizedBox(width: 7),
            Expanded(
              child: TextField(
                autofocus: true,
                onChanged: onChanged,
                style: TextStyle(fontSize: 13, color: bt.ink),
                decoration: InputDecoration(
                  hintText: 'Filter by category…',
                  hintStyle: TextStyle(color: bt.ink4),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 2),
                ),
              ),
            ),
          ],
        ),
      );
}

class _FilterRow extends StatefulWidget {
  const _FilterRow({
    required this.label,
    this.sublabel,
    required this.active,
    required this.bt,
    required this.onTap,
  });
  final String label;
  final String? sublabel;
  final bool active;
  final BudgetTheme bt;
  final VoidCallback onTap;

  @override
  State<_FilterRow> createState() => _FilterRowState();
}

class _FilterRowState extends State<_FilterRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? widget.bt.surface2 : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.active ? widget.bt.ink : widget.bt.ink2,
                      fontWeight:
                          widget.active ? FontWeight.w500 : FontWeight.w400,
                    )),
              ),
              if (widget.sublabel != null)
                Text(widget.sublabel!,
                    style: TextStyle(fontSize: 11, color: widget.bt.ink4)),
              if (widget.active) ...[
                const SizedBox(width: 6),
                BudgetIcons.build('check', size: 13, strokeWidth: 2,
                    color: widget.bt.ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension _IndexedMap<T> on List<T> {
  List<R> mapIndexed<R>(R Function(int i, T e) fn) =>
      List.generate(length, (i) => fn(i, this[i]));
}
