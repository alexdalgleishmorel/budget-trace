import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'cat_icon.dart';
import 'glass.dart';

/// Cycle picker shared between the desktop side nav and the mobile screen headers.
class CycleDropdown extends StatefulWidget {
  const CycleDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChange,
    this.openAbove = false,
    this.expand = false,
    this.popupWidth = 184,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChange;

  /// Whether the popup opens upward (true) or downward (false).
  final bool openAbove;

  /// If true the trigger button fills its parent's width.
  /// If false it shrinks to fit its content.
  final bool expand;

  final double popupWidth;

  @override
  State<CycleDropdown> createState() => _CycleDropdownState();
}

class _CycleDropdownState extends State<CycleDropdown> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  void _toggle(BuildContext context) =>
      _entry == null ? _open(context) : _close();

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _open(BuildContext context) {
    final bt = context.bt;
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: Stack(
          children: [
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: widget.openAbove ? Alignment.topRight : Alignment.bottomRight,
              followerAnchor: widget.openAbove ? Alignment.bottomRight : Alignment.topRight,
              offset: Offset(0, widget.openAbove ? -6 : 6),
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: widget.popupWidth,
                    child: GlassSurface(
                      tier: GlassTier.strong,
                      radius: 14,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.options.reversed.map((opt) {
                          final active = opt == widget.value;
                          return GestureDetector(
                            onTap: () { widget.onChange(opt); _close(); },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              color: Colors.transparent,
                              child: Row(children: [
                                Expanded(child: Text(opt, style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                  color: active ? bt.ink : bt.ink2,
                                ))),
                                if (active)
                                  BudgetIcons.build('check', size: 13, strokeWidth: 1.6, color: bt.accent),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
    final open = _entry != null;
    final label = Text(widget.value, style: TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500, color: bt.ink,
    ));
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: () => _toggle(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: bt.fieldBg,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            border: Border.all(color: open ? bt.accent.withValues(alpha: 0.45) : bt.fieldBorder),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (widget.expand) Expanded(child: label) else label,
              const SizedBox(width: 6),
              BudgetIcons.build('chevron-down', size: 13, strokeWidth: 1.6, color: bt.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
