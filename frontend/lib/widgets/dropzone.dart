import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/features_client.dart';
import '../services/transactions_client.dart';
import '../theme/app_theme.dart';
import 'cat_icon.dart';

/// Statement upload affordance. Tap → file picker → POST /transactions/import →
/// SnackBar summary, then [onImported] (typically a refetch trigger from
/// AppShell).
///
/// CSV is always allowed. When [features.aiImport] is true, a small toggle
/// appears underneath that, when on, sends `parser=ai` and accepts PDFs.
class Dropzone extends StatefulWidget {
  const Dropzone({
    super.key,
    required this.client,
    required this.onImported,
    required this.features,
    this.compact = false,
  });

  final bool compact;
  final TransactionsClient client;
  final Future<void> Function() onImported;
  final FeatureFlags features;

  @override
  State<Dropzone> createState() => _DropzoneState();
}

class _DropzoneState extends State<Dropzone> {
  bool _hovered = false;
  bool _busy = false;
  bool _useAi = false;

  Future<void> _pickAndUpload() async {
    if (_busy) return;
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
      _showSnack('Could not read file bytes.');
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await widget.client.import(
        bytes: bytes,
        filename: file.name,
        parser: _useAi ? 'ai' : 'csv',
      );
      _showSnack(result.summary);
      await widget.onImported();
    } catch (e) {
      _showSnack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return MouseRegion(
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
                  child: _busy
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : BudgetIcons.build('upload',
                          size: 20, strokeWidth: 1.8, color: bt.ink2),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _busy ? 'Uploading…' : 'Drop a statement',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: bt.ink),
              ),
              const SizedBox(height: 2),
              Text(
                _useAi ? 'CSV or PDF — parsed by AI' : 'CSV — date, merchant, amount columns',
                style: TextStyle(fontSize: 12, color: bt.ink4),
                textAlign: TextAlign.center,
              ),
              if (widget.features.aiImport) ...[
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
