import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_base.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Where the explainer modal points people to run the real app.
const String kDemoRepoUrl =
    'https://github.com/alexdalgleishmorel/budget-trace#readme';

/// Open the repo README in a new tab / the system browser. Best-effort —
/// silently no-ops if the platform can't launch a URL.
Future<void> _openRepo() async {
  final uri = Uri.parse(kDemoRepoUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// A slim, app-wide banner shown only in the static demo build ([kDemoMode]).
///
/// Tapping it opens an explainer describing what the demo is, that nothing is
/// persisted, that AI replies and uploads are mocked, and how to run the fully
/// functional app locally via Docker. On a normal build it renders nothing, so
/// it is safe to mount unconditionally in [AppShell].
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDemoMode) return const SizedBox.shrink();
    final bt = context.bt;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showInfo(context),
            child: GlassSurface(
              tier: GlassTier.t2,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: 'Demo version. ',
                          style: TextStyle(
                            color: bt.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text:
                              'Data resets on reload, and AI replies and upload results are mocked.',
                          style: TextStyle(color: bt.ink3),
                        ),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, height: 1.25),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Learn more',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: bt.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showGlassModal<void>(
      context: context,
      builder: (ctx) => _DemoInfoModal(onClose: () => Navigator.of(ctx).pop()),
    );
  }
}

class _DemoInfoModal extends StatelessWidget {
  const _DemoInfoModal({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final bodyStyle = TextStyle(color: bt.ink2, fontSize: 14, height: 1.45);
    final headingStyle = TextStyle(
      color: bt.ink,
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w600,
    );
    // Wrap in a transparent Material so the modal's plain Text inherits a
    // proper text style (otherwise Flutter paints the "no Material" yellow
    // underline under unstyled text).
    return Material(
      type: MaterialType.transparency,
      child: GlassModalShell(
        title: 'About this demo',
        onClose: onClose,
        footer: Row(
          children: [
            Expanded(
              child: GlassButton(
                label: 'Got it',
                variant: GlassButtonVariant.secondary,
                expand: true,
                onPressed: onClose,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassButton(
                label: 'Set it up on GitHub',
                variant: GlassButtonVariant.primary,
                expand: true,
                onPressed: _openRepo,
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This is a static, browser-only demo of Expense Visualizer. There is '
              'no real backend — the data, charts and account live entirely in '
              'memory, so:',
              style: bodyStyle,
            ),
            const SizedBox(height: 12),
            _Bullet(
              'Everything you change (categories, expenses, dashboards, widgets) '
              'resets when you reload the page — nothing is saved.',
            ),
            _Bullet(
              'The Insights AI is mocked: replies are pre-written examples, not a '
              'live model. They are labelled as such in the chat.',
            ),
            _Bullet(
              'File uploads are mocked too: an import reports success, but no real '
              'data is added.',
            ),
            _Bullet(
              'The data is a generated sample, not real transactions.',
            ),
            const SizedBox(height: 18),
            Text('Want the real thing?', style: headingStyle),
            const SizedBox(height: 8),
            Text(
              'The fully functional app runs locally with Docker (real backend, '
              'CSV/PDF import, and live AI once you add a provider key). Clone the '
              'repository and follow the setup in its main README:',
              style: bodyStyle,
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _openRepo,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        kDemoRepoUrl,
                        style: TextStyle(
                          color: bt.accent,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: bt.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.open_in_new, size: 15, color: bt.accent),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: bt.accent, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: bt.ink2, fontSize: 14, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
