import 'package:flutter/material.dart';
import '../models/budget_category.dart';
import '../services/api_base.dart';
import '../services/categories_client.dart';
import '../theme/app_theme.dart';
import '../widgets/cat_icon.dart';
import '../widgets/category_edit_modal.dart';
import '../widgets/glass.dart';
import '../widgets/mobile_settings_icon.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.root,
    required this.client,
    required this.onChanged,
    required this.navPulse,
    required this.onOpenAccount,
  });

  /// Snapshot of the category tree owned and re-fetched by AppShell. After any
  /// mutation, the screen calls [onChanged] which triggers a refetch upstream;
  /// the screen rebuilds with a fresh `root` reference.
  final BudgetCategory root;

  final CategoriesClient client;

  /// Refetch trigger. Returns when AppShell has the new tree applied.
  final Future<void> Function() onChanged;

  /// Monotonically-increasing counter from AppShell. Bumped every time the
  /// user re-taps the Categories nav item while already on the Categories
  /// tab — `didUpdateWidget` observes the change and pops the drill-down
  /// to root.
  final int navPulse;

  /// Opens the AccountScreen modal. Wired to the mobile header's settings
  /// icon (replaces the "Categories" page title); desktop has its own
  /// Account button in the side nav.
  final VoidCallback onOpenAccount;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  /// Drill-down position, stored as ids so it survives a tree refetch (the
  /// BudgetCategory objects themselves get replaced when AppShell re-resolves
  /// from the backend).
  final List<int> _pathIds = [];

  /// True while POST /categories/seed_defaults is in flight. Disables both
  /// empty-state buttons + draws a spinner inside the secondary one.
  bool _seedingDefaults = false;

  @override
  void didUpdateWidget(CategoriesScreen old) {
    super.didUpdateWidget(old);
    // Re-tapping the Categories nav item while already on this tab pops
    // the drill-down to root. AppShell signals this by bumping `navPulse`.
    if (old.navPulse != widget.navPulse && _pathIds.isNotEmpty) {
      setState(() => _pathIds.clear());
    }
  }

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

  Future<void> _useDefaults() async {
    if (_seedingDefaults) return;
    setState(() => _seedingDefaults = true);
    try {
      await widget.client.seedDefaults();
      await widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create defaults: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _seedingDefaults = false);
    }
  }

  Future<void> _add() async {
    final parentNow = _current;
    await CategoryEditModal.showCreate(
      context: context,
      root: widget.root,
      parent: parentNow,
      onSubmit: (parent, name, description, color) async {
        await widget.client.create(
          name: name,
          description: description,
          parentId: parent.id,
          color: color,
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
      onSubmit: (newParent, newName, newDescription, newColor) async {
        await widget.client.update(
          node.id!,
          name: newName,
          description: newDescription,
          parentId: newParent.id,
          color: newColor,
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
                if (atRoot)
                  MobileSettingsIcon(onTap: widget.onOpenAccount)
                else
                  GestureDetector(
                    onTap: _back,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                      child: BudgetIcons.build('chevron-left',
                          size: 22, strokeWidth: 2, color: bt.ink),
                    ),
                  ),
                Expanded(
                  child: atRoot
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            _current.name,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: bt.ink,
                            ),
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
                  ? _FirstRunEmpty(
                      onCreate: _add,
                      onUseDefaults: _useDefaults,
                      seedingDefaults: _seedingDefaults,
                    )
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
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: bt.glassBorder))),
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
                          fontSize: 11,
                          letterSpacing: 0.06 * 11,
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
                ? _FirstRunEmpty(
                      onCreate: _add,
                      onUseDefaults: _useDefaults,
                      seedingDefaults: _seedingDefaults,
                    )
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
  const _FirstRunEmpty({
    required this.onCreate,
    required this.onUseDefaults,
    required this.seedingDefaults,
  });

  final VoidCallback onCreate;
  final VoidCallback onUseDefaults;

  /// True while the seed_defaults round-trip is in flight. Disables both
  /// buttons and renders a spinner inside the secondary "Use defaults"
  /// button so the user has feedback even on a slower connection.
  final bool seedingDefaults;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GlassSurface(
              tier: GlassTier.t1,
              radius: 20,
              padding: const EdgeInsets.all(20),
              child: BudgetIcons.build(
                'grid',
                size: 32,
                strokeWidth: 1.6,
                color: bt.ink2,
              ),
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
              'Categories are how Expense Visualizer organises your spending — and '
              'how the AI knows where to file things. Create your first one, '
              'or start with a sensible default set.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: bt.ink3, height: 1.5),
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final stack = constraints.maxWidth < 320;
                final primary = _PrimaryButton(
                  icon: 'plus',
                  label: 'Create category',
                  onTap: seedingDefaults ? null : onCreate,
                  bt: bt,
                );
                final secondary = _SecondaryButton(
                  label: 'Use defaults',
                  onTap: seedingDefaults ? null : onUseDefaults,
                  busy: seedingDefaults,
                  bt: bt,
                );
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      primary,
                      const SizedBox(height: 8),
                      secondary,
                    ],
                  );
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    primary,
                    const SizedBox(width: 10),
                    secondary,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.bt,
  });
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: label,
      onPressed: onTap,
      variant: GlassButtonVariant.primary,
      icon: BudgetIcons.build(icon, size: 14, strokeWidth: 1.8, color: Colors.white),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onTap,
    required this.busy,
    required this.bt,
  });
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: label,
      onPressed: onTap,
      variant: GlassButtonVariant.secondary,
      icon: busy
          ? SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation(bt.ink3),
              ),
            )
          : null,
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
    final bg = context.categoryBg(node.color);
    // Tiles are smaller on phones — drop the title a couple points so longer
    // names fit without truncating.
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: GlassSurface(
          tier: GlassTier.t1,
          radius: 20,
          child: Stack(
            children: [
              // Radial wash from bottom-left in the category's hue.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: RadialGradient(
                        center: const Alignment(-1, 1),
                        radius: 1.4,
                        colors: [
                          bg.withValues(alpha: 0.55),
                          bg.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.7],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Color dot
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: bg,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const Spacer(),
                        _TileEditButton(onTap: onEdit),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      node.name,
                      style: TextStyle(
                        fontSize: isMobile ? 15.5 : 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: bt.ink,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small edit-pencil pill that floats over a category tile.
class _TileEditButton extends StatelessWidget {
  const _TileEditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: GlassSurface(
          tier: GlassTier.t2,
          radius: 8,
          elevated: false,
          sheen: false,
          padding: const EdgeInsets.all(6),
          child: BudgetIcons.build(
            'edit',
            size: 13,
            strokeWidth: 1.6,
            color: bt.ink2,
          ),
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
          GlassButton(
            label: 'Edit',
            onPressed: onEdit,
            variant: GlassButtonVariant.secondary,
            compact: true,
            icon: BudgetIcons.build('edit',
                size: 14, strokeWidth: 1.6, color: bt.ink2),
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
  });

  final String icon;
  final VoidCallback onTap;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: GlassSurface(
          tier: GlassTier.t2,
          radius: 10,
          elevated: false,
          sheen: false,
          padding: const EdgeInsets.all(9),
          child: BudgetIcons.build(
            icon,
            size: 16,
            strokeWidth: 1.6,
            color: bt.ink2,
          ),
        ),
      ),
    );
  }
}
