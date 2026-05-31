import 'package:flutter/material.dart';

import '../services/api_base.dart';
import '../services/me_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_spend_chip.dart';
import '../widgets/budget_card.dart';
import '../widgets/cat_icon.dart';

/// Single-user settings page. One section:
///   • AI features  — collapsible card holding the master toggle and, when
///                    AI is on, one API-key row per known provider, the
///                    estimated-spend chip, and the model picker.
///
/// Every control bubbles its update through `MeClient.update()` immediately
/// and calls [onMeChanged] with the resulting [Me] so the parent rebuilds
/// with the new flags.
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
  bool _refreshingModels = false;
  String? _modelRefreshNote;
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
    String? selectedProvider,
    String? selectedModel,
    bool selectedModelExplicit = false,
    Map<String, String?>? providerKeys,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
      // A provider switch invalidates the previous fetch summary.
      if (selectedProvider != null) _modelRefreshNote = null;
    });
    try {
      final me = await widget.client.update(
        features: features,
        theme: theme,
        selectedProvider: selectedProvider,
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

  Future<void> _refreshModels() async {
    setState(() {
      _refreshingModels = true;
      _error = null;
      _modelRefreshNote = null;
    });
    try {
      final result = await widget.client.refreshModels();
      // The backend persists discovered models, so a plain GET /me now
      // returns the unioned catalog — no client-side merge needed.
      final me = await widget.client.get();
      if (!mounted) return;
      setState(() {
        _me = me;
        _modelRefreshNote = _summarizeRefresh(result);
      });
      widget.onMeChanged(me);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _refreshingModels = false);
    }
  }

  /// One-line human summary of fetching the selected provider's models.
  String _summarizeRefresh(ModelsRefreshResult result) {
    final p = result.provider;
    if (p.skipped) return 'Set an API key above, then fetch models.';
    if (p.error != null) return 'Fetch failed: ${p.error}';
    final n = p.discoveredCount;
    return n == 0
        ? 'No chat models available for this provider.'
        : 'Found $n model${n == 1 ? '' : 's'}.';
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
          _LocalDataBanner(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 16),
          // Flat AI settings — no collapsible section. The master toggle is
          // always the top row; when AI is on you pick a provider, set its
          // key, fetch its models, and pick one — then the spend readout.
          BudgetCard(
            clipContent: true,
            padding: EdgeInsets.zero,
            child: _DividedSections(children: [
              // Self-describing (its own title + blurb), so no _Section label.
              _FeatureRow(
                value: _me.features.ai,
                busy: _saving,
                onChanged: (v) => _patch(
                    features: FeatureFlags(ai: v, widgets: _me.features.widgets)),
              ),
              if (_me.features.ai) ...[
                _Section(
                  label: 'Provider',
                  child: _ProviderRow(
                    me: _me,
                    busy: _saving || _refreshingModels,
                    onPick: (id) => _patch(selectedProvider: id),
                  ),
                ),
                _Section(
                  label: 'API key',
                  child: _SelectedProviderKey(
                    me: _me,
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
                _Section(
                  label: 'Model',
                  child: _ModelRow(
                    me: _me,
                    busy: _saving,
                    refreshing: _refreshingModels,
                    refreshNote: _modelRefreshNote,
                    onRefresh: _refreshingModels ? null : _refreshModels,
                    onPick: (id) => _patch(
                      selectedModel: id,
                      selectedModelExplicit: true,
                    ),
                  ),
                ),
                _Section(
                  label: 'AI spend',
                  child: _SpendRow(me: _me),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

/// Stacks its [children] inside a card, separated by hairline dividers, each
/// padded uniformly. Used to lay out the flat Account settings sections.
class _DividedSections extends StatelessWidget {
  const _DividedSections({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final body = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) body.add(const BudgetDivider());
      body.add(Padding(
        padding: const EdgeInsets.all(16),
        child: children[i],
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: body,
    );
  }
}

/// A small uppercase label above its [child].
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

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

class _LocalDataBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bt.glass2,
        borderRadius: BudgetRadius.smBR,
        border: Border.all(color: bt.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: bt.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Everything — transactions, categories, settings, and API keys — '
              'is stored only on this machine in a local database (a Docker '
              'volume). Nothing leaves your computer except the requests you '
              'send to the AI provider you configure.',
              style: TextStyle(fontSize: 12, color: bt.ink2, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// The single API-key row for the currently-selected model's provider.
/// Switching the model swaps which provider's key field is shown.
class _SelectedProviderKey extends StatelessWidget {
  const _SelectedProviderKey({
    required this.me,
    required this.controllers,
    required this.visible,
    required this.onToggleVisibility,
    required this.onSave,
    required this.onClear,
  });

  final Me me;
  final TextEditingController Function(String providerId) controllers;
  final Set<String> visible;
  final ValueChanged<String> onToggleVisibility;
  final void Function(String providerId)? onSave;
  final void Function(String providerId)? onClear;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final matches =
        me.providers.where((p) => p.id == me.selectedProvider);
    final provider = matches.isEmpty ? null : matches.first;
    if (provider == null) {
      return Text(
        'No provider selected.',
        style: TextStyle(fontSize: 11.5, color: bt.ink4),
      );
    }
    return _ApiKeyRow(
      provider: provider,
      controller: controllers(provider.id),
      showKey: visible.contains(provider.id),
      onToggleVisibility: () => onToggleVisibility(provider.id),
      onSave: onSave == null ? null : () => onSave!(provider.id),
      onClear: (onClear == null || !provider.apiKeySet)
          ? null
          : () => onClear!(provider.id),
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
                    icon: BudgetIcons.build(
                      showKey ? 'eye-off' : 'eye',
                      size: 16,
                      strokeWidth: 1.6,
                      color: bt.ink3,
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
        ? ('Stored', bt.pos, bt.posBg)
        : (provider.envFallback
            ? ('Env', bt.ink2, bt.glass2)
            : ('Not set', bt.ink4, bt.glass2));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BudgetRadius.chipBR,
        border: Border.all(color: provider.apiKeySet ? bt.posBorder : bt.glassBorder),
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

/// Generic-provider picker (Anthropic / OpenAI / Google). Data-driven from
/// `me.providers`. Switching the provider clears the selected model server-side
/// and swaps which key field + model list show.
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.me,
    required this.busy,
    required this.onPick,
  });

  final Me me;
  final bool busy;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(me.selectedProvider),
          initialValue: me.selectedProvider,
          isDense: true,
          dropdownColor: BudgetColors.bgGrad[1],
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BudgetRadius.inputBR),
          ),
          items: [
            for (final p in me.providers)
              DropdownMenuItem<String>(
                value: p.id,
                child: Text(p.displayName,
                    style: TextStyle(fontSize: 13, color: bt.ink)),
              ),
          ],
          onChanged: busy ? null : (v) {
            if (v != null && v != me.selectedProvider) onPick(v);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Set this provider\'s API key below, then fetch its models.',
          style: TextStyle(fontSize: 11.5, color: bt.ink4, height: 1.4),
        ),
      ],
    );
  }
}

/// Model picker for the selected provider. The list is fetched live (no
/// hardcoded catalog) via the "Fetch models" button; empty until then.
class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.me,
    required this.busy,
    required this.refreshing,
    required this.refreshNote,
    required this.onRefresh,
    required this.onPick,
  });

  final Me me;
  final bool busy;
  final bool refreshing;
  final String? refreshNote;
  final VoidCallback? onRefresh;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final options = me.availableModels;
    final providerLookup = {for (final p in me.providers) p.id: p.displayName};
    final providerName =
        providerLookup[me.selectedProvider] ?? me.selectedProvider;
    final hasModels = options.isNotEmpty;
    // DropdownButtonFormField needs its value to be among the items. Use null
    // when nothing is picked (or the pick isn't in the fetched list).
    final ids = options.map((m) => m.id).toSet();
    final currentValue =
        ids.contains(me.selectedModel) ? me.selectedModel : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasModels)
          DropdownButtonFormField<String>(
            key: ValueKey('${me.selectedProvider}:${me.selectedModel}'),
            initialValue: currentValue,
            isDense: true,
            dropdownColor: BudgetColors.bgGrad[1],
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Select a model…',
              border: OutlineInputBorder(borderRadius: BudgetRadius.inputBR),
            ),
            items: [
              for (final m in options)
                DropdownMenuItem<String>(
                  value: m.id,
                  child: _ModelMenuItem(
                    option: m,
                    providerName: providerLookup[m.provider] ?? m.provider,
                  ),
                ),
            ],
            onChanged: busy ? null : (v) {
              if (v != null) onPick(v);
            },
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: bt.glass2,
              borderRadius: BudgetRadius.smBR,
              border: Border.all(color: bt.glassBorder),
            ),
            child: Text(
              me.selectedProviderKeyAvailable
                  ? 'No models fetched for $providerName yet — tap "Fetch '
                      'models".'
                  : 'Set a $providerName API key above, then tap "Fetch '
                      'models".',
              style: TextStyle(fontSize: 12, color: bt.ink3, height: 1.4),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed:
                  (busy || refreshing || !me.selectedProviderKeyAvailable)
                      ? null
                      : onRefresh,
              icon: refreshing
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    )
                  : Icon(Icons.refresh, size: 16, color: bt.accent),
              label: Text(refreshing ? 'Fetching…' : 'Fetch models'),
            ),
          ],
        ),
        if (refreshNote != null) ...[
          const SizedBox(height: 2),
          Text(
            refreshNote!,
            style: TextStyle(fontSize: 11.5, color: bt.ink3, height: 1.4),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Fetches the live model list $providerName offers (uses the key '
          'above). AI calls use the model you pick; new models may show '
          'without pricing until it\'s published.',
          style: TextStyle(fontSize: 11, color: bt.ink4, height: 1.4),
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
          option.pricingAvailable
              ? '${_formatPrice(option.inputPerMtok)}/MTok in · '
                  '${_formatPrice(option.outputPerMtok)}/MTok out'
              : 'pricing n/a',
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

