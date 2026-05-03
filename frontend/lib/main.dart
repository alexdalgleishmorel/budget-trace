import 'package:flutter/material.dart';
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
  bool _dark = false;

  void _toggleTheme() => setState(() => _dark = !_dark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Budget Trace',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: AppShell(
        isDark: _dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
