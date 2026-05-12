class BudgetCategory {
  BudgetCategory({
    required this.name,
    this.id,
    this.description,
    List<BudgetCategory>? children,
    this.isUnknown = false,
    this.color = 'stone',
  }) : children = children ?? [];

  /// Backend-assigned id. Null for any in-memory-only category (only used
  /// briefly during loading or in tests).
  int? id;

  String name;

  /// Human-written hint for what belongs in this category. Surfaced to the
  /// AI assistant as classification context when categorising new expenses.
  String? description;

  final List<BudgetCategory> children;
  final bool isUnknown;

  /// Palette key (e.g. `"sage"`, `"clay"`) — resolved to a Color at render
  /// time via `context.categoryBg(color)`. Stored verbatim on the wire.
  String color;

  bool get isLeaf => children.isEmpty;
}
