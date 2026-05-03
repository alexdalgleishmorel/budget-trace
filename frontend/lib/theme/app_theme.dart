import 'package:flutter/material.dart';

// ── Design tokens from tokens.css ───────────────────────────────────────────

class BudgetColors {
  // Light palette
  static const bgLight = Color(0xFFF6F3EC);
  static const bg2Light = Color(0xFFF0ECE2);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surface2Light = Color(0xFFFAF8F2);
  static const inkLight = Color(0xFF121110);
  static const ink2Light = Color(0xFF2C2A26);
  static const ink3Light = Color(0xFF5C5851);
  static const ink4Light = Color(0xFF8C877D);
  static const ink5Light = Color(0xFFB5B0A5);
  static const ruleLight = Color(0x14121110); // 8% opacity
  static const ruleStrongLight = Color(0x24121110); // 14%
  static const ruleSoftLight = Color(0x0D121110); // 5%
  static const posLight = Color(0xFF2E7D53);
  static const posBgLight = Color(0x142E7D53);
  static const posBorderLight = Color(0x332E7D53);
  static const negLight = Color(0xFFB4432F);
  static const negBgLight = Color(0x14B4432F);
  static const negBorderLight = Color(0x38B4432F);
  static const warnLight = Color(0xFF9A7A2C);
  static const warnBgLight = Color(0x1A9A7A2C);
  static const tile1Light = Color(0xFFECE8DE);
  static const tile2Light = Color(0xFFE2DED3);
  static const tile3Light = Color(0xFFD6D2C6);
  static const tile4Light = Color(0xFFC8C4B7);
  static const tile5Light = Color(0xFFB9B6A8);
  static const tileInkLight = Color(0xFF1A1815);
  static const tileInk2Light = Color(0xFF4A463D);

  // Dark palette
  static const bgDark = Color(0xFF0C0B09);
  static const bg2Dark = Color(0xFF13120F);
  static const surfaceDark = Color(0xFF17150F);
  static const surface2Dark = Color(0xFF1D1B14);
  static const inkDark = Color(0xFFF0ECE2);
  static const ink2Dark = Color(0xFFD9D4C6);
  static const ink3Dark = Color(0xFFA49E8E);
  static const ink4Dark = Color(0xFF76715F);
  static const ink5Dark = Color(0xFF4F4A3E);
  static const ruleDark = Color(0x14F0ECE2);
  static const ruleStrongDark = Color(0x24F0ECE2);
  static const ruleSoftDark = Color(0x0AF0ECE2);
  static const posDark = Color(0xFF6FBE8E);
  static const posBgDark = Color(0x1A6FBE8E);
  static const posBorderDark = Color(0x476FBE8E);
  static const negDark = Color(0xFFE0826D);
  static const negBgDark = Color(0x1AE0826D);
  static const negBorderDark = Color(0x47E0826D);
  static const warnDark = Color(0xFFD4B26A);
  static const warnBgDark = Color(0x1FD4B26A);
  static const tile1Dark = Color(0xFF1F1D16);
  static const tile2Dark = Color(0xFF26231B);
  static const tile3Dark = Color(0xFF2E2B22);
  static const tile4Dark = Color(0xFF383428);
  static const tile5Dark = Color(0xFF423D2F);
  static const tileInkDark = Color(0xFFF0ECE2);
  static const tileInk2Dark = Color(0xFFB5B0A0);
}

class BudgetRadius {
  static const card = Radius.circular(20);
  static const tile = Radius.circular(18);
  static const btn = Radius.circular(12);
  static const input = Radius.circular(12);
  static const chip = Radius.circular(999);
  static const sm = Radius.circular(8);

  static const cardBR = BorderRadius.all(card);
  static const tileBR = BorderRadius.all(tile);
  static const btnBR = BorderRadius.all(btn);
  static const inputBR = BorderRadius.all(input);
  static const chipBR = BorderRadius.all(chip);
  static const smBR = BorderRadius.all(sm);
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

  List<Color> get tileColors => [tile1, tile2, tile3, tile4, tile5];

  static const light = BudgetTheme(
    bg: BudgetColors.bgLight,
    bg2: BudgetColors.bg2Light,
    surface: BudgetColors.surfaceLight,
    surface2: BudgetColors.surface2Light,
    ink: BudgetColors.inkLight,
    ink2: BudgetColors.ink2Light,
    ink3: BudgetColors.ink3Light,
    ink4: BudgetColors.ink4Light,
    ink5: BudgetColors.ink5Light,
    rule: BudgetColors.ruleLight,
    ruleStrong: BudgetColors.ruleStrongLight,
    ruleSoft: BudgetColors.ruleSoftLight,
    pos: BudgetColors.posLight,
    posBg: BudgetColors.posBgLight,
    posBorder: BudgetColors.posBorderLight,
    neg: BudgetColors.negLight,
    negBg: BudgetColors.negBgLight,
    negBorder: BudgetColors.negBorderLight,
    warn: BudgetColors.warnLight,
    warnBg: BudgetColors.warnBgLight,
    tile1: BudgetColors.tile1Light,
    tile2: BudgetColors.tile2Light,
    tile3: BudgetColors.tile3Light,
    tile4: BudgetColors.tile4Light,
    tile5: BudgetColors.tile5Light,
    tileInk: BudgetColors.tileInkLight,
    tileInk2: BudgetColors.tileInk2Light,
  );

  static const dark = BudgetTheme(
    bg: BudgetColors.bgDark,
    bg2: BudgetColors.bg2Dark,
    surface: BudgetColors.surfaceDark,
    surface2: BudgetColors.surface2Dark,
    ink: BudgetColors.inkDark,
    ink2: BudgetColors.ink2Dark,
    ink3: BudgetColors.ink3Dark,
    ink4: BudgetColors.ink4Dark,
    ink5: BudgetColors.ink5Dark,
    rule: BudgetColors.ruleDark,
    ruleStrong: BudgetColors.ruleStrongDark,
    ruleSoft: BudgetColors.ruleSoftDark,
    pos: BudgetColors.posDark,
    posBg: BudgetColors.posBgDark,
    posBorder: BudgetColors.posBorderDark,
    neg: BudgetColors.negDark,
    negBg: BudgetColors.negBgDark,
    negBorder: BudgetColors.negBorderDark,
    warn: BudgetColors.warnDark,
    warnBg: BudgetColors.warnBgDark,
    tile1: BudgetColors.tile1Dark,
    tile2: BudgetColors.tile2Dark,
    tile3: BudgetColors.tile3Dark,
    tile4: BudgetColors.tile4Dark,
    tile5: BudgetColors.tile5Dark,
    tileInk: BudgetColors.tileInkDark,
    tileInk2: BudgetColors.tileInk2Dark,
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
  );

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
    );
  }
}

// ── ThemeData factories ───────────────────────────────────────────────────────

ThemeData buildTheme(Brightness brightness) {
  final bt = brightness == Brightness.light ? BudgetTheme.light : BudgetTheme.dark;
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: bt.bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: bt.ink,
      onPrimary: bt.bg,
      secondary: bt.ink3,
      onSecondary: bt.bg,
      error: bt.neg,
      onError: bt.bg,
      surface: bt.surface,
      onSurface: bt.ink,
    ),
    fontFamily: 'SF Pro Text',
    useMaterial3: true,
    extensions: [bt],
  );
}

// ── Convenience extension ─────────────────────────────────────────────────────

extension BudgetThemeContext on BuildContext {
  BudgetTheme get bt => Theme.of(this).extension<BudgetTheme>()!;
}
