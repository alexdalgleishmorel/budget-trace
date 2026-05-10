import 'package:flutter/material.dart';
import 'services/me_client.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';

void main() {
  runApp(const BudgetTraceApp());
}

class BudgetTraceApp extends StatefulWidget {
  const BudgetTraceApp({super.key});

  @override
  State<BudgetTraceApp> createState() => _BudgetTraceAppState();
}

class _BudgetTraceAppState extends State<BudgetTraceApp> {
  final _meClient = MeClient();
  Me _me = Me.initial;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  @override
  void dispose() {
    _meClient.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    try {
      final me = await _meClient.get();
      if (!mounted) return;
      setState(() => _me = me);
    } catch (_) {
      // Backend unreachable on first load. Stay on Me.initial; AppShell will
      // surface the underlying connectivity error through its own data calls.
    }
  }

  void _onMeChanged(Me me) {
    if (!mounted) return;
    setState(() => _me = me);
  }

  /// Refresh `/me` after AI calls so the global spend chip updates. Cheap —
  /// it's the chip in the shell, not a bottleneck. Silent on errors.
  Future<void> _refreshMe() async {
    try {
      final me = await _meClient.get();
      if (!mounted) return;
      setState(() => _me = me);
    } catch (_) {
      // Stale spend total is harmless; chip just doesn't tick this turn.
    }
  }

  ThemeMode _themeMode() {
    switch (_me.theme) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Budget Trace',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode(),
      home: AppShell(
        me: _me,
        meClient: _meClient,
        onMeChanged: _onMeChanged,
        onRefreshMe: _refreshMe,
      ),
    );
  }
}
