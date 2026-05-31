import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/transactions_client.dart';
import '../theme/app_theme.dart';
import 'ai_promo.dart';
import 'ai_spend_chip.dart';
import 'cat_icon.dart';
import 'glass.dart';
import 'import_progress_modal.dart';

/// Statement upload affordance. Tap → file picker → opens
/// [ImportProgressModal], which awaits the upload and shows in-progress /
/// success / error panels. [onImported] fires after the modal closes so
/// AppShell refetches.
///
/// CSV is always accepted (no AI needed, no tokens billed). When [aiEnabled]
/// is true the picker also accepts PDF + image formats and the upload is
/// routed to the AI parser automatically based on the file extension. When
/// AI is off the dropzone renders a green [AiPromo] above it inviting the
/// user to turn AI on for broader file support.
class Dropzone extends StatefulWidget {
  const Dropzone({
    super.key,
    required this.client,
    required this.onImported,
    required this.hasCategories,
    required this.onOpenCategories,
    required this.aiEnabled,
    required this.aiReady,
    required this.aiSpentUsd,
    this.onOpenAccount,
    this.compact = false,
  });

  final bool compact;
  final TransactionsClient client;
  final Future<void> Function() onImported;

  /// Whether the user has set up any (non-Unknown) categories. When false,
  /// uploading is blocked and the dropzone shows a "set up categories" prompt
  /// — imports need somewhere to land.
  final bool hasCategories;

  /// Switches to the Categories tab — the CTA when [hasCategories] is false.
  final VoidCallback onOpenCategories;

  /// The AI feature flag is on.
  final bool aiEnabled;

  /// AI parsing is actually usable: AI on + provider key set + a model picked.
  /// When false, the dropzone accepts CSV only and nudges the user to finish
  /// setup. (CSV never needs AI, so it always works.)
  final bool aiReady;

  final double aiSpentUsd;

  /// Pushes the Account screen — used by the [AiPromo] CTA when AI is off.
  final VoidCallback? onOpenAccount;

  @override
  State<Dropzone> createState() => _DropzoneState();
}

// File extensions allowed when AI is on. CSV stays in the list because the
// CSV path is free; the picker accepts everything and we pick the parser
// from the extension at upload time.
const _kAiExtensions = ['csv', 'pdf', 'png', 'jpg', 'jpeg', 'webp', 'gif'];
const _kCsvOnlyExtensions = ['csv'];

class _DropzoneState extends State<Dropzone> {
  bool _hovered = false;

  Future<void> _pickAndUpload() async {
    // Only offer (and route through) AI parsing when it's actually usable.
    final extensions = widget.aiReady ? _kAiExtensions : _kCsvOnlyExtensions;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    // When AI is ready, every upload goes through the AI parser. Otherwise
    // only CSV is allowed (the picker enforces it) and the free CSV path runs.
    final parser = widget.aiReady ? 'ai' : 'csv';

    // Build one job per readable file. Files we couldn't read bytes for are
    // dropped with a note rather than silently skipped.
    final jobs = <ImportJob>[];
    final unreadable = <String>[];
    for (final file in picked.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        unreadable.add(file.name);
        continue;
      }
      jobs.add(ImportJob(
        filename: file.name,
        upload: () => widget.client.import(
          bytes: bytes,
          filename: file.name,
          parser: parser,
        ),
      ));
    }

    if (!mounted) return;
    if (unreadable.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read: ${unreadable.join(', ')}')),
      );
    }
    if (jobs.isEmpty) return;

    await ImportProgressModal.show(
      context: context,
      jobs: jobs,
      aiEnabled: widget.aiEnabled,
    );
    await widget.onImported();
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    // Hard gate: no categories → no upload. Imports need somewhere to land,
    // and a fresh user importing into an empty tree just buries everything
    // under "Unknown". Point them at Categories first.
    if (!widget.hasCategories) {
      return _CategoriesNeeded(onOpenCategories: widget.onOpenCategories);
    }
    return Column(
      // `stretch` so the dropzone (and any AiPromo above it) claim the full
      // width of their parent. With `start` the GlassSurface's inner Column
      // shrunk to its intrinsic content width (~250 dp), leaving the
      // dropzone visibly narrower than the surrounding cards.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.aiReady) ...[
          if (widget.aiSpentUsd > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  AiSpendChip.detailed(
                    amountUsd: widget.aiSpentUsd,
                    label: 'spent on AI',
                  ),
                ],
              ),
            ),
        ] else if (widget.aiEnabled) ...[
          // AI is on but not finished setting up (no key and/or no model).
          // CSV still works below; nudge them to finish for PDF/image support.
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AiPromo.uploadSetup(onOpenAccount: widget.onOpenAccount),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AiPromo.upload(onOpenAccount: widget.onOpenAccount),
          ),
        ],
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _pickAndUpload,
            child: GlassSurface(
              tier: GlassTier.t1,
              radius: 18,
              dashedBorder: true,
              borderOverride:
                  _hovered ? bt.accent.withValues(alpha: 0.6) : bt.glassBorderStrong,
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 16 : 20,
                vertical: widget.compact ? 20 : 28,
              ),
              // Center fills both axes inside the GlassSurface's content
              // slot; without it, the inner Column shrinks to its widest
              // child and Stack pins that block to its top-start anchor,
              // making the icon + title sit visibly left of centre.
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GradientIconTile(
                      size: 48,
                      radius: 14,
                      child: BudgetIcons.build('upload',
                          size: 20, strokeWidth: 1.8, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Drop a statement',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: bt.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.aiReady
                          ? 'CSV, PDF, or image — parsed by AI · pick one or more'
                          : 'CSV — date, merchant, amount · pick one or more',
                      style: TextStyle(fontSize: 12, color: bt.ink3),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Blocked-upload state shown when the user has no categories yet. Mirrors the
/// dropzone's framed look but is inert — the CTA sends them to Categories.
class _CategoriesNeeded extends StatelessWidget {
  const _CategoriesNeeded({required this.onOpenCategories});

  final VoidCallback onOpenCategories;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return GlassSurface(
      tier: GlassTier.t1,
      radius: 18,
      dashedBorder: true,
      borderOverride: bt.glassBorderStrong,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientIconTile(
              size: 48,
              radius: 14,
              child: BudgetIcons.build('folder',
                  size: 20, strokeWidth: 1.8, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              'Set up categories first',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: bt.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'Create at least one category before importing, so your '
              'transactions have somewhere to land.',
              style: TextStyle(fontSize: 12, color: bt.ink3, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            GlassButton(
              label: 'Set up categories',
              onPressed: onOpenCategories,
              variant: GlassButtonVariant.primary,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}
