import '../models/budget_category.dart';

/// One entry per assignable category — leaves AND parents. Every category
/// in the tree except the synthetic root and the Unknown bucket is a valid
/// assignment target: the user (or the AI) may pick a parent directly when
/// no child is a clearer fit (e.g. a generic "Travel" charge that doesn't
/// match the more specific "Flights" / "Lodging" leaves underneath it).
///
/// Walking by path gives every entry a stable, unambiguous identifier even
/// when two categories share the same `name` in different parts of the
/// tree. `group` is the entry's immediate-non-root ancestor name (or the
/// entry's own name for top-level categories), used by the dropdown UIs to
/// render a `<group> · <leaf>` label.
typedef AssignableCategory = ({String name, String group, String path});

List<AssignableCategory> assignableCategoriesOf(BudgetCategory root) {
  final result = <AssignableCategory>[];
  for (final g in root.children.where((c) => !c.isUnknown)) {
    _collect(g, parentName: g.name, parentPath: '', out: result);
  }
  return result;
}

void _collect(
  BudgetCategory node, {
  required String parentName,
  required String parentPath,
  required List<AssignableCategory> out,
}) {
  final path = parentPath.isEmpty ? node.name : '$parentPath / ${node.name}';
  out.add((name: node.name, group: parentName, path: path));
  for (final child in node.children) {
    _collect(child, parentName: node.name, parentPath: path, out: out);
  }
}

/// Resolve a category path (e.g. "Living / Grocery") back to its backend id.
/// Walks the tree segment-by-segment so two categories sharing the same
/// `name` in different branches resolve to the correct row.
int? categoryIdForPath(BudgetCategory root, String path) {
  final segments = path.split(' / ');
  BudgetCategory? current = root;
  for (final segment in segments) {
    if (current == null) return null;
    current = current.children.firstWhere(
      (c) => c.name == segment,
      orElse: () => BudgetCategory(name: '__missing__'),
    );
    if (current.name == '__missing__') return null;
  }
  return current?.id;
}
