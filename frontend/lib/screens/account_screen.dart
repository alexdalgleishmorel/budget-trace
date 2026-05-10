import 'package:flutter/material.dart';

import '../services/api_base.dart';
import '../services/me_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_spend_chip.dart';
import '../widgets/budget_card.dart';

/// Single-user settings page. Three sections:
///   • Features    — master AI toggle
///   • API key     — Anthropic key (masked, set/clear)
///   • Appearance  — system / light / dark
///
/// Every control bubbles its update through `MeClient.update()` immediately
/// and calls [onMeChanged] with the resulting [Me] so the parent rebuilds
/// with the new theme + flags.
class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.me,
    required this.client,
    required this.onMeChanged,
  });

  final Me me;
  final MeClient client;
  final ValueChanged<Me> onMeChanged;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Me _me;
  final _keyController = TextEditingController();
  final _adminKeyController = TextEditingController();
  bool _showKey = false;
  bool _showAdminKey = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _me = widget.me;
    // Save buttons reveal themselves the moment the user types into a key
    // field — listening on the controller is the cheapest way to drive that
    // without making the row a StatefulWidget.
    _keyController.addListener(_onTextChange);
    _adminKeyController.addListener(_onTextChange);
    _refresh();
  }

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    try {
      final me = await widget.client.get();
      if (!mounted) return;
      setState(() => _me = me);
      widget.onMeChanged(me);
    } catch (_) {
      // Stale `_me` is harmless — surface the error only on user-driven edits.
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _adminKeyController.dispose();
    super.dispose();
  }

  Future<void> _patch({
    FeatureFlags? features,
    String? theme,
    String? anthropicApiKey,
    bool apiKeyExplicit = false,
    String? anthropicAdminApiKey,
    bool adminKeyExplicit = false,
    String? anthropicModel,
    bool modelExplicit = false,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final me = await widget.client.update(
        features: features,
        theme: theme,
        anthropicApiKey: anthropicApiKey,
        apiKeyExplicit: apiKeyExplicit,
        anthropicAdminApiKey: anthropicAdminApiKey,
        adminKeyExplicit: adminKeyExplicit,
        anthropicModel: anthropicModel,
        modelExplicit: modelExplicit,
      );
      if (!mounted) return;
      setState(() => _me = me);
      widget.onMeChanged(me);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveKey() async {
    final v = _keyController.text.trim();
    if (v.isEmpty) return;
    await _patch(anthropicApiKey: v, apiKeyExplicit: true);
    _keyController.clear();
    setState(() => _showKey = false);
  }

  Future<void> _clearKey() async {
    await _patch(anthropicApiKey: null, apiKeyExplicit: true);
  }

  Future<void> _saveAdminKey() async {
    final v = _adminKeyController.text.trim();
    if (v.isEmpty) return;
    await _patch(anthropicAdminApiKey: v, adminKeyExplicit: true);
    _adminKeyController.clear();
    setState(() => _showAdminKey = false);
  }

  Future<void> _clearAdminKey() async {
    await _patch(anthropicAdminApiKey: null, adminKeyExplicit: true);
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Scaffold(
      backgroundColor: bt.bg,
      appBar: AppBar(
        title: const Text('Account'),
        backgroundColor: bt.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: bt.ink,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _AuthBanner(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 16),
          _Section(
            label: 'Features',
            child: _FeatureRow(
              value: _me.features.ai,
              busy: _saving,
              onChanged: (v) => _patch(features: FeatureFlags(ai: v)),
            ),
          ),
          // Everything below the AI toggle is gated on it. Flipping it off
          // hides the API key, spend chip, model picker, and admin key —
          // there's nothing useful you can configure when the master flag
          // is off, and showing them would be misleading (changes wouldn't
          // take effect until the user flipped it back on).
          if (_me.features.ai) ...[
            const SizedBox(height: 16),
            _Section(
              label: 'Anthropic API key',
              child: _ApiKeyRow(
                keyIsSet: _me.anthropicApiKeySet,
                controller: _keyController,
                showKey: _showKey,
                onToggleVisibility: () => setState(() => _showKey = !_showKey),
                onSave: _saving ? null : _saveKey,
                onClear: _saving || !_me.anthropicApiKeySet ? null : _clearKey,
                hint: 'sk-ant-…',
                hintWhenSet:
                    'Set. Used for AI parsing, auto-categorization, and chat.',
                hintWhenUnset:
                    'Not set — falls back to the ANTHROPIC_API_KEY env var.',
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              label: 'AI Spend',
              child: _SpendRow(me: _me),
            ),
          ],
          const SizedBox(height: 16),
          _Section(
            label: 'Appearance',
            child: _ThemeRow(
              value: _me.theme,
              onChanged: (v) => _patch(theme: v),
            ),
          ),
          if (_me.features.ai) ...[
            const SizedBox(height: 16),
            _ExpandableSection(
              label: 'Advanced settings',
              children: [
                _LabelledChild(
                  label: 'Model',
                  child: _ModelRow(
                    me: _me,
                    busy: _saving,
                    onPick: (id) =>
                        _patch(anthropicModel: id, modelExplicit: true),
                    onReset: () =>
                        _patch(anthropicModel: null, modelExplicit: true),
                  ),
                ),
                const SizedBox(height: 16),
                _LabelledChild(
                  label: 'Anthropic Admin API key',
                  child: _ApiKeyRow(
                    keyIsSet: _me.anthropicAdminApiKeySet,
                    controller: _adminKeyController,
                    showKey: _showAdminKey,
                    onToggleVisibility: () =>
                        setState(() => _showAdminKey = !_showAdminKey),
                    onSave: _saving ? null : _saveAdminKey,
                    onClear: _saving || !_me.anthropicAdminApiKeySet
                        ? null
                        : _clearAdminKey,
                    hint: 'sk-ant-admin-…',
                    hintWhenSet:
                        'Set. Spend total reflects actual costs from Anthropic\'s '
                        'billing API instead of locally estimated token cost.',
                    hintWhenUnset:
                        'Optional. When set, the spend total reflects actual costs '
                        'from Anthropic\'s billing API instead of the local estimate.',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: BudgetLabel(label),
        ),
        BudgetCard(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ],
    );
  }
}

/// Collapsible counterpart to [_Section]. Children render the same labelled
/// look as a `_Section` so the visual hierarchy doesn't break when expanded —
/// just wrap each in a [_LabelledChild].
class _ExpandableSection extends StatefulWidget {
  const _ExpandableSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              children: [
                Expanded(child: BudgetLabel(widget.label)),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: bt.ink4,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.children,
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          sizeCurve: Curves.easeOut,
        ),
      ],
    );
  }
}

/// Mirrors [_Section]'s label-above-card layout for use inside an
/// [_ExpandableSection], where the wrapping section already owns the toggle
/// header. Keeps each sub-control's own label distinct from the parent.
class _LabelledChild extends StatelessWidget {
  const _LabelledChild({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: BudgetLabel(label),
        ),
        BudgetCard(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ],
    );
  }
}

class _AuthBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bt.warnBg,
        borderRadius: BudgetRadius.smBR,
        border: Border.all(color: bt.warn.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: bt.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Single-user mode — auth is not yet implemented. Your Anthropic '
              'API key is stored unencrypted in local SQLite.',
              style: TextStyle(fontSize: 12, color: bt.ink2, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bt.negBg,
        borderRadius: BudgetRadius.smBR,
        border: Border.all(color: bt.negBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: bt.neg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 12, color: bt.ink2, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI features',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: bt.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Auto-categorize new imports, parse PDF/image statements, and '
                'enable the Insights chat.',
                style: TextStyle(fontSize: 12, color: bt.ink4, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          onChanged: busy ? null : onChanged,
        ),
      ],
    );
  }
}

class _ApiKeyRow extends StatelessWidget {
  const _ApiKeyRow({
    required this.keyIsSet,
    required this.controller,
    required this.showKey,
    required this.onToggleVisibility,
    required this.onSave,
    required this.onClear,
    required this.hint,
    required this.hintWhenSet,
    required this.hintWhenUnset,
  });

  final bool keyIsSet;
  final TextEditingController controller;
  final bool showKey;
  final VoidCallback onToggleVisibility;
  final VoidCallback? onSave;
  final VoidCallback? onClear;
  final String hint;
  final String hintWhenSet;
  final String hintWhenUnset;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    // Save is only relevant when the user has typed something — until then
    // the field shows just the masked text + show/hide affordance, no
    // commit affordance to clutter the row.
    final hasPendingChange = controller.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: !showKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: keyIsSet ? 'Replace stored key…' : hint,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BudgetRadius.inputBR),
                  suffixIcon: IconButton(
                    tooltip: showKey ? 'Hide' : 'Show',
                    icon: Icon(
                      showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: onToggleVisibility,
                  ),
                ),
                style: TextStyle(fontSize: 13, color: bt.ink),
              ),
            ),
            if (hasPendingChange) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSave,
                child: const Text('Save'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                keyIsSet ? hintWhenSet : hintWhenUnset,
                style: TextStyle(fontSize: 11.5, color: bt.ink4, height: 1.4),
              ),
            ),
            if (keyIsSet)
              TextButton(
                onPressed: onClear,
                child: const Text('Clear'),
              ),
          ],
        ),
      ],
    );
  }
}

class _SpendRow extends StatelessWidget {
  const _SpendRow({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final note = me.aiSpentSource == 'authoritative'
        ? 'Reported by Anthropic Admin API (cost report).'
        : 'Estimated from token usage and the price of the selected model. '
            'Add an Admin API key below for actual figures.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AiSpendChip.detailed(
              amountUsd: me.aiSpentUsd,
              isEstimate: me.isSpendEstimated,
              label: 'spent on Anthropic',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          note,
          style: TextStyle(fontSize: 11.5, color: bt.ink4, height: 1.4),
        ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.me,
    required this.busy,
    required this.onPick,
    required this.onReset,
  });

  final Me me;
  final bool busy;
  final ValueChanged<String> onPick;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final options = me.availableModels;
    // Guard against an unexpected model id (e.g. env-pinned model not in
    // MODEL_PRICES). Show the dropdown's current value as the resolved id
    // even if it's not in the list — Dart's DropdownButtonFormField requires
    // the value to be in items, so synthesise an entry if needed.
    final ids = options.map((m) => m.id).toSet();
    final hasCurrent = ids.contains(me.anthropicModel);
    final items = [
      ...options.map(
        (m) => DropdownMenuItem<String>(
          value: m.id,
          child: _ModelMenuItem(option: m),
        ),
      ),
      if (!hasCurrent)
        DropdownMenuItem<String>(
          value: me.anthropicModel,
          child: Text(
            me.anthropicModel,
            style: TextStyle(fontSize: 13, color: bt.ink2),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          // ValueKey re-mounts the form field whenever the resolved model
          // changes externally (e.g. "Reset to default") so the new
          // `initialValue` actually takes effect.
          key: ValueKey(me.anthropicModel),
          initialValue: me.anthropicModel,
          isDense: true,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BudgetRadius.inputBR),
          ),
          items: items,
          onChanged: busy ? null : (v) {
            if (v != null) onPick(v);
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'AI calls (chat, parser, auto-categorize) all use this model. '
                'Pricing affects the spend chip above.',
                style: TextStyle(fontSize: 11.5, color: bt.ink4, height: 1.4),
              ),
            ),
            TextButton(
              onPressed: busy ? null : onReset,
              child: const Text('Reset to default'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModelMenuItem extends StatelessWidget {
  const _ModelMenuItem({required this.option});

  final ModelOption option;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          option.displayName,
          style: TextStyle(fontSize: 13, color: bt.ink),
        ),
        const SizedBox(width: 8),
        Text(
          '\$${option.inputPerMtok.toStringAsFixed(0)}/MTok in · '
          '\$${option.outputPerMtok.toStringAsFixed(0)}/MTok out',
          style: TextStyle(fontSize: 11, color: bt.ink4),
        ),
      ],
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = [
    (key: 'system', label: 'System'),
    (key: 'light', label: 'Light'),
    (key: 'dark', label: 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      decoration: BoxDecoration(
        color: bt.surface2,
        borderRadius: BudgetRadius.btnBR,
        border: Border.all(color: bt.ruleStrong),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: _options.map((opt) {
          final active = opt.key == value;
          return Expanded(
            child: GestureDetector(
              onTap: active ? null : () => onChanged(opt.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: active ? bt.surface : Colors.transparent,
                  borderRadius: const BorderRadius.all(Radius.circular(9)),
                  border: Border.all(
                    color: active ? bt.rule : Colors.transparent,
                  ),
                ),
                child: Center(
                  child: Text(
                    opt.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? bt.ink : bt.ink3,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
