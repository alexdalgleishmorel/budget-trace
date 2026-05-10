import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'cat_icon.dart';

/// Canonical copy used to invite the user to turn on AI features. Reuse
/// these strings from every surface that wants to promote AI rather than
/// inventing new wording per location — keeps the messaging consistent and
/// makes it cheap to retune from one place.
class AiPromoCopy {
  AiPromoCopy._();

  /// Full-page empty state on the Insights tab when `me.features.ai` is off.
  static const insightsHeadline = 'Enable AI to use Insights';
  static const insightsBody =
      'Insights lets you chat with an AI about your spending — ask "where am '
      'I overspending?", "what trended up last quarter?", or "how much can I '
      'save?" The assistant can also rename merchants, recategorize, and edit '
      'transactions for you. Enable AI features in Account to start.';

  /// Inline banner inside the upload Dropzone when AI is off.
  static const uploadHeadline = 'Upload any file type with AI';
  static const uploadBody =
      'Turn on AI features in Account to drop in PDFs, screenshots, or images '
      'of statements. New imports are also auto-categorized.';

  /// CTA used on every variant.
  static const ctaLabel = 'Open Account';
}

/// Visual size of an [AiPromo]. `compact` is a horizontal icon-and-text strip
/// for use inline next to other widgets; `fullPage` is a centered, vertically
/// stacked empty state for use as a whole tab's content.
enum AiPromoVariant { compact, fullPage }

/// Green-themed call-to-action promoting AI features. The canonical visual
/// for "turn on AI to unlock this surface" anywhere in the app — every
/// AI-disabled empty state should reach for this widget rather than rolling
/// its own banner.
class AiPromo extends StatelessWidget {
  const AiPromo({
    super.key,
    required this.headline,
    required this.body,
    this.onOpenAccount,
    this.variant = AiPromoVariant.compact,
  });

  /// Inline banner for use inside another widget (e.g. inside the Dropzone
  /// card). Uses [AiPromoCopy.uploadHeadline] / [uploadBody] by default.
  factory AiPromo.upload({Key? key, VoidCallback? onOpenAccount}) => AiPromo(
        key: key,
        headline: AiPromoCopy.uploadHeadline,
        body: AiPromoCopy.uploadBody,
        onOpenAccount: onOpenAccount,
        variant: AiPromoVariant.compact,
      );

  /// Full-page empty state — centered, with the CTA. Used by Insights when
  /// AI is disabled.
  factory AiPromo.insights({Key? key, VoidCallback? onOpenAccount}) => AiPromo(
        key: key,
        headline: AiPromoCopy.insightsHeadline,
        body: AiPromoCopy.insightsBody,
        onOpenAccount: onOpenAccount,
        variant: AiPromoVariant.fullPage,
      );

  final String headline;
  final String body;
  final VoidCallback? onOpenAccount;
  final AiPromoVariant variant;

  @override
  Widget build(BuildContext context) {
    if (variant == AiPromoVariant.fullPage) {
      return _FullPageBody(
        headline: headline,
        body: body,
        onOpenAccount: onOpenAccount,
      );
    }
    return _CompactBody(
      headline: headline,
      body: body,
      onOpenAccount: onOpenAccount,
    );
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({
    required this.headline,
    required this.body,
    required this.onOpenAccount,
  });

  final String headline;
  final String body;
  final VoidCallback? onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bt.posBg,
        borderRadius: BudgetRadius.smBR,
        border: Border.all(color: bt.posBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BudgetIcons.build(
            'sparkle',
            size: 14,
            strokeWidth: 1.8,
            color: bt.pos,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: bt.pos,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: bt.ink2,
                    height: 1.45,
                  ),
                ),
                if (onOpenAccount != null) ...[
                  const SizedBox(height: 10),
                  _OpenAccountButton(onTap: onOpenAccount!, big: false),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullPageBody extends StatelessWidget {
  const _FullPageBody({
    required this.headline,
    required this.body,
    required this.onOpenAccount,
  });

  final String headline;
  final String body;
  final VoidCallback? onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    // Vertical layout: icon on top, headline, body, CTA. The Column shrink-
    // wraps so the green Container's height matches its content rather than
    // filling the available space.
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: bt.posBg,
        borderRadius: BudgetRadius.smBR,
        border: Border.all(color: bt.posBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BudgetIcons.build(
            'sparkle',
            size: 22,
            strokeWidth: 1.8,
            color: bt.pos,
          ),
          const SizedBox(height: 12),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: bt.pos,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: bt.ink2,
              height: 1.5,
            ),
          ),
          if (onOpenAccount != null) ...[
            const SizedBox(height: 18),
            _OpenAccountButton(onTap: onOpenAccount!, big: true),
          ],
        ],
      ),
    );

    // Center in both axes within the parent. SingleChildScrollView keeps the
    // banner readable on very short viewports without forcing a tight height
    // onto the Container (which would otherwise stretch the green box to
    // fill the page).
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: card,
          ),
        ),
      ),
    );
  }
}

class _OpenAccountButton extends StatelessWidget {
  const _OpenAccountButton({required this.onTap, required this.big});
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: big ? 14 : 10,
          vertical: big ? 9 : 6,
        ),
        decoration: BoxDecoration(
          color: bt.pos,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(
          AiPromoCopy.ctaLabel,
          style: TextStyle(
            fontSize: big ? 12.5 : 11.5,
            fontWeight: FontWeight.w600,
            color: bt.bg,
          ),
        ),
      ),
    );
  }
}
