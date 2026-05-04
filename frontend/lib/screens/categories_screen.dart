import 'package:flutter/material.dart';
import '../models/budget_category.dart';
import '../services/categories_client.dart';
import '../theme/app_theme.dart';
import '../widgets/budget_card.dart';
import '../widgets/cat_icon.dart';
import '../widgets/category_edit_modal.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.root,
    required this.client,
    required this.onChanged,
  });

  /// Snapshot of the category tree owned and re-fetched by AppShell. After any
  /// mutation, the screen calls [onChanged] which triggers a refetch upstream;
  /// the screen rebuilds with a fresh `root` reference.
  final BudgetCategory root;

  final CategoriesClient client;

  /// Refetch trigger. Returns when AppShell has the new tree applied.
  final Future<void> Function() onChanged;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  /// Drill-down position, stored as ids so it survives a tree refetch (the
  /// BudgetCategory objects themselves get replaced when AppShell re-resolves
  /// from the backend).
  final List<int> _pathIds = [];

  /// Resolve [_pathIds] against the current tree. Stops early if any id no
  /// longer exists (e.g. the user just deleted that node).
  List<BudgetCategory> get _path {
    final out = <BudgetCategory>[];
    BudgetCategory current = widget.root;
    for (final id in _pathIds) {
      BudgetCategory? next;
      for (final c in current.children) {
        if (c.id == id) {
          next = c;
          break;
        }
      }
      if (next == null) break;
      out.add(next);
      current = next;
    }
    return out;
  }

  BudgetCategory get _current => _path.isEmpty ? widget.root : _path.last;

  List<BudgetCategory> get _visible =>
      _current.children.where((c) => !c.isUnknown).toList();

  void _drill(BudgetCategory node) {
    final id = node.id;
    if (id == null) return;
    setState(() => _pathIds.add(id));
  }

  void _back() {
    if (_pathIds.isEmpty) return;
    setState(() => _pathIds.removeLast());
  }

  void _navigateTo(int depth) {
    setState(() => _pathIds.removeRange(depth, _pathIds.length));
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> _add() async {
    final parentNow = _current;
    await CategoryEditModal.showCreate(
      context: context,
      root: widget.root,
      parent: parentNow,
      onSubmit: (parent, name, description) async {
        await widget.client.create(
          name: name,
          description: description,
          parentId: parent.id,
        );
        await widget.onChanged();
      },
    );
  }

  Future<void> _edit(BudgetCategory node) async {
    final currentParent = _findParent(widget.root, node) ?? widget.root;
    await CategoryEditModal.showEdit(
      context: context,
      root: widget.root,
      target: node,
      currentParent: currentParent,
      onSubmit: (newParent, newName, newDescription) async {
        await widget.client.update(
          node.id!,
          name: newName,
          description: newDescription,
          parentId: newParent.id,
          descriptionExplicit: true,
          parentExplicit: true,
        );
        await widget.onChanged();
      },
      onDelete: () async {
        await widget.client.delete(node.id!);
        // Trim the drill path so we're not pointing at the deleted node.
        final id = node.id!;
        final idx = _pathIds.indexOf(id);
        if (idx >= 0) {
          setState(() => _pathIds.removeRange(idx, _pathIds.length));
        }
        await widget.onChanged();
      },
    );
  }

  BudgetCategory? _findParent(BudgetCategory root, BudgetCategory target) {
    for (final c in root.children) {
      if (c.id == target.id) return root;
      final found = _findParent(c, target);
      if (found != null) return found;
    }
    return null;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 600;
        return isDesktop ? _buildDesktop(context) : _buildMobile(context);
      },
    );
  }

  Widget _buildMobile(BuildContext context) {
    final bt = context.bt;
    final atRoot = _path.isEmpty;
    final showLeafView = !atRoot && _current.children.isEmpty;
    final showFirstRunEmpty = atRoot && _visible.isEmpty;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
            child: Row(
              children: [
                if (!atRoot)
                  GestureDetector(
                    onTap: _back,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                      child: BudgetIcons.build('chevron-left',
                          size: 22, strokeWidth: 2, color: bt.ink),
                    ),
                  )
                else
                  const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    atRoot ? 'Categories' : _current.name,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: bt.ink,
                    ),
                  ),
                ),
                _IconButton(
                  icon: 'plus',
                  onTap: _add,
                  bt: bt,
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
              child: showFirstRunEmpty
                  ? _FirstRunEmpty(onCreate: _add)
                  : showLeafView
                      ? _LeafView(node: _current, onEdit: () => _edit(_current))
                      : _FillGrid(
                          nodes: _visible,
                          gap: 12,
                          onTap: _drill,
                          onEdit: _edit,
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final bt = context.bt;
    final atRoot = _path.isEmpty;
    final showLeafView = !atRoot && _current.children.isEmpty;
    final showFirstRunEmpty = atRoot && _visible.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(28, 22, 22, 18),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: bt.rule))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _path.isEmpty ? null : () => _navigateTo(0),
                      child: Text(
                        'CATEGORIES',
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 0.12 * 10.5,
                          color: _path.isEmpty ? bt.ink4 : bt.ink3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_path.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _Breadcrumbs(path: _path, onNavigateTo: _navigateTo),
                    ],
                  ],
                ),
              ),
              _IconButton(icon: 'plus', onTap: _add, bt: bt),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: showFirstRunEmpty
                ? _FirstRunEmpty(onCreate: _add)
                : showLeafView
                    ? _LeafView(node: _current, onEdit: () => _edit(_current))
                    : _FillGrid(
                        nodes: _visible,
                        gap: 16,
                        onTap: _drill,
                        onEdit: _edit,
                      ),
          ),
        ),
      ],
    );
  }
}

// ── First-run empty state ───────────────────────────────────────────────────

class _FirstRunEmpty extends StatelessWidget {
  const _FirstRunEmpty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bt.surface,
                border: Border.all(color: bt.ruleStrong),
                borderRadius: const BorderRadius.all(Radius.circular(16)),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.grid_view_outlined, size: 24, color: bt.ink3),
            ),
            const SizedBox(height: 18),
            Text(
              'No categories yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.01,
                color: bt.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Categories are how Budget Trace organises your spending — and '
              'how the AI knows where to file things. Create your first one '
              'to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: bt.ink3, height: 1.5),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: onCreate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  color: bt.ink,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BudgetIcons.build('plus',
                        size: 14, strokeWidth: 2, color: bt.bg),
                    const SizedBox(width: 8),
                    Text(
                      'Create category',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: bt.bg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Breadcrumbs ──────────────────────────────────────────────────────────────

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.path, required this.onNavigateTo});

  final List<BudgetCategory> path;
  final ValueChanged<int> onNavigateTo;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final crumbs = <Widget>[];
    for (var i = 0; i < path.length; i++) {
      final isLast = i == path.length - 1;
      if (i > 0) {
        crumbs.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: BudgetIcons.build('chevron-right',
              size: 14, strokeWidth: 2, color: bt.ink5),
        ));
      }
      crumbs.add(_Crumb(
        label: path[i].name,
        active: isLast,
        onTap: () => onNavigateTo(i + 1),
        bt: bt,
      ));
    }
    return Row(children: crumbs);
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.active,
    required this.onTap,
    required this.bt,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: active ? 26 : 22,
          letterSpacing: -0.02,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          color: active ? bt.ink : bt.ink3,
        ),
      ),
    );
  }
}

// ── Fill grid ────────────────────────────────────────────────────────────────

/// Lays out [nodes] in a grid that exactly fills the available space. Picks
/// the column count that yields tiles closest to square.
class _FillGrid extends StatelessWidget {
  const _FillGrid({
    required this.nodes,
    required this.gap,
    required this.onTap,
    required this.onEdit,
  });

  final List<BudgetCategory> nodes;
  final double gap;
  final ValueChanged<BudgetCategory> onTap;
  final ValueChanged<BudgetCategory> onEdit;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      final bt = context.bt;
      return Center(
        child: Text(
          'No subcategories.',
          style: TextStyle(fontSize: 13, color: bt.ink4),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final n = nodes.length;

        // Pick the column count that makes tiles closest to square while
        // using all available space.
        int bestCols = 1;
        double bestAspectError = double.infinity;
        for (int cols = 1; cols <= n; cols++) {
          final rows = (n / cols).ceil();
          final tileW = (w - gap * (cols - 1)) / cols;
          final tileH = (h - gap * (rows - 1)) / rows;
          if (tileW <= 0 || tileH <= 0) continue;
          final ratio = tileW / tileH;
          final err = (ratio >= 1 ? ratio - 1 : 1 / ratio - 1);
          if (err < bestAspectError) {
            bestAspectError = err;
            bestCols = cols;
          }
        }

        final cols = bestCols;
        final rows = (n / cols).ceil();
        final tileH = (h - gap * (rows - 1)) / rows;

        return Column(
          children: List.generate(rows, (r) {
            final children = <Widget>[];
            for (int c = 0; c < cols; c++) {
              final i = r * cols + c;
              if (c > 0) children.add(SizedBox(width: gap));
              if (i < n) {
                children.add(Expanded(
                  child: _Tile(
                    node: nodes[i],
                    onTap: () => onTap(nodes[i]),
                    onEdit: () => onEdit(nodes[i]),
                  ),
                ));
              } else {
                // Placeholder so the last row's filled tiles keep the same
                // width as rows above. (Spacer would expand to fill, which we
                // don't want — we want tile widths consistent across rows.)
                children.add(const Expanded(child: SizedBox.shrink()));
              }
            }
            return Padding(
              padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : gap),
              child: SizedBox(
                height: tileH,
                child: Row(children: children),
              ),
            );
          }),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.node,
    required this.onTap,
    required this.onEdit,
  });

  final BudgetCategory node;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return GestureDetector(
      onTap: onTap,
      child: BudgetCard(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  node.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.01,
                    color: bt.ink,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: _IconButton(
                icon: 'edit',
                onTap: onEdit,
                bt: bt,
                small: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Leaf view ────────────────────────────────────────────────────────────────

class _LeafView extends StatelessWidget {
  const _LeafView({required this.node, required this.onEdit});

  final BudgetCategory node;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            node.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02,
              color: bt.ink,
            ),
          ),
          if (node.description != null && node.description!.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              node.description!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: bt.ink3, height: 1.45),
            ),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: bt.surface,
                border: Border.all(color: bt.ruleStrong),
                borderRadius: const BorderRadius.all(Radius.circular(10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BudgetIcons.build('edit',
                      size: 14, strokeWidth: 1.8, color: bt.ink2),
                  const SizedBox(width: 8),
                  Text('Edit',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: bt.ink2)),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ── Reusable icon button ─────────────────────────────────────────────────────

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    required this.bt,
    this.small = false,
  });

  final String icon;
  final VoidCallback onTap;
  final BudgetTheme bt;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 28.0 : 34.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bt.surface,
          border: Border.all(color: bt.ruleStrong),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        alignment: Alignment.center,
        child: BudgetIcons.build(
          icon,
          size: small ? 13 : 16,
          strokeWidth: 1.8,
          color: bt.ink2,
        ),
      ),
    );
  }
}
