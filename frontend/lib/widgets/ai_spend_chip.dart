import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pill-shaped readout of an AI spend amount in USD. Always shown with a
/// leading `~` (compact) or trailing `(est.)` (detailed) — the figure is
/// estimated from token usage × the selected model's published per-MTok
/// price, never the authoritative billed amount.
///
/// Two flavours:
///   * [AiSpendChip.compact] — `~$X.XX`. Used in the side nav / mobile
///     settings row.
///   * [AiSpendChip.detailed] — `$X.XX <label> (est.)`. Used in the Account
///     screen and the Insights chat header.
class AiSpendChip extends StatelessWidget {
  const AiSpendChip._({
    required this.amountUsd,
    required _Variant variant,
    this.label,
  }) : _variant = variant;

  factory AiSpendChip.compact({required double amountUsd}) =>
      AiSpendChip._(amountUsd: amountUsd, variant: _Variant.compact);

  factory AiSpendChip.detailed({
    required double amountUsd,
    required String label,
  }) =>
      AiSpendChip._(
        amountUsd: amountUsd,
        variant: _Variant.detailed,
        label: label,
      );

  final double amountUsd;
  final _Variant _variant;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final amount = _formatUsd(amountUsd);
    final text = switch (_variant) {
      _Variant.compact => '~$amount',
      _Variant.detailed => '$amount ${label ?? ''} (est.)'.trim(),
    };
    return Tooltip(
      message:
          'Estimated from token usage and the selected model\'s published '
          'per-MTok price. Not the same as your provider bill.',
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        decoration: BoxDecoration(
          color: bt.surface2,
          borderRadius: BudgetRadius.chipBR,
          border: Border.all(color: bt.ruleStrong),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: bt.ink2,
            // tabular figures keep the chip width stable as the value ticks up.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

enum _Variant { compact, detailed }

String _formatUsd(double v) {
  // Two decimals for normal amounts, four when below a cent so per-call
  // costs of fractional cents still render meaningfully.
  if (v.abs() > 0 && v.abs() < 0.01) {
    return '\$${v.toStringAsFixed(4)}';
  }
  return '\$${v.toStringAsFixed(2)}';
}
