import 'package:flutter/material.dart';

import '../services/api_base.dart';
import '../services/me_client.dart';
import '../theme/app_theme.dart';
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
  bool _showKey = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _me = widget.me;
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _patch({
    FeatureFlags? features,
    String? theme,
    String? anthropicApiKey,
    bool apiKeyExplicit = false,
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
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            label: 'Appearance',
            child: _ThemeRow(
              value: _me.theme,
              onChanged: (v) => _patch(theme: v),
            ),
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
  });

  final bool keyIsSet;
  final TextEditingController controller;
  final bool showKey;
  final VoidCallback onToggleVisibility;
  final VoidCallback? onSave;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
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
                  hintText: keyIsSet ? 'Replace stored key…' : 'sk-ant-…',
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
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onSave,
              child: const Text('Save'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                keyIsSet
                    ? 'Set. Used for AI parsing, auto-categorization, and chat.'
                    : 'Not set — falls back to the ANTHROPIC_API_KEY env var.',
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
