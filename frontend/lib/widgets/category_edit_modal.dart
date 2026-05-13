import 'package:flutter/material.dart';
import '../models/budget_category.dart';
import '../theme/app_theme.dart';
import 'cat_icon.dart';
import 'glass.dart';

/// Add/edit/delete dialog for a category. Adapted from the original
/// `HFEditModal` prototype but trimmed to fit the simplified data model:
/// name + parent + delete (no icon, amount, or description).
class CategoryEditModal extends StatefulWidget {
  const CategoryEditModal._({
    required this.mode,
    required this.root,
    required this.initialName,
    required this.initialDescription,
    required this.initialParent,
    required this.initialColor,
    required this.target,
    required this.onSubmit,
    required this.onDelete,
  });

  /// Open as "create a child of [parent]".
  static Future<void> showCreate({
    required BuildContext context,
    required BudgetCategory root,
    required BudgetCategory parent,
    required Future<void> Function(BudgetCategory newParent, String name, String? description, String color) onSubmit,
  }) {
    return showDialog(
      context: context,
      barrierColor: const Color(0x8C080614),
      builder: (_) => CategoryEditModal._(
        mode: CategoryEditMode.create,
        root: root,
        initialName: '',
        initialDescription: '',
        initialParent: parent,
        initialColor: CategoryPalette.defaultKey,
        target: null,
        onSubmit: onSubmit,
        onDelete: null,
      ),
    );
  }

  /// Open as "edit [target]". `target` must not be the root or `isUnknown`.
  static Future<void> showEdit({
    required BuildContext context,
    required BudgetCategory root,
    required BudgetCategory target,
    required BudgetCategory currentParent,
    required Future<void> Function(BudgetCategory newParent, String name, String? description, String color) onSubmit,
    required Future<void> Function() onDelete,
  }) {
    return showDialog(
      context: context,
      barrierColor: const Color(0x8C080614),
      builder: (_) => CategoryEditModal._(
        mode: CategoryEditMode.edit,
        root: root,
        initialName: target.name,
        initialDescription: target.description ?? '',
        initialParent: currentParent,
        initialColor: target.color,
        target: target,
        onSubmit: onSubmit,
        onDelete: onDelete,
      ),
    );
  }

  final CategoryEditMode mode;
  final BudgetCategory root;
  final String initialName;
  final String initialDescription;
  final BudgetCategory initialParent;
  final String initialColor;
  final BudgetCategory? target;
  final Future<void> Function(BudgetCategory newParent, String name, String? description, String color) onSubmit;
  final Future<void> Function()? onDelete;

  @override
  State<CategoryEditModal> createState() => _CategoryEditModalState();
}

enum CategoryEditMode { create, edit }


class _CategoryEditModalState extends State<CategoryEditModal> {
  late TextEditingController _name;
  late TextEditingController _description;
  late BudgetCategory _parent;
  late String _color;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName)
      ..addListener(_onTextChanged);
    _description = TextEditingController(text: widget.initialDescription)
      ..addListener(_onTextChanged);
    _parent = widget.initialParent;
    _color = widget.initialColor;
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _name.removeListener(_onTextChanged);
    _description.removeListener(_onTextChanged);
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final name = _name.text.trim();
    final desc = _description.text.trim();
    if (name.isEmpty || desc.isEmpty) return false;
    if (widget.mode == CategoryEditMode.create) return true;
    final nameChanged = name != widget.initialName.trim();
    final descChanged = desc != widget.initialDescription.trim();
    final parentChanged = _parent != widget.initialParent;
    final colorChanged = _color != widget.initialColor;
    return nameChanged || descChanged || parentChanged || colorChanged;
  }

  /// All categories that could legally be a parent — root + every non-leaf,
  /// non-Unknown descendant — minus the target itself and its own subtree
  /// (can't make a node its own ancestor).
  List<BudgetCategory> _parentCandidates() {
    final out = <BudgetCategory>[widget.root];
    final excluded = <BudgetCategory>{};
    if (widget.target != null) {
      _collect(widget.target!, excluded);
    }
    void walk(BudgetCategory n) {
      for (final c in n.children) {
        if (c.isUnknown || excluded.contains(c)) continue;
        out.add(c);
        walk(c);
      }
    }
    walk(widget.root);
    return out;
  }

  void _collect(BudgetCategory n, Set<BudgetCategory> out) {
    out.add(n);
    for (final c in n.children) {
      _collect(c, out);
    }
  }

  String _pathOf(BudgetCategory node) {
    if (node == widget.root) return 'Budget';
    final stack = <String>[];
    bool found = false;
    void walk(BudgetCategory n) {
      if (found) return;
      if (n == node) {
        stack.add(n.name);
        found = true;
        return;
      }
      for (final c in n.children) {
        walk(c);
        if (found) {
          if (n != widget.root) stack.add(n.name);
          return;
        }
      }
    }
    walk(widget.root);
    return stack.reversed.join(' / ');
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    final d = _description.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_parent, n, d.isEmpty ? null : d, _color);
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
    final fn = widget.onDelete;
    if (fn == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
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
    final isCreate = widget.mode == CategoryEditMode.create;

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
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: bt.glassBorder)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isCreate ? 'New category' : 'Edit category',
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
                        child: TextField(
                          controller: _name,
                          autofocus: true,
                          onSubmitted: (_) => _save(),
                          style: TextStyle(fontSize: 14, color: bt.ink),
                          decoration: _inputDecoration(
                            bt: bt,
                            hint: isCreate ? 'e.g. Subscriptions' : '',
                          ),
                        ),
                      ),
                      _Field(
                        label: 'Description',
                        sub:
                            'Helps the AI assistant categorise expenses into this bucket.',
                        child: TextField(
                          controller: _description,
                          minLines: 2,
                          maxLines: 4,
                          style: TextStyle(fontSize: 14, color: bt.ink),
                          decoration: _inputDecoration(
                            bt: bt,
                            hint: 'What kinds of expenses belong here?',
                          ),
                        ),
                      ),
                      _Field(
                        label: 'Color',
                        child: _ColorPicker(
                          selected: _color,
                          onChange: (k) => setState(() => _color = k),
                          bt: bt,
                        ),
                      ),
                      _Field(
                        label: isCreate ? 'Parent category' : 'Move to',
                        child: _ParentDropdown(
                          options: _parentCandidates(),
                          current: _parent,
                          pathOf: _pathOf,
                          onChange: (p) {
                            setState(() => _parent = p);
                          },
                          bt: bt,
                        ),
                      ),
                      if (!isCreate && widget.onDelete != null) ...[
                        const SizedBox(height: 6),
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
                                        'Delete "${widget.target?.name ?? ''}"',
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
                              const SizedBox(height: 6),
                              Text(
                                'Transactions in this bucket will move to Unknown.',
                                style: TextStyle(
                                    fontSize: 11.5, color: bt.ink4),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                decoration: BoxDecoration(
                  color: bt.glass1,
                  border: Border(top: BorderSide(color: bt.glassBorder)),
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
                          label: _busy
                              ? 'Saving…'
                              : (isCreate ? 'Create category' : 'Save changes'),
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
                style: TextStyle(fontSize: 11.5, color: bt.ink4),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.selected,
    required this.onChange,
    required this.bt,
  });

  final String selected;
  final ValueChanged<String> onChange;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in CategoryPalette.keys)
          _Swatch(
            colorKey: key,
            selected: key == selected,
            onTap: () => onChange(key),
            bt: bt,
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colorKey,
    required this.selected,
    required this.onTap,
    required this.bt,
  });

  final String colorKey;
  final bool selected;
  final VoidCallback onTap;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    final bg = context.categoryBg(colorKey);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? bt.ink : bt.ruleStrong,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _ParentDropdown extends StatelessWidget {
  const _ParentDropdown({
    required this.options,
    required this.current,
    required this.pathOf,
    required this.onChange,
    required this.bt,
  });

  final List<BudgetCategory> options;
  final BudgetCategory current;
  final String Function(BudgetCategory) pathOf;
  final ValueChanged<BudgetCategory> onChange;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bt.fieldBg,
        border: Border.all(color: bt.fieldBorder),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BudgetCategory>(
          value: current,
          isExpanded: true,
          icon: BudgetIcons.build('chevron-down',
              size: 14, strokeWidth: 1.6, color: bt.ink3),
          dropdownColor: bt.bg,
          style: TextStyle(fontSize: 14, color: bt.ink),
          onChanged: (v) {
            if (v != null) onChange(v);
          },
          items: options
              .map((c) => DropdownMenuItem<BudgetCategory>(
                    value: c,
                    child: Text(
                      pathOf(c),
                      style: TextStyle(fontSize: 14, color: bt.ink),
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
    return GlassButton(
      label: label,
      onPressed: onTap,
      variant: GlassButtonVariant.secondary,
      compact: true,
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
    return GlassButton(
      label: label,
      onPressed: onTap,
      variant: GlassButtonVariant.primary,
      compact: true,
    );
  }
}
