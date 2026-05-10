import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/transactions_client.dart';
import '../theme/app_theme.dart';
import 'ai_spend_chip.dart';
import 'cat_icon.dart';
import 'import_progress_modal.dart';

/// Statement upload affordance. Tap → file picker → opens
/// [ImportProgressModal], which awaits the upload and shows in-progress /
/// success / error panels. [onImported] fires after the modal closes so
/// AppShell refetches.
///
/// CSV is always allowed. When [aiEnabled] is true, a small toggle appears
/// underneath that, when on, sends `parser=ai` and accepts PDFs. The
/// running cumulative AI spend is rendered as an [AiSpendChip] above the
/// dropzone — this is the only AI surface besides the Insights chat, so
/// it's where the global spend metric lives now (was previously in the
/// side nav).
class Dropzone extends StatefulWidget {
  const Dropzone({
    super.key,
    required this.client,
    required this.onImported,
    required this.aiEnabled,
    required this.aiSpentUsd,
    required this.aiSpentEstimated,
    this.compact = false,
  });

  final bool compact;
  final TransactionsClient client;
  final Future<void> Function() onImported;
  final bool aiEnabled;
  final double aiSpentUsd;
  final bool aiSpentEstimated;

  @override
  State<Dropzone> createState() => _DropzoneState();
}

class _DropzoneState extends State<Dropzone> {
  bool _hovered = false;
  bool _useAi = false;

  Future<void> _pickAndUpload() async {
    final extensions = _useAi ? ['csv', 'pdf'] : ['csv'];
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

    final parser = _useAi ? 'ai' : 'csv';
    if (!mounted) return;
    await ImportProgressModal.show(
      context: context,
      filename: file.name,
      aiEnabled: _useAi,
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
    final showChip = widget.aiEnabled || widget.aiSpentUsd > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showChip) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                AiSpendChip.detailed(
                  amountUsd: widget.aiSpentUsd,
                  isEstimate: widget.aiSpentEstimated,
                  label: 'spent on Anthropic',
                ),
              ],
            ),
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
                _useAi ? 'CSV or PDF — parsed by AI' : 'CSV — date, merchant, amount columns',
                style: TextStyle(fontSize: 12, color: bt.ink4),
                textAlign: TextAlign.center,
              ),
              if (widget.aiEnabled) ...[
                const SizedBox(height: 10),
                _AiToggle(
                  value: _useAi,
                  onChanged: (v) => setState(() => _useAi = v),
                  bt: bt,
                ),
              ],
            ],
          ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AiToggle extends StatelessWidget {
  const _AiToggle({required this.value, required this.onChanged, required this.bt});
  final bool value;
  final ValueChanged<bool> onChanged;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    // Stop the parent GestureDetector from intercepting the tap.
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? bt.ink : bt.surface,
          border: Border.all(color: bt.ruleStrong),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BudgetIcons.build(
              value ? 'check' : 'sparkle',
              size: 12,
              strokeWidth: 2,
              color: value ? bt.bg : bt.ink3,
            ),
            const SizedBox(width: 6),
            Text(
              'Use AI parsing',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: value ? bt.bg : bt.ink2,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: value ? bt.bg.withValues(alpha: 0.18) : bt.warnBg,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
              ),
              child: Text(
                'PREMIUM',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.08 * 9,
                  color: value ? bt.bg : bt.warn,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
