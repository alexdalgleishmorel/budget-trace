import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// ── Glass surface ─────────────────────────────────────────────────────────────
//
// Frosted-glass tile, used as the base for every chrome surface in the Arctic
// rework. The CSS recipe is `backdrop-filter: blur() saturate()` plus a stack
// of inset/drop shadows and a refractive sheen via `mix-blend-mode: overlay`.
//
// Flutter approximations (intentional — the SDK does not match CSS exactly):
//   • `saturate()` is not available; we let the underlying gradient bleed
//     through and accept the visual difference.
//   • `mix-blend-mode: overlay` does not behave the same against translucent
//     surfaces in Flutter — we replace the sheen pseudo-element with a
//     plain vertical LinearGradient overlay. Do NOT try to "fix" with
//     BlendMode.overlay; it looks worse.
//   • CSS inset box-shadows have no Flutter equivalent — we layer two 1 px
//     Containers (top highlight / bottom shade) inside the clip.

enum GlassTier { t1, t2, t3, strong }

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.tier = GlassTier.t1,
    this.radius = 16,
    this.padding,
    this.glow,
    this.borderOverride,
    this.dashedBorder = false,
    this.elevated = true,
    this.sheen = true,
  });

  final Widget child;
  final GlassTier tier;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final BoxShadow? glow;
  final Color? borderOverride;
  final bool dashedBorder;
  final bool elevated;
  final bool sheen;

  double get _blurSigma => tier == GlassTier.strong ? 24 : 20;

  Color _fill(BudgetTheme bt) {
    switch (tier) {
      case GlassTier.t1:
        return bt.glass1;
      case GlassTier.t2:
        return bt.glass2;
      case GlassTier.t3:
      case GlassTier.strong:
        return bt.glass3;
    }
  }

  Color _border(BudgetTheme bt) {
    if (borderOverride != null) return borderOverride!;
    return tier == GlassTier.t3 || tier == GlassTier.strong
        ? bt.glassBorderStrong
        : bt.glassBorder;
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final br = BorderRadius.all(Radius.circular(radius));
    final shadows = <BoxShadow>[
      if (elevated) bt.glassShadow,
      ?glow,
    ];
    final fill = _fill(bt);
    final border = _border(bt);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: shadows.isEmpty ? null : shadows,
      ),
      child: ClipRRect(
        borderRadius: br,
        child: Stack(
          children: [
            // 1. Blurred backdrop with fill
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _blurSigma,
                  sigmaY: _blurSigma,
                ),
                child: ColoredBox(color: fill),
              ),
            ),
            // 2. Sheen overlay (replaces `mix-blend-mode: overlay`)
            if (sheen)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          bt.glassHighlight.withValues(
                            alpha: bt.glassHighlight.a * 0.55,
                          ),
                          Colors.transparent,
                          Colors.transparent,
                          bt.glassHighlight.withValues(
                            alpha: bt.glassHighlight.a * 0.14,
                          ),
                        ],
                        stops: const [0.0, 0.35, 0.70, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            // 3. Solid or dashed border
            if (!dashedBorder)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: br,
                      border: Border.all(color: border, width: 1),
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DashedBorderPainter(
                      color: border,
                      radius: radius,
                    ),
                  ),
                ),
              ),
            // 4. Content (non-positioned — sizes the Stack)
            Padding(
              padding: padding ?? EdgeInsets.zero,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ── Page background (gradient + veil orbs) ───────────────────────────────────

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base gradient (155° in CSS ≈ down + slight right)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.42, -1.0),
              end: const Alignment(0.42, 1.0),
              colors: bt.bgGrad,
              stops: bt.bgGradStops,
            ),
          ),
        ),
        // Veil orb A — top-right, accent hue
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1, -1),
                radius: 1.2,
                colors: [bt.bgVeilA, Colors.transparent],
                stops: const [0.0, 0.6],
              ),
            ),
          ),
        ),
        // Veil orb B — bottom-left, accent-2 hue
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-1, 1),
                radius: 1.0,
                colors: [bt.bgVeilB, Colors.transparent],
                stops: const [0.0, 0.55],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

// ── Buttons ──────────────────────────────────────────────────────────────────

enum GlassButtonVariant { primary, secondary, ghost, destructive }

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = GlassButtonVariant.secondary,
    this.compact = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final GlassButtonVariant variant;
  final bool compact;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final disabled = onPressed == null;
    final height = compact ? 34.0 : 40.0;
    final hPad = compact ? 14.0 : 18.0;

    final labelColor = _labelColor(bt);
    // Default icon color matches the label — callers can still override by
    // passing an explicit color on the icon widget.
    final Widget content = IconTheme.merge(
      data: IconThemeData(color: labelColor),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.01 * (compact ? 13 : 14),
              color: labelColor,
            ),
          ),
        ],
      ),
    );

    final padded = Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: content,
    );

    final body = SizedBox(
      height: height,
      child: variant == GlassButtonVariant.primary
          ? _primaryBody(bt, padded)
          : variant == GlassButtonVariant.secondary
              ? _secondaryBody(bt, padded)
              : variant == GlassButtonVariant.destructive
                  ? _destructiveBody(bt, padded)
                  : _ghostBody(bt, padded),
    );

    // Loose constraints (e.g. inside a Stack(alignment: center)) would let
    // the button expand to the parent's max width, which is never what a
    // standalone button wants. IntrinsicWidth sizes it to its label/icon.
    // Tight parent constraints — e.g. `Column(crossAxisAlignment: stretch)`
    // for an empty-state CTA — still win over IntrinsicWidth, so the
    // explicit-stretch use case keeps working.
    final shell = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: body,
      ),
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: expand ? shell : IntrinsicWidth(child: shell),
    );
  }

  Color _labelColor(BudgetTheme bt) {
    switch (variant) {
      case GlassButtonVariant.primary:
        return Colors.white;
      case GlassButtonVariant.secondary:
        return bt.ink;
      case GlassButtonVariant.ghost:
        return bt.ink2;
      case GlassButtonVariant.destructive:
        return bt.neg;
    }
  }

  Widget _primaryBody(BudgetTheme bt, Widget content) {
    final br = BorderRadius.circular(999);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bt.accentGrad,
          stops: bt.accentGradStops,
        ),
        // Soft outer accent halo + a tight cyan-tinted glow ring that, on the
        // dark gradient background, reads as the bezel in the design bundle.
        // Alphas tuned down from the original (0.45 / 0.18) so the bloom
        // doesn't overwhelm — pairs with the darker 800-level gradient stops.
        boxShadow: [
          BoxShadow(
            color: bt.accent.withValues(alpha: 0.28),
            blurRadius: 18,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: bt.accent2.withValues(alpha: 0.10),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
        // 1px translucent white ring — the "outline" visible in the screenshot.
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: br,
        child: Stack(
          children: [
            // 1px top inner highlight — Flutter has no inset BoxShadow, so
            // we draw a slim Container pinned to the top of the clip.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
            // 1px bottom inner shade — gives the button its subtle "bezel"
            // bottom edge, balancing the top highlight.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  color: Colors.black.withValues(alpha: 0.12),
                ),
              ),
            ),
            Center(child: content),
          ],
        ),
      ),
    );
  }

  Widget _secondaryBody(BudgetTheme bt, Widget content) {
    return GlassSurface(
      tier: GlassTier.t2,
      radius: 999,
      elevated: false,
      sheen: false,
      child: Center(child: content),
    );
  }

  Widget _destructiveBody(BudgetTheme bt, Widget content) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: bt.negBg,
        border: Border.all(color: bt.negBorder, width: 1),
      ),
      child: Center(child: content),
    );
  }

  Widget _ghostBody(BudgetTheme bt, Widget content) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.transparent,
      ),
      child: Center(child: content),
    );
  }
}

// ── Chip ─────────────────────────────────────────────────────────────────────

class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.active = false,
    this.icon,
    this.onTap,
    this.compact = true,
  });

  final String label;
  final bool active;
  final Widget? icon;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final height = compact ? 30.0 : 36.0;
    final hPad = 14.0;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          icon!,
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? Colors.white : bt.ink2,
          ),
        ),
      ],
    );

    final body = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        child: Center(child: content),
      ),
    );

    final shell = active
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bt.accentGrad,
                stops: bt.accentGradStops,
              ),
              boxShadow: [
                BoxShadow(
                  color: bt.accent.withValues(alpha: 0.30),
                  blurRadius: 12,
                  spreadRadius: -2,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: body,
          )
        : GlassSurface(
            tier: GlassTier.t2,
            radius: 999,
            elevated: false,
            sheen: false,
            child: body,
          );

    if (onTap == null) return shell;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: shell,
      ),
    );
  }
}

// ── Field ────────────────────────────────────────────────────────────────────

class GlassField extends StatefulWidget {
  const GlassField({
    super.key,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.monospaced = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.suffix,
    this.prefix,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String? placeholder;
  final bool obscure;
  final bool monospaced;
  final int minLines;
  final int? maxLines;
  final Widget? suffix;
  final Widget? prefix;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextInputType? keyboardType;

  @override
  State<GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<GlassField> {
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(() {
      if (!mounted) return;
      setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final style = TextStyle(
      fontSize: 14,
      fontFamily: widget.monospaced ? 'SF Mono' : null,
      fontFamilyFallback: widget.monospaced ? const ['Menlo', 'monospace'] : null,
      color: bt.ink,
    );
    final isMulti = (widget.maxLines ?? 1) > 1 || widget.minLines > 1;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: bt.fieldBg,
        border: Border.all(
          color: _focused ? bt.accent : bt.fieldBorder,
          width: 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: bt.accent.withValues(alpha: 0.20),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      constraints: BoxConstraints(minHeight: isMulti ? 76 : 42),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: isMulti ? 10 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.prefix != null) ...[
            widget.prefix!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              obscureText: widget.obscure,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType,
              style: style,
              cursorColor: bt.accent,
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: bt.ink4,
                  fontFamily: widget.monospaced ? 'SF Mono' : null,
                ),
                contentPadding: EdgeInsets.symmetric(
                  vertical: isMulti ? 0 : 12,
                ),
              ),
            ),
          ),
          if (widget.suffix != null) ...[
            const SizedBox(width: 8),
            widget.suffix!,
          ],
        ],
      ),
    );
  }
}

// ── Toggle ───────────────────────────────────────────────────────────────────

class GlassToggle extends StatelessWidget {
  const GlassToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    const w = 44.0;
    const h = 26.0;
    const knob = 20.0;
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: value
                ? LinearGradient(
                    colors: bt.accentGrad,
                    stops: bt.accentGradStops,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: value ? null : bt.glass3,
            border: Border.all(
              color: value ? Colors.transparent : bt.glassBorder,
              width: 1,
            ),
            boxShadow: value
                ? [
                    BoxShadow(
                      color: bt.accent.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: -2,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          padding: const EdgeInsets.all(2),
          child: Container(
            width: knob,
            height: knob,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Gradient text (accent gradient wash) ─────────────────────────────────────

class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style, this.colors, this.stops});
  final String text;
  final TextStyle? style;
  final List<Color>? colors;
  final List<double>? stops;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final gColors = colors ?? bt.accentGrad;
    final gStops = stops ?? bt.accentGradStops;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gColors,
        stops: gStops,
      ).createShader(bounds),
      child: Text(text, style: style),
    );
  }
}

// ── Modal shell ──────────────────────────────────────────────────────────────

class GlassModalShell extends StatelessWidget {
  const GlassModalShell({
    super.key,
    required this.title,
    required this.child,
    this.footer,
    this.onClose,
    this.maxWidth = 520,
  });

  final String title;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onClose;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GlassSurface(
          tier: GlassTier.strong,
          radius: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: bt.ink,
                          letterSpacing: -0.01,
                        ),
                      ),
                    ),
                    if (onClose != null)
                      _CloseButton(onTap: onClose!),
                  ],
                ),
              ),
              Container(height: 1, color: bt.glassBorder),
              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: child,
                ),
              ),
              // Footer
              if (footer != null) ...[
                Container(height: 1, color: bt.glassBorder),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: footer!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bt.glass2,
            border: Border.all(color: bt.glassBorder, width: 1),
          ),
          child: CustomPaint(
            size: const Size(12, 12),
            painter: _XPainter(color: bt.ink2),
          ),
        ),
      ),
    );
  }
}

class _XPainter extends CustomPainter {
  _XPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, size.height), p);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), p);
  }

  @override
  bool shouldRepaint(covariant _XPainter old) => old.color != color;
}

// ── Helper: present a glass modal with a blurred barrier ─────────────────────

Future<T?> showGlassModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: const Color(0x8C080614),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) => SafeArea(child: builder(ctx)),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8 * curved.value, sigmaY: 8 * curved.value),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

// ── Gradient icon tile (used by brand mark, dropzone icon, etc) ──────────────

class GradientIconTile extends StatelessWidget {
  const GradientIconTile({
    super.key,
    required this.child,
    this.size = 26,
    this.radius = 8,
  });

  final Widget child;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bt.accentGrad,
          stops: bt.accentGradStops,
        ),
        boxShadow: [
          BoxShadow(
            color: bt.accent.withValues(alpha: 0.35),
            blurRadius: 14,
            spreadRadius: -3,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
