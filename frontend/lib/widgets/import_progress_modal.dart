import 'package:flutter/material.dart';

import '../services/api_base.dart';
import '../services/transactions_client.dart';
import '../theme/app_theme.dart';
import 'budget_card.dart';
import 'cat_icon.dart';

/// Blocking dialog for the statement-import flow. Opens the moment the user
/// picks a file and stays up through three internal states:
///
/// 1. **inProgress** — indeterminate `LinearProgressIndicator`, filename, and
///    a status line that nudges the user about wait time when AI parsing is
///    on. No fake percentages — we don't have phase-streaming from the
///    backend, and pretending we do would be dishonest.
/// 2. **success** — stats grid (Added / Duplicates / Failed / Categorized)
///    with a contextual headline. Distinguishes the dedupe re-upload case
///    ("All rows already imported") from a true "nothing parsed" case.
/// 3. **error** — friendly headline keyed off `ApiException.code`, raw
///    message in a code block as fallback.
///
/// Static [show] kicks the whole thing off — caller passes a closure that
/// performs the actual upload and returns an [ImportResult].
class ImportProgressModal extends StatefulWidget {
  const ImportProgressModal._({
    required this.upload,
    required this.filename,
    required this.aiEnabled,
  });

  final Future<ImportResult> Function() upload;
  final String filename;
  final bool aiEnabled;

  static Future<void> show({
    required BuildContext context,
    required Future<ImportResult> Function() upload,
    required String filename,
    required bool aiEnabled,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportProgressModal._(
        upload: upload,
        filename: filename,
        aiEnabled: aiEnabled,
      ),
    );
  }

  @override
  State<ImportProgressModal> createState() => _ImportProgressModalState();
}

enum _Phase { inProgress, success, error }

class _ImportProgressModalState extends State<ImportProgressModal> {
  _Phase _phase = _Phase.inProgress;
  ImportResult? _result;
  Object? _error;
  bool _showRowErrors = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final r = await widget.upload();
      if (!mounted) return;
      setState(() {
        _result = r;
        _phase = _Phase.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: BudgetCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: switch (_phase) {
            _Phase.inProgress => _InProgressBody(
                filename: widget.filename,
                aiEnabled: widget.aiEnabled,
                bt: bt,
              ),
            _Phase.success => _SuccessBody(
                result: _result!,
                showRowErrors: _showRowErrors,
                onToggleRowErrors: () =>
                    setState(() => _showRowErrors = !_showRowErrors),
                onClose: () => Navigator.of(context).pop(),
                bt: bt,
              ),
            _Phase.error => _ErrorBody(
                error: _error!,
                onClose: () => Navigator.of(context).pop(),
                bt: bt,
              ),
          },
        ),
      ),
    );
  }
}

// ── In-progress ─────────────────────────────────────────────────────────────

class _InProgressBody extends StatelessWidget {
  const _InProgressBody({
    required this.filename,
    required this.aiEnabled,
    required this.bt,
  });

  final String filename;
  final bool aiEnabled;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            BudgetIcons.build('upload',
                size: 18, strokeWidth: 1.8, color: bt.ink2),
            const SizedBox(width: 10),
            Text(
              'Importing statement',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: bt.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          child: LinearProgressIndicator(
            minHeight: 6,
            backgroundColor: bt.glass2,
            valueColor: AlwaysStoppedAnimation(bt.accent),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Processing your statement…',
          style: TextStyle(fontSize: 13, color: bt.ink2, height: 1.4),
        ),
        if (aiEnabled) ...[
          const SizedBox(height: 4),
          Text(
            'AI parsing can take 5–30 seconds.',
            style: TextStyle(fontSize: 12, color: bt.ink4, height: 1.4),
          ),
        ],
        const SizedBox(height: 12),
        _Filename(filename: filename, bt: bt),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Success ─────────────────────────────────────────────────────────────────

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({
    required this.result,
    required this.showRowErrors,
    required this.onToggleRowErrors,
    required this.onClose,
    required this.bt,
  });

  final ImportResult result;
  final bool showRowErrors;
  final VoidCallback onToggleRowErrors;
  final VoidCallback onClose;
  final BudgetTheme bt;

  String get _headline {
    if (result.rowsInserted > 0) {
      return 'Imported ${result.rowsInserted} '
          '${result.rowsInserted == 1 ? "transaction" : "transactions"}';
    }
    if (result.rowsSkippedDuplicate > 0) return 'All rows already imported';
    if (result.rowsParsed == 0) return 'No transactions detected';
    return 'Nothing imported';
  }

  @override
  Widget build(BuildContext context) {
    final categorization = result.categorization;
    final showCategorized = categorization != null && categorization.error == null;
    final categorizeKeyMissing =
        categorization != null && categorization.error == 'ai_key_missing';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: bt.posBg,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                border: Border.all(color: bt.posBorder),
              ),
              alignment: Alignment.center,
              child: BudgetIcons.build('check',
                  size: 14, strokeWidth: 2, color: bt.pos),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _headline,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: bt.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _StatsGrid(
          stats: [
            _Stat(label: 'Added', value: result.rowsInserted, color: bt.pos),
            if (result.rowsSkippedDuplicate > 0)
              _Stat(label: 'Duplicates', value: result.rowsSkippedDuplicate, color: bt.ink3),
            if (result.rowsFailed > 0)
              _Stat(label: 'Failed', value: result.rowsFailed, color: bt.warn),
            if (showCategorized)
              _Stat(label: 'Categorized', value: categorization.categorized, color: bt.ink3),
          ],
          bt: bt,
        ),
        if (result.rowsFailed > 0) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onToggleRowErrors,
            child: Row(
              children: [
                BudgetIcons.build(showRowErrors ? 'chevron-down' : 'chevron-right',
                    size: 12, strokeWidth: 1.8, color: bt.ink4),
                const SizedBox(width: 6),
                Text(
                  '${result.rowsFailed} row${result.rowsFailed == 1 ? "" : "s"} '
                  'couldn\'t be parsed and were skipped',
                  style: TextStyle(fontSize: 12, color: bt.ink4),
                ),
              ],
            ),
          ),
          if (showRowErrors) ...[
            const SizedBox(height: 8),
            _ErrorList(errors: result.errors.take(3).toList(), bt: bt),
          ],
        ],
        if (categorizeKeyMissing) ...[
          const SizedBox(height: 12),
          Text(
            'Auto-categorize was skipped — set an API key in Account to enable it.',
            style: TextStyle(fontSize: 12, color: bt.ink4, height: 1.45),
          ),
        ],
        const SizedBox(height: 18),
        _PrimaryButton(label: 'Done', onTap: onClose, bt: bt),
      ],
    );
  }
}

class _Stat {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.bt});
  final List<_Stat> stats;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bt.surface2,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(color: bt.rule),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 28, color: bt.rule),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${stats[i].value}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: stats[i].color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats[i].label,
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.12 * 10.5,
                      fontWeight: FontWeight.w500,
                      color: bt.ink4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.errors, required this.bt});
  final List<Map<String, dynamic>> errors;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bt.surface2,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        border: Border.all(color: bt.rule),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: errors.map((e) {
          final row = e['row'];
          final reason = e['reason'] ?? '(no detail)';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              row != null ? 'row $row — $reason' : '$reason',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: bt.ink3,
                height: 1.5,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Error ───────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.error,
    required this.onClose,
    required this.bt,
  });

  final Object error;
  final VoidCallback onClose;
  final BudgetTheme bt;

  ({String headline, String body}) get _content {
    if (error is ApiException) {
      final e = error as ApiException;
      switch (e.code) {
        case 'csv_parse_failed':
          return (
            headline: "Couldn't read your CSV",
            body: e.message,
          );
        case 'ai_key_missing':
          return (
            headline: 'AI features need an API key',
            body: 'Set one in Account, then try again.',
          );
        case 'feature_disabled':
          return (
            headline: 'AI parsing is turned off',
            body: 'Enable AI features in Account to parse PDFs.',
          );
        case 'unsupported_file_type':
          return (
            headline: "Couldn't read this file",
            body: 'Supported: PDF, image (PNG/JPEG/WebP/GIF), CSV. '
                'No tokens were used — nothing was sent to the model.',
          );
        case 'unsupported_content':
          return (
            headline: 'Selected model can\'t read this',
            body: '${e.message} '
                'PDF uploads work on Anthropic and Google models.',
          );
        default:
          return (
            headline: 'Import failed',
            body: e.message,
          );
      }
    }
    return (
      headline: 'Import failed',
      body: error.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _content;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: bt.negBg,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                border: Border.all(color: bt.negBorder),
              ),
              alignment: Alignment.center,
              child: BudgetIcons.build('alert',
                  size: 14, strokeWidth: 2, color: bt.neg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.headline,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: bt.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: bt.surface2,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            border: Border.all(color: bt.rule),
          ),
          padding: const EdgeInsets.all(12),
          child: Text(
            c.body,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: bt.ink2,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'No transactions were saved.',
          style: TextStyle(fontSize: 12, color: bt.ink4),
        ),
        const SizedBox(height: 18),
        _PrimaryButton(label: 'Close', onTap: onClose, bt: bt),
      ],
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────

class _Filename extends StatelessWidget {
  const _Filename({required this.filename, required this.bt});
  final String filename;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Text(
      filename,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11.5,
        color: bt.ink4,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    required this.bt,
  });
  final String label;
  final VoidCallback onTap;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bt.ink,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: bt.bg,
            ),
          ),
        ),
      ),
    );
  }
}
