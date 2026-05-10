import 'package:flutter/material.dart';

import '../services/api_base.dart';
import '../services/me_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_spend_chip.dart';
import '../widgets/budget_card.dart';

/// Single-user settings page. Two sections:
///   • Appearance   — system / light / dark (top of the screen, always visible)
///   • AI features  — collapsible card holding the master toggle and, when
///                    AI is on, one API-key row per known provider, the
///                    estimated-spend chip, and the model picker.
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
  // Per-provider controller + visibility state. Initialized lazily as
  // providers appear (so a new provider id from the backend just shows up).
  final Map<String, TextEditingController> _keyControllers = {};
  final Set<String> _visibleKeys = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _me = widget.me;
    _refresh();
  }

  TextEditingController _controllerFor(String providerId) {
    final existing = _keyControllers[providerId];
    if (existing != null) return existing;
    final ctrl = TextEditingController();
    ctrl.addListener(() {
      if (mounted) setState(() {});
    });
    _keyControllers[providerId] = ctrl;
    return ctrl;
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
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _patch({
    FeatureFlags? features,
    String? theme,
    String? selectedModel,
    bool selectedModelExplicit = false,
    Map<String, String?>? providerKeys,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final me = await widget.client.update(
        features: features,
        theme: theme,
        selectedModel: selectedModel,
        selectedModelExplicit: selectedModelExplicit,
        providerKeys: providerKeys,
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

  Future<void> _saveKey(String providerId) async {
    final ctrl = _controllerFor(providerId);
    final v = ctrl.text.trim();
    if (v.isEmpty) return;
    await _patch(providerKeys: {providerId: v});
    ctrl.clear();
    setState(() => _visibleKeys.remove(providerId));
  }

  Future<void> _clearKey(String providerId) async {
    await _patch(providerKeys: {providerId: null});
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
            label: 'Appearance',
            child: _ThemeRow(
              value: _me.theme,
              onChanged: (v) => _patch(theme: v),
            ),
          ),
          const SizedBox(height: 16),
          _ExpandableSection(
            label: 'AI features',
            // The master toggle is always the first row inside the dropdown.
            // The remaining controls only appear when the toggle is on —
            // they'd be misleading otherwise (changes wouldn't take effect
            // until the master flag was flipped back on).
            children: [
              _FeatureRow(
                value: _me.features.ai,
                busy: _saving,
                onChanged: (v) => _patch(features: FeatureFlags(ai: v)),
              ),
              if (_me.features.ai) ...[
                _SubControl(
                  label: 'API keys',
                  child: _ApiKeysList(
                    providers: _me.providers,
                    controllers: _controllerFor,
                    visible: _visibleKeys,
                    onToggleVisibility: (id) => setState(() {
                      if (_visibleKeys.contains(id)) {
                        _visibleKeys.remove(id);
                      } else {
                        _visibleKeys.add(id);
                      }
                    }),
                    onSave: _saving ? null : _saveKey,
                    onClear: _saving ? null : _clearKey,
                  ),
                ),
                _SubControl(
                  label: 'AI Spend',
                  child: _SpendRow(me: _me),
                ),
                _SubControl(
                  label: 'Model',
                  child: _ModelRow(
                    me: _me,
                    busy: _saving,
                    onPick: (id) => _patch(
                      selectedModel: id,
                      selectedModelExplicit: true,
                    ),
                    onReset: () => _patch(
                      selectedModel: null,
                      selectedModelExplicit: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
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

/// Collapsible card. Renders as a `BudgetCard` whose first row is the
/// tappable header (label + chevron). When expanded, [children] are stacked
/// inside the same card, separated by hairline dividers.
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
    final body = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      body.add(const BudgetDivider());
      body.add(Padding(
        padding: const EdgeInsets.all(16),
        child: widget.children[i],
      ));
    }
    return BudgetCard(
      clipContent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
              children: body,
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

/// Sub-control inside an [_ExpandableSection]: a small uppercase label
/// above the [child]. The wrapping card and dividers are owned by the
/// parent section, so this is just the label-above-content pairing.
class _SubControl extends StatelessWidget {
  const _SubControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BudgetLabel(label),
        const SizedBox(height: 10),
        child,
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
              'Single-user mode — auth is not yet implemented. Your API '
              'keys are stored unencrypted in local SQLite.',
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

/// One row per provider known by the backend, rendered in registry order.
/// The list is fully data-driven — adding a provider in services/ai/registry.py
/// makes it show up here without a frontend change.
class _ApiKeysList extends StatelessWidget {
  const _ApiKeysList({
    required this.providers,
    required this.controllers,
    required this.visible,
    required this.onToggleVisibility,
    required this.onSave,
    required this.onClear,
  });

  final List<ProviderStatus> providers;
  final TextEditingController Function(String providerId) controllers;
  final Set<String> visible;
  final ValueChanged<String> onToggleVisibility;
  final void Function(String providerId)? onSave;
  final void Function(String providerId)? onClear;

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) {
      final bt = context.bt;
      return Text(
        'No providers configured on the backend.',
        style: TextStyle(fontSize: 11.5, color: bt.ink4),
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < providers.length; i++) {
      if (i > 0) rows.add(const SizedBox(height: 14));
      final p = providers[i];
      rows.add(_ApiKeyRow(
        provider: p,
        controller: controllers(p.id),
        showKey: visible.contains(p.id),
        onToggleVisibility: () => onToggleVisibility(p.id),
        onSave: onSave == null ? null : () => onSave!(p.id),
        onClear: (onClear == null || !p.apiKeySet) ? null : () => onClear!(p.id),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

class _ApiKeyRow extends StatelessWidget {
  const _ApiKeyRow({
    required this.provider,
    required this.controller,
    required this.showKey,
    required this.onToggleVisibility,
    required this.onSave,
    required this.onClear,
  });

  final ProviderStatus provider;
  final TextEditingController controller;
  final bool showKey;
  final VoidCallback onToggleVisibility;
  final VoidCallback? onSave;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final hasPendingChange = controller.text.trim().isNotEmpty;
    final pill = _StatusPill(provider: provider);
    final hint = provider.apiKeySet
        ? 'Stored. Used for ${provider.displayName} models.'
        : (provider.envFallback
            ? 'Using ${provider.envVar} from the environment. Save a key '
              'here to override.'
            : 'Required if you select a ${provider.displayName} model below.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              provider.displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: bt.ink,
              ),
            ),
            const SizedBox(width: 10),
            pill,
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: !showKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: provider.apiKeySet
                      ? 'Replace stored key…'
                      : 'Paste ${provider.displayName} API key…',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BudgetRadius.inputBR),
                  suffixIcon: IconButton(
                    tooltip: showKey ? 'Hide' : 'Show',
                    icon: Icon(
                      showKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
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
              FilledButton(onPressed: onSave, child: const Text('Save')),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                hint,
                style:
                    TextStyle(fontSize: 11.5, color: bt.ink4, height: 1.4),
              ),
            ),
            if (provider.apiKeySet)
              TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.provider});

  final ProviderStatus provider;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final (label, fg, bg) = provider.apiKeySet
        ? ('Stored', bt.pos, bt.pos.withValues(alpha: 0.12))
        : (provider.envFallback
            ? ('Env', bt.ink2, bt.surface2)
            : ('Not set', bt.ink4, bt.surface2));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BudgetRadius.chipBR,
        border: Border.all(color: bt.ruleStrong),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }
}

class _SpendRow extends StatelessWidget {
  const _SpendRow({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AiSpendChip.detailed(
              amountUsd: me.aiSpentUsd,
              label: 'spent on AI',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Estimated from token usage and the selected model\'s published '
          'per-MTok price. Not the same as your provider bill — check each '
          'provider\'s dashboard for the authoritative figure.',
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
    // the registry). Show the dropdown's current value as the resolved id
    // even if it's not in the list — Dart's DropdownButtonFormField requires
    // the value to be in items, so synthesise an entry if needed.
    final ids = options.map((m) => m.id).toSet();
    final hasCurrent = ids.contains(me.selectedModel);
    final providerLookup = {for (final p in me.providers) p.id: p.displayName};
    final items = [
      ...options.map(
        (m) => DropdownMenuItem<String>(
          value: m.id,
          child: _ModelMenuItem(
            option: m,
            providerName: providerLookup[m.provider] ?? m.provider,
          ),
        ),
      ),
      if (!hasCurrent)
        DropdownMenuItem<String>(
          value: me.selectedModel,
          child: Text(
            me.selectedModel,
            style: TextStyle(fontSize: 13, color: bt.ink2),
          ),
        ),
    ];

    final providerName =
        providerLookup[me.selectedModelProvider] ?? me.selectedModelProvider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          // ValueKey re-mounts the form field whenever the resolved model
          // changes externally (e.g. "Reset to default") so the new
          // `initialValue` actually takes effect.
          key: ValueKey(me.selectedModel),
          initialValue: me.selectedModel,
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
        if (!me.selectedModelKeyAvailable) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bt.warnBg,
              borderRadius: BudgetRadius.smBR,
              border: Border.all(color: bt.warn.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: bt.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$providerName API key not set — AI features won\'t work '
                    'until you add one above (or switch to a model whose '
                    'provider has a key).',
                    style: TextStyle(
                        fontSize: 11.5, color: bt.ink2, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
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
  const _ModelMenuItem({required this.option, required this.providerName});

  final ModelOption option;
  final String providerName;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$providerName — ${option.displayName}',
          style: TextStyle(fontSize: 13, color: bt.ink),
        ),
        const SizedBox(width: 8),
        Text(
          '${_formatPrice(option.inputPerMtok)}/MTok in · '
          '${_formatPrice(option.outputPerMtok)}/MTok out',
          style: TextStyle(fontSize: 11, color: bt.ink4),
        ),
      ],
    );
  }

  static String _formatPrice(double v) {
    // Use 2 decimals for sub-$1 prices, 0 decimals for whole-dollar prices.
    if (v < 1.0) return '\$${v.toStringAsFixed(2)}';
    if (v == v.roundToDouble()) return '\$${v.toStringAsFixed(0)}';
    return '\$${v.toStringAsFixed(2)}';
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
