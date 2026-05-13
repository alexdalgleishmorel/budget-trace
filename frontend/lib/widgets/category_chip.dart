import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/budget_category.dart';
import '../theme/app_theme.dart';
import '../utils/leaf_categories.dart';
import 'cat_icon.dart';
import 'glass.dart';

class CategoryChip extends StatefulWidget {
  const CategoryChip({
    super.key,
    required this.value,
    required this.root,
    required this.onChange,
    required this.onOpenCategories,
  });

  final String? value;
  final BudgetCategory root;
  final ValueChanged<String> onChange;

  /// Switches the AppShell to the Categories tab. Surfaced from the
  /// "Need a new bucket? Create it in Categories" footer in the picker
  /// overlay.
  final VoidCallback onOpenCategories;

  @override
  State<CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<CategoryChip> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  List<AssignableCategory> get _allCats => assignableCategoriesOf(widget.root);

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _openPicker(BuildContext context) {
    final bt = Theme.of(context).extension<BudgetTheme>()!;
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (_) => _PickerOverlay(
        link: _link,
        bt: bt,
        allCats: _allCats,
        onSelect: (name) {
          widget.onChange(name);
          _close();
        },
        onDismiss: _close,
        onOpenCategories: () {
          _close();
          widget.onOpenCategories();
        },
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
    final bt = context.bt;
    final unknown = widget.value == null;
    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unknown) ...[
          BudgetIcons.build('alert',
              size: 12, strokeWidth: 1.8, color: bt.warn),
          const SizedBox(width: 6),
        ],
        Text(
          widget.value ?? 'Needs category',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: unknown ? bt.warn : bt.ink2,
          ),
        ),
        const SizedBox(width: 4),
        BudgetIcons.build('chevron-down', size: 12, strokeWidth: 1.8,
            color: (unknown ? bt.warn : bt.ink2).withValues(alpha: 0.55)),
      ],
    );
    final body = Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      child: inner,
    );
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: () => _openPicker(context),
        child: unknown
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BudgetRadius.chipBR,
                  color: bt.warnBg,
                  border: Border.all(color: bt.warn.withValues(alpha: 0.55)),
                ),
                child: body,
              )
            : GlassSurface(
                tier: GlassTier.t2,
                radius: 999,
                elevated: false,
                sheen: false,
                child: body,
              ),
      ),
    );
  }
}

// ── Picker overlay ────────────────────────────────────────────────────────────

class _PickerOverlay extends StatefulWidget {
  const _PickerOverlay({
    required this.link,
    required this.bt,
    required this.allCats,
    required this.onSelect,
    required this.onDismiss,
    required this.onOpenCategories,
  });

  final LayerLink link;
  final BudgetTheme bt;
  final List<AssignableCategory> allCats;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;
  final VoidCallback onOpenCategories;

  @override
  State<_PickerOverlay> createState() => _PickerOverlayState();
}

class _PickerOverlayState extends State<_PickerOverlay> {
  String _search = '';

  // Tap target for the inline "Categories" link in the footer. Created once
  // and disposed in [dispose] — leaving it as a per-build TapGestureRecognizer
  // would leak each time the chip rebuilds.
  late final TapGestureRecognizer _categoriesTap = TapGestureRecognizer()
    ..onTap = () => widget.onOpenCategories();

  @override
  void dispose() {
    _categoriesTap.dispose();
    super.dispose();
  }

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
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 6),
            child: GestureDetector(
              onTap: () {},
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 240,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: GlassSurface(
                      tier: GlassTier.strong,
                      radius: 14,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SearchField(
                            bt: widget.bt,
                            onChanged: (v) => setState(() => _search = v),
                          ),
                          Divider(height: 1, color: widget.bt.glassBorder),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                children: filtered.isEmpty
                                    ? [_EmptyState(bt: widget.bt)]
                                    : filtered
                                        .map((c) => _PickerRow(
                                              cat: c,
                                              bt: widget.bt,
                                              onTap: () => widget.onSelect(c.path),
                                            ))
                                        .toList(),
                              ),
                            ),
                          ),
                          Divider(height: 1, color: widget.bt.glassBorder),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                    fontSize: 11.5, color: widget.bt.ink4),
                                children: [
                                  const TextSpan(
                                      text:
                                          'Need a new bucket? Create it in '),
                                  TextSpan(
                                    text: 'Categories',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: widget.bt.ink2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    recognizer: _categoriesTap,
                                  ),
                                  const TextSpan(text: '.'),
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
          ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.bt, required this.onChanged});
  final BudgetTheme bt;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
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
                hintText: 'Search categories…',
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.bt});
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Text('No match', style: TextStyle(fontSize: 12.5, color: bt.ink4)),
      );
}

class _PickerRow extends StatefulWidget {
  const _PickerRow({required this.cat, required this.bt, required this.onTap});
  final AssignableCategory cat;
  final BudgetTheme bt;
  final VoidCallback onTap;

  @override
  State<_PickerRow> createState() => _PickerRowState();
}

class _PickerRowState extends State<_PickerRow> {
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.cat.name,
                    style: TextStyle(fontSize: 13, color: widget.bt.ink)),
              ),
              if (widget.cat.group != widget.cat.name)
                Text(widget.cat.group,
                    style: TextStyle(fontSize: 11, color: widget.bt.ink4)),
            ],
          ),
        ),
      ),
    );
  }
}
