import '../models/budget_category.dart';

/// Walk the category tree and return every leaf with the name of its
/// immediate non-root ancestor as a `group` field. Used by the
/// CategoryChip-style assignment dropdowns.
List<({String name, String group})> leafCategoriesOf(BudgetCategory root) {
  final result = <({String name, String group})>[];
  for (final g in root.children.where((c) => !c.isUnknown)) {
    _collect(g, g.name, result);
  }
  return result;
}

void _collect(
  BudgetCategory node,
  String parentName,
  List<({String name, String group})> out,
) {
  if (node.children.isEmpty) {
    out.add((name: node.name, group: parentName));
  } else {
    for (final child in node.children) {
      _collect(child, node.name, out);
    }
  }
}

/// Find a category by its (possibly-not-leaf) name, walking the whole tree.
/// Returns null if no category in [root]'s subtree is named [name].
BudgetCategory? findCategoryByName(BudgetCategory root, String name) {
  for (final c in root.children) {
    if (c.name == name) return c;
    final hit = findCategoryByName(c, name);
    if (hit != null) return hit;
  }
  return null;
}

/// Resolve a category name → backend id. Used at the screen/backend boundary
/// when the UI carries the leaf-name string and the API expects an int id.
int? categoryIdForName(BudgetCategory root, String name) {
  final hit = findCategoryByName(root, name);
  return hit?.id;
}
