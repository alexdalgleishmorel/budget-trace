import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'cat_icon.dart';
import 'glass.dart';

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

  /// Upload Dropzone when AI is ON but not finished setting up (no provider
  /// key and/or no model picked). CSV still works; this nudges the rest.
  static const uploadSetupHeadline = 'Finish AI setup to upload PDFs & images';
  static const uploadSetupBody =
      'Choose a provider, add its API key, and pick a model in Account to parse '
      'PDFs, screenshots, and images (and auto-categorize). CSV uploads work now.';

  /// Insights tab when AI is ON but no model is picked yet.
  static const insightsSetupHeadline = 'Pick a model to use Insights';
  static const insightsSetupBody =
      'You\'ve enabled AI — now choose a provider, add its API key, and pick a '
      'model in Account, then come back to chat about your spending.';

  /// CTA used on every variant.
  static const ctaLabel = 'Open Account';
}

/// Visual size of an [AiPromo]. `compact` is a horizontal icon-and-text strip
/// for use inline next to other widgets; `fullPage` is a centered, vertically
/// stacked empty state for use as a whole tab's content.
enum AiPromoVariant { compact, fullPage }

/// Glass-tier call-to-action promoting AI features. Every AI-disabled empty
/// state should reach for this widget rather than rolling its own banner.
class AiPromo extends StatelessWidget {
  const AiPromo({
    super.key,
    required this.headline,
    required this.body,
    this.onOpenAccount,
    this.variant = AiPromoVariant.compact,
  });

  factory AiPromo.upload({Key? key, VoidCallback? onOpenAccount}) => AiPromo(
        key: key,
        headline: AiPromoCopy.uploadHeadline,
        body: AiPromoCopy.uploadBody,
        onOpenAccount: onOpenAccount,
        variant: AiPromoVariant.compact,
      );

  factory AiPromo.uploadSetup({Key? key, VoidCallback? onOpenAccount}) =>
      AiPromo(
        key: key,
        headline: AiPromoCopy.uploadSetupHeadline,
        body: AiPromoCopy.uploadSetupBody,
        onOpenAccount: onOpenAccount,
        variant: AiPromoVariant.compact,
      );

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
    return GlassSurface(
      tier: GlassTier.t1,
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BudgetIcons.build(
            'sparkle',
            size: 14,
            strokeWidth: 1.6,
            color: bt.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: bt.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    color: bt.ink2,
                    height: 1.45,
                  ),
                ),
                if (onOpenAccount != null) ...[
                  const SizedBox(height: 10),
                  GlassButton(
                    label: AiPromoCopy.ctaLabel,
                    onPressed: onOpenAccount,
                    variant: GlassButtonVariant.primary,
                    compact: true,
                  ),
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
    final card = GlassSurface(
      tier: GlassTier.t1,
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GradientIconTile(
            size: 80,
            radius: 24,
            child: BudgetIcons.build(
              'sparkle',
              size: 32,
              strokeWidth: 1.8,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.015 * 22,
              color: bt.ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: bt.ink3,
              height: 1.55,
            ),
          ),
          if (onOpenAccount != null) ...[
            const SizedBox(height: 20),
            GlassButton(
              label: AiPromoCopy.ctaLabel,
              onPressed: onOpenAccount,
              variant: GlassButtonVariant.primary,
            ),
          ],
        ],
      ),
    );

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
