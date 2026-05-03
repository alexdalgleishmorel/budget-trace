import 'package:flutter/material.dart';
import '../models/budget_category.dart';
import '../models/transaction.dart';
import '../theme/app_theme.dart';
import '../utils/leaf_categories.dart';
import 'cat_icon.dart';

/// Edit dialog for a single transaction. Allows renaming the merchant
/// (which the parent applies to every transaction sharing that exact name),
/// changing the category, or deleting the transaction outright.
class TransactionEditModal extends StatefulWidget {
  const TransactionEditModal._({
    required this.transaction,
    required this.root,
    required this.onSubmit,
    required this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    required Transaction transaction,
    required BudgetCategory root,
    required Future<void> Function(String merchant, String? category) onSubmit,
    required Future<void> Function() onDelete,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => TransactionEditModal._(
        transaction: transaction,
        root: root,
        onSubmit: onSubmit,
        onDelete: onDelete,
      ),
    );
  }

  final Transaction transaction;
  final BudgetCategory root;
  final Future<void> Function(String merchant, String? category) onSubmit;
  final Future<void> Function() onDelete;

  @override
  State<TransactionEditModal> createState() => _TransactionEditModalState();
}

class _TransactionEditModalState extends State<TransactionEditModal> {
  late TextEditingController _merchant;
  late String? _category;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _merchant = TextEditingController(text: widget.transaction.merchant)
      ..addListener(_onChanged);
    _category = widget.transaction.category;
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _merchant.removeListener(_onChanged);
    _merchant.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final m = _merchant.text.trim();
    if (m.isEmpty) return false;
    final merchantChanged = m != widget.transaction.merchant.trim();
    final categoryChanged = _category != widget.transaction.category;
    return merchantChanged || categoryChanged;
  }

  Future<void> _save() async {
    final m = _merchant.text.trim();
    if (m.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(m, _category);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDelete();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final leaves = leafCategoriesOf(widget.root);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Material(
          color: bt.surface,
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: bt.rule)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Edit expense',
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
              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Field(
                        label: 'Name',
                        sub:
                            'Renaming this expense will also rename every other expense sharing the exact same name.',
                        child: TextField(
                          controller: _merchant,
                          autofocus: true,
                          onSubmitted: (_) => _save(),
                          style: TextStyle(fontSize: 14, color: bt.ink),
                          decoration: _inputDecoration(bt: bt),
                        ),
                      ),
                      _Field(
                        label: 'Category',
                        child: _CategoryDropdown(
                          leaves: leaves,
                          current: _category,
                          onChange: (c) => setState(() => _category = c),
                          bt: bt,
                        ),
                      ),
                      // Amount + date readout (read-only context)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: bt.surface2,
                          borderRadius: const BorderRadius.all(Radius.circular(10)),
                          border: Border.all(color: bt.ruleSoft),
                        ),
                        child: Row(
                          children: [
                            Text(widget.transaction.date,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12.5,
                                    color: bt.ink3)),
                            const Spacer(),
                            Text(
                              '\$${widget.transaction.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: bt.ink2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.only(top: 18),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: bt.ruleStrong, width: 1),
                          ),
                        ),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: _busy ? null : _delete,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: bt.negBg,
                                  border: Border.all(color: bt.negBorder),
                                  borderRadius:
                                      const BorderRadius.all(Radius.circular(12)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    BudgetIcons.build('trash',
                                        size: 15,
                                        strokeWidth: 1.8,
                                        color: bt.neg),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Delete expense',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: bt.neg,
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
                  ),
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                decoration: BoxDecoration(
                  color: bt.surface2,
                  border: Border(top: BorderSide(color: bt.rule)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _error!,
                          style: TextStyle(fontSize: 12, color: bt.neg),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _GhostButton(
                          label: 'Cancel',
                          onTap: _busy ? null : () => Navigator.of(context).pop(),
                          bt: bt,
                        ),
                        const SizedBox(width: 8),
                        _PrimaryButton(
                          label: _busy ? 'Saving…' : 'Save changes',
                          onTap: (_busy || !_canSubmit) ? null : _save,
                          bt: bt,
                        ),
                      ],
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

InputDecoration _inputDecoration({required BudgetTheme bt, String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: bt.ink4),
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    filled: true,
    fillColor: bt.surface2,
    border: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: bt.ruleStrong),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: bt.ruleStrong),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: bt.ink),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.sub});
  final String label;
  final Widget child;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.12 * 10.5,
                color: bt.ink4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          child,
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                sub!,
                style: TextStyle(fontSize: 11.5, color: bt.ink4, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.leaves,
    required this.current,
    required this.onChange,
    required this.bt,
  });

  final List<({String name, String group})> leaves;
  final String? current;
  final ValueChanged<String?> onChange;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    final values = <String?>[null, ...leaves.map((l) => l.name)];
    // Make sure the current value (if non-null) appears in the list — defensive
    // in case a transaction was tagged with a category that no longer exists.
    if (current != null && !values.contains(current)) {
      values.add(current);
    }

    String labelFor(String? v) {
      if (v == null) return 'Unassigned';
      final match = leaves.where((l) => l.name == v).toList();
      if (match.isEmpty) return v;
      return '${match.first.group} / ${match.first.name}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bt.surface2,
        border: Border.all(color: bt.ruleStrong),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: current,
          isExpanded: true,
          icon: BudgetIcons.build('chevron-down',
              size: 14, strokeWidth: 2, color: bt.ink3),
          dropdownColor: bt.surface,
          style: TextStyle(fontSize: 14, color: bt.ink),
          onChanged: onChange,
          items: values
              .map((v) => DropdownMenuItem<String?>(
                    value: v,
                    child: Text(
                      labelFor(v),
                      style: TextStyle(
                          fontSize: 14,
                          color: v == null ? bt.ink3 : bt.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap, required this.bt});
  final String label;
  final VoidCallback? onTap;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: bt.surface,
            border: Border.all(color: bt.ruleStrong),
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: bt.ink2),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap, required this.bt});
  final String label;
  final VoidCallback? onTap;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: bt.ink,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: bt.bg),
          ),
        ),
      ),
    );
  }
}
