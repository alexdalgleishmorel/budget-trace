import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pill-shaped readout of an AI spend amount in USD.
///
/// Two flavours:
///   * [AiSpendChip.compact] — just `$X.XX` (with a leading `~` when the
///     value is locally estimated rather than reported by Anthropic's
///     Admin API). Used in the side nav / mobile settings row.
///   * [AiSpendChip.detailed] — `$X.XX <label>`, optionally with an `(est.)`
///     suffix when [isEstimate] is true. Used in the Account screen and
///     the Insights chat header.
class AiSpendChip extends StatelessWidget {
  const AiSpendChip._({
    required this.amountUsd,
    required this.isEstimate,
    required _Variant variant,
    this.label,
  }) : _variant = variant;

  factory AiSpendChip.compact({
    required double amountUsd,
    required bool isEstimate,
  }) =>
      AiSpendChip._(
        amountUsd: amountUsd,
        isEstimate: isEstimate,
        variant: _Variant.compact,
      );

  factory AiSpendChip.detailed({
    required double amountUsd,
    required bool isEstimate,
    required String label,
  }) =>
      AiSpendChip._(
        amountUsd: amountUsd,
        isEstimate: isEstimate,
        variant: _Variant.detailed,
        label: label,
      );

  final double amountUsd;
  final bool isEstimate;
  final _Variant _variant;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final amount = _formatUsd(amountUsd);
    final text = switch (_variant) {
      _Variant.compact => isEstimate ? '~$amount' : amount,
      _Variant.detailed =>
        '$amount ${label ?? ''}${isEstimate ? ' (est.)' : ''}'.trim(),
    };
    return Tooltip(
      message: isEstimate
          ? 'Estimated from token usage and the price of the selected model.'
          : 'Reported by the Anthropic Admin API.',
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
