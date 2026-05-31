import 'package:flutter/material.dart';

import '../services/api_base.dart';
import '../services/transactions_client.dart';
import '../theme/app_theme.dart';
import 'budget_card.dart';
import 'cat_icon.dart';

/// One file to import: its display name and the closure that uploads it.
class ImportJob {
  const ImportJob({required this.filename, required this.upload});

  final String filename;
  final Future<ImportResult> Function() upload;
}

/// Outcome of a single file — exactly one of [result] / [error] is set.
class _Outcome {
  const _Outcome({required this.filename, this.result, this.error});

  final String filename;
  final ImportResult? result;
  final Object? error;

  bool get ok => result != null;
}

/// Blocking dialog for the statement-import flow. Opens the moment the user
/// picks one or more files and stays up through two internal states:
///
/// 1. **inProgress** — indeterminate `LinearProgressIndicator`, the file
///    currently uploading ("Importing file 2 of 3 — …"), and a wait-time
///    nudge when AI parsing is on. Files upload sequentially, each reusing the
///    single-file `POST /transactions/import` endpoint; a file that fails is
///    recorded and the rest still run.
/// 2. **done** — aggregate stats (Added / Duplicates / Failed / Categorized)
///    summed across files, with a contextual headline and, when more than one
///    file was selected or any file failed, a per-file breakdown.
///
/// Static [show] kicks the whole thing off — the caller passes the list of
/// [ImportJob]s to run.
class ImportProgressModal extends StatefulWidget {
  const ImportProgressModal._({
    required this.jobs,
    required this.aiEnabled,
  });

  final List<ImportJob> jobs;
  final bool aiEnabled;

  static Future<void> show({
    required BuildContext context,
    required List<ImportJob> jobs,
    required bool aiEnabled,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportProgressModal._(
        jobs: jobs,
        aiEnabled: aiEnabled,
      ),
    );
  }

  @override
  State<ImportProgressModal> createState() => _ImportProgressModalState();
}

enum _Phase { inProgress, done }

class _ImportProgressModalState extends State<ImportProgressModal> {
  _Phase _phase = _Phase.inProgress;
  final List<_Outcome> _outcomes = [];
  int _currentIndex = 0;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (var i = 0; i < widget.jobs.length; i++) {
      if (!mounted) return;
      setState(() => _currentIndex = i);
      final job = widget.jobs[i];
      try {
        final r = await job.upload();
        _outcomes.add(_Outcome(filename: job.filename, result: r));
      } catch (e) {
        // A single file failing doesn't abort the batch.
        _outcomes.add(_Outcome(filename: job.filename, error: e));
      }
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.done);
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
                total: widget.jobs.length,
                currentIndex: _currentIndex,
                filename: widget.jobs[_currentIndex].filename,
                aiEnabled: widget.aiEnabled,
                bt: bt,
              ),
            _Phase.done => _SummaryBody(
                outcomes: _outcomes,
                showDetails: _showDetails,
                onToggleDetails: () =>
                    setState(() => _showDetails = !_showDetails),
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
    required this.total,
    required this.currentIndex,
    required this.filename,
    required this.aiEnabled,
    required this.bt,
  });

  final int total;
  final int currentIndex;
  final String filename;
  final bool aiEnabled;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    final multi = total > 1;
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
              multi ? 'Importing statements' : 'Importing statement',
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
          multi
              ? 'Importing file ${currentIndex + 1} of $total…'
              : 'Processing your statement…',
          style: TextStyle(fontSize: 13, color: bt.ink2, height: 1.4),
        ),
        if (aiEnabled) ...[
          const SizedBox(height: 4),
          Text(
            'AI parsing can take 5–30 seconds per file.',
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

// ── Summary (aggregate of all files) ─────────────────────────────────────────

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.outcomes,
    required this.showDetails,
    required this.onToggleDetails,
    required this.onClose,
    required this.bt,
  });

  final List<_Outcome> outcomes;
  final bool showDetails;
  final VoidCallback onToggleDetails;
  final VoidCallback onClose;
  final BudgetTheme bt;

  int get _added =>
      outcomes.fold(0, (s, o) => s + (o.result?.rowsInserted ?? 0));
  int get _duplicates =>
      outcomes.fold(0, (s, o) => s + (o.result?.rowsSkippedDuplicate ?? 0));
  int get _failedRows =>
      outcomes.fold(0, (s, o) => s + (o.result?.rowsFailed ?? 0));
  int get _categorized => outcomes.fold(0, (s, o) {
        final c = o.result?.categorization;
        return s + (c != null && c.error == null ? c.categorized : 0);
      });
  int get _filesFailed => outcomes.where((o) => !o.ok).length;
  bool get _anyCategorized => outcomes.any((o) {
        final c = o.result?.categorization;
        return c != null && c.error == null;
      });
  bool get _anyKeyMissing => outcomes.any((o) {
        final c = o.result?.categorization;
        return c != null && c.error == 'ai_key_missing';
      });

  String get _headline {
    final fileCount = outcomes.length;
    final fileSuffix = fileCount > 1 ? ' from $fileCount files' : '';
    if (_added > 0) {
      return 'Imported $_added '
          '${_added == 1 ? "transaction" : "transactions"}$fileSuffix';
    }
    if (_filesFailed == outcomes.length) return 'Import failed';
    if (_duplicates > 0) return 'All rows already imported';
    return 'No transactions detected';
  }

  @override
  Widget build(BuildContext context) {
    final allFailed = _filesFailed == outcomes.length;
    final multi = outcomes.length > 1;
    // Show the per-file breakdown control when there's more than one file, or
    // when a single file failed and we have detail to expose.
    final hasDetail = multi || _filesFailed > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: allFailed ? bt.negBg : bt.posBg,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                border: Border.all(color: allFailed ? bt.negBorder : bt.posBorder),
              ),
              alignment: Alignment.center,
              child: BudgetIcons.build(allFailed ? 'alert' : 'check',
                  size: 14, strokeWidth: 2, color: allFailed ? bt.neg : bt.pos),
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
        if (!allFailed) ...[
          const SizedBox(height: 14),
          _StatsGrid(
            stats: [
              _Stat(label: 'Added', value: _added, color: bt.pos),
              if (_duplicates > 0)
                _Stat(label: 'Duplicates', value: _duplicates, color: bt.ink3),
              if (_failedRows > 0)
                _Stat(label: 'Failed', value: _failedRows, color: bt.warn),
              if (_anyCategorized)
                _Stat(label: 'Categorized', value: _categorized, color: bt.ink3),
            ],
            bt: bt,
          ),
        ],
        if (_filesFailed > 0) ...[
          const SizedBox(height: 12),
          Text(
            '$_filesFailed of ${outcomes.length} file'
            '${outcomes.length == 1 ? "" : "s"} couldn\'t be imported.',
            style: TextStyle(fontSize: 12, color: bt.warn, height: 1.45),
          ),
        ],
        if (_anyKeyMissing) ...[
          const SizedBox(height: 12),
          Text(
            'Auto-categorize was skipped — set an API key in Account to enable it.',
            style: TextStyle(fontSize: 12, color: bt.ink4, height: 1.45),
          ),
        ],
        if (hasDetail) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onToggleDetails,
            child: Row(
              children: [
                BudgetIcons.build(showDetails ? 'chevron-down' : 'chevron-right',
                    size: 12, strokeWidth: 1.8, color: bt.ink4),
                const SizedBox(width: 6),
                Text(
                  showDetails ? 'Hide per-file details' : 'Per-file details',
                  style: TextStyle(fontSize: 12, color: bt.ink4),
                ),
              ],
            ),
          ),
          if (showDetails) ...[
            const SizedBox(height: 8),
            _PerFileList(outcomes: outcomes, bt: bt),
          ],
        ],
        const SizedBox(height: 18),
        _PrimaryButton(label: 'Done', onTap: onClose, bt: bt),
      ],
    );
  }
}

/// One line per file: filename + its summary (or failure reason).
class _PerFileList extends StatelessWidget {
  const _PerFileList({required this.outcomes, required this.bt});
  final List<_Outcome> outcomes;
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
        children: [
          for (var i = 0; i < outcomes.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _PerFileRow(outcome: outcomes[i], bt: bt),
          ],
        ],
      ),
    );
  }
}

class _PerFileRow extends StatelessWidget {
  const _PerFileRow({required this.outcome, required this.bt});
  final _Outcome outcome;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    final ok = outcome.ok;
    final detail =
        ok ? outcome.result!.summary : friendlyImportError(outcome.error!).body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: BudgetIcons.build(ok ? 'check' : 'alert',
              size: 12, strokeWidth: 2, color: ok ? bt.pos : bt.neg),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                outcome.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: bt.ink2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                detail,
                style: TextStyle(fontSize: 11, color: bt.ink4, height: 1.4),
              ),
            ],
          ),
        ),
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

// ── Friendly error mapping (per file) ────────────────────────────────────────

/// Maps an import failure to a short headline + body. Shared by the per-file
/// breakdown so an `ApiException.code` becomes human-readable.
({String headline, String body}) friendlyImportError(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'csv_parse_failed':
        return (headline: "Couldn't read your CSV", body: error.message);
      case 'ai_key_missing':
        return (
          headline: 'AI features need an API key',
          body: 'Set one in Account, then try again.',
        );
      case 'no_model_selected':
        return (
          headline: 'Pick an AI model',
          body: 'Choose a provider, fetch its models, and pick one in Account, '
              'then try again. (CSV uploads work without a model.)',
        );
      case 'feature_disabled':
        return (
          headline: 'AI parsing is turned off',
          body: 'Enable AI features in Account to parse PDFs.',
        );
      case 'unsupported_file_type':
        return (
          headline: "Couldn't read this file",
          body: 'Supported: PDF, image (PNG/JPEG/WebP/GIF), CSV.',
        );
      case 'unsupported_content':
        return (
          headline: "Selected model can't read this",
          body: '${error.message} '
              'PDF uploads work on Anthropic and Google models.',
        );
      default:
        return (headline: 'Import failed', body: error.message);
    }
  }
  return (headline: 'Import failed', body: error.toString());
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
