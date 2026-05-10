import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/transactions_client.dart';
import '../theme/app_theme.dart';
import 'ai_promo.dart';
import 'ai_spend_chip.dart';
import 'cat_icon.dart';
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
    required this.aiEnabled,
    required this.aiSpentUsd,
    this.onOpenAccount,
    this.compact = false,
  });

  final bool compact;
  final TransactionsClient client;
  final Future<void> Function() onImported;
  final bool aiEnabled;
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
    final extensions = widget.aiEnabled ? _kAiExtensions : _kCsvOnlyExtensions;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read file bytes.')),
      );
      return;
    }

    // When AI is on, every upload goes through the AI parser — no extension
    // routing. When AI is off, only CSV is allowed (the picker enforces it)
    // and the free CSV path runs.
    final parser = widget.aiEnabled ? 'ai' : 'csv';

    if (!mounted) return;
    await ImportProgressModal.show(
      context: context,
      filename: file.name,
      aiEnabled: widget.aiEnabled,
      upload: () => widget.client.import(
        bytes: bytes,
        filename: file.name,
        parser: parser,
      ),
    );
    await widget.onImported();
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.aiEnabled) ...[
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 16 : 20,
                vertical: widget.compact ? 20 : 28,
              ),
              decoration: BoxDecoration(
                color: bt.surface2,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                border: Border.all(
                  color: _hovered ? bt.ink3 : bt.ruleStrong,
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: bt.surface,
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      border: Border.all(color: bt.ruleStrong),
                    ),
                    child: Center(
                      child: BudgetIcons.build('upload',
                          size: 20, strokeWidth: 1.8, color: bt.ink2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Drop a statement',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: bt.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.aiEnabled
                        ? 'CSV, PDF, or image — parsed by AI'
                        : 'CSV — date, merchant, amount columns',
                    style: TextStyle(fontSize: 12, color: bt.ink4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
