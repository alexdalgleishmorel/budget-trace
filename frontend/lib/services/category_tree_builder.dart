import '../models/budget_category.dart';
import 'categories_client.dart';

/// Build the in-app `BudgetCategory` tree from a flat list of [CategoryDto]s
/// returned by `GET /categories`.
///
/// The backend's CTE excludes the root "Budget" row from the listing, so the
/// flat list is already rooted at the top-level groups. We synthesise a root
/// node here so the rest of the app keeps the same `root.children` shape it
/// always had.
BudgetCategory buildTree(List<CategoryDto> dtos) {
  // First pass: BudgetCategory per dto, indexed by id.
  final byId = <int, BudgetCategory>{};
  for (final d in dtos) {
    byId[d.id] = BudgetCategory(
      id: d.id,
      name: d.name,
      description: d.description,
      isUnknown: d.isUnknown,
      color: d.color,
    );
  }

  // Second pass: link children. Top-level dtos (parent_id == root_id) become
  // children of the synthesised root. Their parent_id is the same for every
  // top-level row — pick it off the first one we see.
  int? rootId;
  for (final d in dtos) {
    if (d.parentId == null) continue;
    if (!byId.containsKey(d.parentId!)) {
      rootId = d.parentId;
    } else {
      byId[d.parentId!]!.children.add(byId[d.id]!);
    }
  }

  final root = BudgetCategory(
    id: rootId,
    name: 'Budget',
  );
  for (final d in dtos) {
    if (d.parentId == rootId) {
      root.children.add(byId[d.id]!);
    }
  }

  return root;
}
