import 'package:flutter/material.dart';

// ── Design tokens — Expense Visualizer (Arctic palette, dark-only) ───────────
//
// The app ships a single, opinionated dark theme. The bundle's Arctic light
// variant was retired — the entire visual language (glass surfaces, sheen
// overlays, accent gradients) is calibrated for a deep-sky backdrop and the
// extra mode wasn't paying for its complexity.

class BudgetColors {
  // ── Arctic dark palette ───────────────────────────────────────────────────

  static const bg = Color(0xFF060D18);
  static const bg2 = Color(0xFF163A4A);
  static const surface = Color.fromRGBO(220, 235, 250, 0.07); // = glass1
  static const surface2 = Color.fromRGBO(220, 235, 250, 0.12); // = glass2
  static const ink = Color.fromRGBO(245, 250, 255, 0.96);
  static const ink2 = Color.fromRGBO(245, 250, 255, 0.72);
  static const ink3 = Color.fromRGBO(245, 250, 255, 0.52);
  static const ink4 = Color.fromRGBO(245, 250, 255, 0.34);
  static const ink5 = Color.fromRGBO(245, 250, 255, 0.18);
  static const rule = Color.fromRGBO(220, 235, 250, 0.20);
  static const ruleStrong = Color.fromRGBO(220, 235, 250, 0.30);
  static const ruleSoft = Color.fromRGBO(220, 235, 250, 0.10);
  static const pos = Color(0xFF10B981);
  static const posBg = Color.fromRGBO(16, 185, 129, 0.18);
  static const posBorder = Color.fromRGBO(16, 185, 129, 0.50);
  static const neg = Color(0xFFF43F5E);
  static const negBg = Color.fromRGBO(244, 63, 94, 0.18);
  static const negBorder = Color.fromRGBO(244, 63, 94, 0.35);
  static const warn = Color(0xFFF59E0B);
  static const warnBg = Color.fromRGBO(245, 158, 11, 0.18);
  // First 5 hues of the 12-color category palette (used by widget bodies and
  // the legacy tile API). Saturated hues — text uses white.
  static const tile1 = Color(0xFF10B981);
  static const tile2 = Color(0xFF06B6D4);
  static const tile3 = Color(0xFF3B82F6);
  static const tile4 = Color(0xFF8B5CF6);
  static const tile5 = Color(0xFFD946EF);
  static const tileInk = Color(0xFFFFFFFF);
  static const tileInk2 = Color.fromRGBO(255, 255, 255, 0.72);

  // Glass / chrome / accent
  static const glass1 = Color.fromRGBO(220, 235, 250, 0.07);
  static const glass2 = Color.fromRGBO(220, 235, 250, 0.12);
  static const glass3 = Color.fromRGBO(220, 235, 250, 0.17);
  static const glassBorder = Color.fromRGBO(220, 235, 250, 0.20);
  static const glassBorderStrong = Color.fromRGBO(220, 235, 250, 0.30);
  static const glassHighlight = Color.fromRGBO(230, 245, 255, 0.32);
  static const fieldBg = Color.fromRGBO(220, 235, 250, 0.06);
  static const fieldBorder = Color.fromRGBO(220, 235, 250, 0.20);
  static const accent = Color(0xFF0EA5E9);
  static const accent2 = Color(0xFF06B6D4);
  static const bgVeilA = Color.fromRGBO(14, 165, 233, 0.14);
  static const bgVeilB = Color.fromRGBO(6, 182, 212, 0.12);
  static const glassShadow = BoxShadow(
    color: Color.fromRGBO(0, 20, 35, 0.55),
    offset: Offset(0, 30),
    blurRadius: 60,
    spreadRadius: -20,
  );

  static const bgGrad = <Color>[
    Color(0xFF060D18),
    Color(0xFF0C1A2B),
    Color(0xFF112942),
    Color(0xFF163A4A),
  ];
  // Primary-button / chip-active gradient. Pitched darker than the bundle's
  // 700-level stops so the button reads as accent without dominating the
  // page — Tailwind 800-level sky/cyan/teal at ~27% lightness, paired with
  // a softer outer halo over in GlassButton._primaryBody.
  static const accentGrad = <Color>[
    Color(0xFF075985), // sky-800
    Color(0xFF155E75), // cyan-800
    Color(0xFF115E59), // teal-800
  ];

  /// 12-color category palette from the design bundle. Used as solid swatches
  /// on dark surfaces — white text always wins.
  static const categoryPalette = <Color>[
    Color(0xFF10B981), // emerald
    Color(0xFF06B6D4), // cyan
    Color(0xFF3B82F6), // blue
    Color(0xFF8B5CF6), // violet
    Color(0xFFD946EF), // fuchsia
    Color(0xFFEC4899), // pink
    Color(0xFFF43F5E), // rose
    Color(0xFFF59E0B), // amber
    Color(0xFFEAB308), // yellow
    Color(0xFF84CC16), // lime
    Color(0xFF14B8A6), // teal
    Color(0xFF6366F1), // indigo
  ];

  static const bgGradStops = <double>[0.0, 0.35, 0.70, 1.0];
  static const accentGradStops = <double>[0.0, 0.55, 1.0];
}

/// Curated palette for category tiles. Keys are stored verbatim in the
/// database (single source of truth in `backend/.../category_palette.py`);
/// the frontend resolves each key to one of the bundle's 12 category hues.
class CategoryPalette {
  static const String defaultKey = 'stone';

  /// Ordered key list. Drives the order of swatches in the picker.
  static const List<String> keys = [
    'sage',
    'moss',
    'olive',
    'ochre',
    'sand',
    'cream',
    'clay',
    'rose',
    'plum',
    'lavender',
    'sky',
    'teal',
    'stone',
    'graphite',
  ];

  static const Map<String, Color> _palette = {
    'sage':     Color(0xFF10B981), // emerald (cat-1)
    'moss':     Color(0xFF84CC16), // lime (cat-10)
    'olive':    Color(0xFFEAB308), // yellow (cat-9)
    'ochre':    Color(0xFFF59E0B), // amber (cat-8)
    'sand':     Color(0xFFFBBF24), // lighter amber
    'cream':    Color(0xFFFCD34D), // soft yellow
    'clay':     Color(0xFFF43F5E), // rose (cat-7)
    'rose':     Color(0xFFEC4899), // pink (cat-6)
    'plum':     Color(0xFFD946EF), // fuchsia (cat-5)
    'lavender': Color(0xFF8B5CF6), // violet (cat-4)
    'sky':      Color(0xFF06B6D4), // cyan (cat-2)
    'teal':     Color(0xFF14B8A6), // teal (cat-11)
    'stone':    Color(0xFF6366F1), // indigo (cat-12)
    'graphite': Color(0xFF3B82F6), // blue (cat-3)
  };

  static Color resolve(String key) =>
      _palette[key] ?? _palette[defaultKey]!;
}

class BudgetRadius {
  // Existing
  static const card = Radius.circular(20);
  static const tile = Radius.circular(18);
  static const btn = Radius.circular(12);
  static const input = Radius.circular(12);
  static const chip = Radius.circular(999);
  static const sm = Radius.circular(8);

  // New (Arctic) — bundle scale
  static const xs = Radius.circular(8);
  static const md = Radius.circular(16);
  static const lg = Radius.circular(20); // alias of card
  static const xl = Radius.circular(24); // modal shells
  static const pill = Radius.circular(999); // alias of chip

  static const cardBR = BorderRadius.all(card);
  static const tileBR = BorderRadius.all(tile);
  static const btnBR = BorderRadius.all(btn);
  static const inputBR = BorderRadius.all(input);
  static const chipBR = BorderRadius.all(chip);
  static const smBR = BorderRadius.all(sm);
  static const xsBR = BorderRadius.all(xs);
  static const mdBR = BorderRadius.all(md);
  static const lgBR = BorderRadius.all(lg);
  static const xlBR = BorderRadius.all(xl);
  static const pillBR = BorderRadius.all(pill);
}

// ── ThemeExtension providing semantic colours ────────────────────────────────

class BudgetTheme extends ThemeExtension<BudgetTheme> {
  const BudgetTheme({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.ink5,
    required this.rule,
    required this.ruleStrong,
    required this.ruleSoft,
    required this.pos,
    required this.posBg,
    required this.posBorder,
    required this.neg,
    required this.negBg,
    required this.negBorder,
    required this.warn,
    required this.warnBg,
    required this.tile1,
    required this.tile2,
    required this.tile3,
    required this.tile4,
    required this.tile5,
    required this.tileInk,
    required this.tileInk2,
    required this.bgGrad,
    required this.bgGradStops,
    required this.glass1,
    required this.glass2,
    required this.glass3,
    required this.glassBorder,
    required this.glassBorderStrong,
    required this.glassHighlight,
    required this.glassShadow,
    required this.fieldBg,
    required this.fieldBorder,
    required this.accent,
    required this.accent2,
    required this.accentGrad,
    required this.accentGradStops,
    required this.categoryColors,
    required this.bgVeilA,
    required this.bgVeilB,
  });

  final Color bg;
  final Color bg2;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color ink4;
  final Color ink5;
  final Color rule;
  final Color ruleStrong;
  final Color ruleSoft;
  final Color pos;
  final Color posBg;
  final Color posBorder;
  final Color neg;
  final Color negBg;
  final Color negBorder;
  final Color warn;
  final Color warnBg;
  final Color tile1;
  final Color tile2;
  final Color tile3;
  final Color tile4;
  final Color tile5;
  final Color tileInk;
  final Color tileInk2;

  final List<Color> bgGrad;
  final List<double> bgGradStops;
  final Color glass1;
  final Color glass2;
  final Color glass3;
  final Color glassBorder;
  final Color glassBorderStrong;
  final Color glassHighlight;
  final BoxShadow glassShadow;
  final Color fieldBg;
  final Color fieldBorder;
  final Color accent;
  final Color accent2;
  final List<Color> accentGrad;
  final List<double> accentGradStops;
  final List<Color> categoryColors;
  final Color bgVeilA;
  final Color bgVeilB;

  List<Color> get tileColors => [tile1, tile2, tile3, tile4, tile5];

  /// The one and only theme value. The app is dark-only; this constant is
  /// what `buildTheme()` registers into `ThemeData.extensions`. Tests can
  /// reach for it directly when they need to construct a themed
  /// `MaterialApp` in isolation.
  static const dark = BudgetTheme(
    bg: BudgetColors.bg,
    bg2: BudgetColors.bg2,
    surface: BudgetColors.surface,
    surface2: BudgetColors.surface2,
    ink: BudgetColors.ink,
    ink2: BudgetColors.ink2,
    ink3: BudgetColors.ink3,
    ink4: BudgetColors.ink4,
    ink5: BudgetColors.ink5,
    rule: BudgetColors.rule,
    ruleStrong: BudgetColors.ruleStrong,
    ruleSoft: BudgetColors.ruleSoft,
    pos: BudgetColors.pos,
    posBg: BudgetColors.posBg,
    posBorder: BudgetColors.posBorder,
    neg: BudgetColors.neg,
    negBg: BudgetColors.negBg,
    negBorder: BudgetColors.negBorder,
    warn: BudgetColors.warn,
    warnBg: BudgetColors.warnBg,
    tile1: BudgetColors.tile1,
    tile2: BudgetColors.tile2,
    tile3: BudgetColors.tile3,
    tile4: BudgetColors.tile4,
    tile5: BudgetColors.tile5,
    tileInk: BudgetColors.tileInk,
    tileInk2: BudgetColors.tileInk2,
    bgGrad: BudgetColors.bgGrad,
    bgGradStops: BudgetColors.bgGradStops,
    glass1: BudgetColors.glass1,
    glass2: BudgetColors.glass2,
    glass3: BudgetColors.glass3,
    glassBorder: BudgetColors.glassBorder,
    glassBorderStrong: BudgetColors.glassBorderStrong,
    glassHighlight: BudgetColors.glassHighlight,
    glassShadow: BudgetColors.glassShadow,
    fieldBg: BudgetColors.fieldBg,
    fieldBorder: BudgetColors.fieldBorder,
    accent: BudgetColors.accent,
    accent2: BudgetColors.accent2,
    accentGrad: BudgetColors.accentGrad,
    accentGradStops: BudgetColors.accentGradStops,
    categoryColors: BudgetColors.categoryPalette,
    bgVeilA: BudgetColors.bgVeilA,
    bgVeilB: BudgetColors.bgVeilB,
  );

  @override
  BudgetTheme copyWith({
    Color? bg, Color? bg2, Color? surface, Color? surface2,
    Color? ink, Color? ink2, Color? ink3, Color? ink4, Color? ink5,
    Color? rule, Color? ruleStrong, Color? ruleSoft,
    Color? pos, Color? posBg, Color? posBorder,
    Color? neg, Color? negBg, Color? negBorder,
    Color? warn, Color? warnBg,
    Color? tile1, Color? tile2, Color? tile3, Color? tile4, Color? tile5,
    Color? tileInk, Color? tileInk2,
    List<Color>? bgGrad, List<double>? bgGradStops,
    Color? glass1, Color? glass2, Color? glass3,
    Color? glassBorder, Color? glassBorderStrong, Color? glassHighlight,
    BoxShadow? glassShadow,
    Color? fieldBg, Color? fieldBorder,
    Color? accent, Color? accent2,
    List<Color>? accentGrad, List<double>? accentGradStops,
    List<Color>? categoryColors,
    Color? bgVeilA, Color? bgVeilB,
  }) => BudgetTheme(
    bg: bg ?? this.bg, bg2: bg2 ?? this.bg2,
    surface: surface ?? this.surface, surface2: surface2 ?? this.surface2,
    ink: ink ?? this.ink, ink2: ink2 ?? this.ink2,
    ink3: ink3 ?? this.ink3, ink4: ink4 ?? this.ink4, ink5: ink5 ?? this.ink5,
    rule: rule ?? this.rule, ruleStrong: ruleStrong ?? this.ruleStrong, ruleSoft: ruleSoft ?? this.ruleSoft,
    pos: pos ?? this.pos, posBg: posBg ?? this.posBg, posBorder: posBorder ?? this.posBorder,
    neg: neg ?? this.neg, negBg: negBg ?? this.negBg, negBorder: negBorder ?? this.negBorder,
    warn: warn ?? this.warn, warnBg: warnBg ?? this.warnBg,
    tile1: tile1 ?? this.tile1, tile2: tile2 ?? this.tile2, tile3: tile3 ?? this.tile3,
    tile4: tile4 ?? this.tile4, tile5: tile5 ?? this.tile5,
    tileInk: tileInk ?? this.tileInk, tileInk2: tileInk2 ?? this.tileInk2,
    bgGrad: bgGrad ?? this.bgGrad,
    bgGradStops: bgGradStops ?? this.bgGradStops,
    glass1: glass1 ?? this.glass1,
    glass2: glass2 ?? this.glass2,
    glass3: glass3 ?? this.glass3,
    glassBorder: glassBorder ?? this.glassBorder,
    glassBorderStrong: glassBorderStrong ?? this.glassBorderStrong,
    glassHighlight: glassHighlight ?? this.glassHighlight,
    glassShadow: glassShadow ?? this.glassShadow,
    fieldBg: fieldBg ?? this.fieldBg,
    fieldBorder: fieldBorder ?? this.fieldBorder,
    accent: accent ?? this.accent,
    accent2: accent2 ?? this.accent2,
    accentGrad: accentGrad ?? this.accentGrad,
    accentGradStops: accentGradStops ?? this.accentGradStops,
    categoryColors: categoryColors ?? this.categoryColors,
    bgVeilA: bgVeilA ?? this.bgVeilA,
    bgVeilB: bgVeilB ?? this.bgVeilB,
  );

  static List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    final n = a.length;
    return List<Color>.generate(n, (i) => Color.lerp(a[i], b[i % b.length], t)!);
  }

  static List<double> _lerpDoubleList(List<double> a, List<double> b, double t) {
    final n = a.length;
    return List<double>.generate(n, (i) {
      final bv = b[i % b.length];
      return a[i] + (bv - a[i]) * t;
    });
  }

  static BoxShadow _lerpShadow(BoxShadow a, BoxShadow b, double t) {
    return BoxShadow(
      color: Color.lerp(a.color, b.color, t)!,
      offset: Offset.lerp(a.offset, b.offset, t)!,
      blurRadius: a.blurRadius + (b.blurRadius - a.blurRadius) * t,
      spreadRadius: a.spreadRadius + (b.spreadRadius - a.spreadRadius) * t,
    );
  }

  @override
  BudgetTheme lerp(BudgetTheme? other, double t) {
    if (other == null) return this;
    return BudgetTheme(
      bg: Color.lerp(bg, other.bg, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      ink4: Color.lerp(ink4, other.ink4, t)!,
      ink5: Color.lerp(ink5, other.ink5, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      ruleStrong: Color.lerp(ruleStrong, other.ruleStrong, t)!,
      ruleSoft: Color.lerp(ruleSoft, other.ruleSoft, t)!,
      pos: Color.lerp(pos, other.pos, t)!,
      posBg: Color.lerp(posBg, other.posBg, t)!,
      posBorder: Color.lerp(posBorder, other.posBorder, t)!,
      neg: Color.lerp(neg, other.neg, t)!,
      negBg: Color.lerp(negBg, other.negBg, t)!,
      negBorder: Color.lerp(negBorder, other.negBorder, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnBg: Color.lerp(warnBg, other.warnBg, t)!,
      tile1: Color.lerp(tile1, other.tile1, t)!,
      tile2: Color.lerp(tile2, other.tile2, t)!,
      tile3: Color.lerp(tile3, other.tile3, t)!,
      tile4: Color.lerp(tile4, other.tile4, t)!,
      tile5: Color.lerp(tile5, other.tile5, t)!,
      tileInk: Color.lerp(tileInk, other.tileInk, t)!,
      tileInk2: Color.lerp(tileInk2, other.tileInk2, t)!,
      bgGrad: _lerpColorList(bgGrad, other.bgGrad, t),
      bgGradStops: _lerpDoubleList(bgGradStops, other.bgGradStops, t),
      glass1: Color.lerp(glass1, other.glass1, t)!,
      glass2: Color.lerp(glass2, other.glass2, t)!,
      glass3: Color.lerp(glass3, other.glass3, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassBorderStrong: Color.lerp(glassBorderStrong, other.glassBorderStrong, t)!,
      glassHighlight: Color.lerp(glassHighlight, other.glassHighlight, t)!,
      glassShadow: _lerpShadow(glassShadow, other.glassShadow, t),
      fieldBg: Color.lerp(fieldBg, other.fieldBg, t)!,
      fieldBorder: Color.lerp(fieldBorder, other.fieldBorder, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accentGrad: _lerpColorList(accentGrad, other.accentGrad, t),
      accentGradStops: _lerpDoubleList(accentGradStops, other.accentGradStops, t),
      categoryColors: _lerpColorList(categoryColors, other.categoryColors, t),
      bgVeilA: Color.lerp(bgVeilA, other.bgVeilA, t)!,
      bgVeilB: Color.lerp(bgVeilB, other.bgVeilB, t)!,
    );
  }
}

// ── ThemeData factory ────────────────────────────────────────────────────────

/// Builds the dark `ThemeData` used app-wide. The light variant was retired —
/// `MaterialApp` is wired with `theme: buildTheme()` and `themeMode: dark`.
ThemeData buildTheme() {
  const bt = BudgetTheme.dark;
  return ThemeData(
    brightness: Brightness.dark,
    // Scaffold bg is transparent — AppBackground (in widgets/glass.dart)
    // paints the page gradient + veil orbs at the AppShell root.
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: BudgetColors.accent,
      onPrimary: Colors.white,
      secondary: BudgetColors.accent2,
      onSecondary: Colors.white,
      error: BudgetColors.neg,
      onError: Colors.white,
      surface: BudgetColors.surface,
      onSurface: BudgetColors.ink,
    ),
    fontFamily: 'SF Pro Text',
    fontFamilyFallback: const ['SF Pro Display', 'Inter', 'system-ui'],
    useMaterial3: true,
    // `surface` above is the translucent glass-1 token, which Material's
    // AlertDialog uses for its default fill — that left dialogs reading
    // as see-through against the page gradient. Pin AlertDialog (and the
    // material PopupMenu / BottomSheet shells) to an opaque deep-navy so
    // they pop against the gradient.
    dialogTheme: DialogThemeData(
      backgroundColor: BudgetColors.bgGrad[1], // #0C1A2B — deeper than bg
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: BudgetColors.ink,
      ),
      contentTextStyle: const TextStyle(
        fontSize: 13,
        color: BudgetColors.ink2,
        height: 1.45,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: BudgetColors.bg,
      surfaceTintColor: Colors.transparent,
    ),
    // PopupMenuButton (the dashboard's time-range picker, anywhere using
    // Material's `showMenu`) defaults to `ColorScheme.surface` — same
    // translucent glass-1 issue as AlertDialog. Pin it to an opaque
    // deep-navy with a soft border so the menu pops against the page.
    popupMenuTheme: PopupMenuThemeData(
      color: BudgetColors.bgGrad[1],
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      textStyle: const TextStyle(
        fontSize: 13,
        color: BudgetColors.ink,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: BudgetColors.glassBorderStrong),
      ),
    ),
    extensions: const [bt],
  );
}

// ── Convenience extension ─────────────────────────────────────────────────────

extension BudgetThemeContext on BuildContext {
  BudgetTheme get bt => Theme.of(this).extension<BudgetTheme>()!;

  /// Resolve a category palette key to a tile background color.
  Color categoryBg(String key) => CategoryPalette.resolve(key);
}
