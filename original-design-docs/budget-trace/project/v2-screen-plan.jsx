// v2 — Plan (Treemap) screens. No Unknown tile. B is default, C is mobile option.

function PlanTreemap({ rootNode, w, h, mode = 'classic', onDrill, showFill = false, readable = true }) {
  // strip Unknown for Plan
  const kids = (rootNode.children || []).filter(c => !c.isUnknown);
  const items = kids.map(c => ({
    node: c, value: Math.max(c.amount || 1, 1),
  }));
  const PAD = 4;

  if (mode === 'rows') {
    const total = items.reduce((s, r) => s + r.value, 0);
    let yy = 0;
    return (
      <div style={{ position: 'relative', width: w, height: h }}>
        {items.map((r, i) => {
          const rh = (r.value / total) * h;
          const y0 = yy; yy += rh;
          const node = r.node;
          const isOver = showFill && node.actual > node.amount;
          const pct = showFill && node.amount > 0 ? Math.min(1.2, node.actual / node.amount) : 0;
          return (
            <div key={i} className="row-tile"
              onClick={() => onDrill && onDrill(node)}
              style={{
                position: 'absolute',
                left: 0, top: y0 + 1,
                width: w, height: rh - 2,
                background: catColor(node),
              }}>
              {showFill && pct > 0 && (
                <div className={'tile-fill' + (isOver ? ' over' : '')}
                  style={{ width: Math.min(100, pct * 100) + '%', top: 0, bottom: 0, height: '100%' }} />
              )}
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, zIndex: 1 }}>
                <span className="display" style={{ fontSize: 18 }}>{ICONS[node.name] || '◆'}</span>
                <span className="tile-name">{node.name}</span>
              </div>
              <span className="tile-amt" style={{ zIndex: 1 }}>{fmtMoney(node.amount)}</span>
            </div>
          );
        })}
      </div>
    );
  }

  const rects = squarify(items, 0, 0, w, h);
  return (
    <div style={{ position: 'relative', width: w, height: h }}>
      {rects.map((r, i) => {
        const node = r.node;
        const small = r.w < 80 || r.h < 60;
        return (
          <div key={i}
            className={'tile' + (small ? ' small' : '')}
            onClick={() => onDrill && onDrill(node)}
            style={{
              position: 'absolute',
              left: r.x + PAD/2, top: r.y + PAD/2,
              width: r.w - PAD, height: r.h - PAD,
              background: catColor(node),
            }}>
            <div style={{ position: 'relative', zIndex: 1 }}>
              <div className="tile-name">{node.name}</div>
              {!small && <div className="tile-amt">{fmtMoney(node.amount)}</div>}
            </div>
          </div>
        );
      })}
    </div>
  );
}

// Reusable breadcrumb path → clickable nav back up
function PlanCrumbs({ path, onJump, rightSlot }) {
  // path: [{ node, label }], root first
  return (
    <div className="crumbs">
      {path.map((p, i) => {
        const isLast = i === path.length - 1;
        return (
          <React.Fragment key={i}>
            {i > 0 && <span>›</span>}
            {isLast
              ? <b>{p.label}</b>
              : <span style={{ cursor: 'pointer', textDecoration: 'underline dotted', textUnderlineOffset: 2 }}
                  onClick={() => onJump(i)}>{p.label}</span>}
          </React.Fragment>
        );
      })}
      {rightSlot && <span style={{ marginLeft: 'auto' }}>{rightSlot}</span>}
    </div>
  );
}

// Desktop sidebar — vertical rail with page icons; expands in-place to show labels
function DesktopSidebar({ current, onNav }) {
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (!open) return;
    const onDoc = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    setTimeout(() => document.addEventListener('click', onDoc), 0);
    return () => document.removeEventListener('click', onDoc);
  }, [open]);
  const pages = [
    ['plan',     'Plan',     '◱'],
    ['expenses', 'Expenses', '≣'],
    ['results',  'Results',  '◔'],
    ['summary',  'Summary',  '∑'],
    ['account',  'Account',  '◌'],
  ];
  const W_COLLAPSED = 40;
  const W_EXPANDED = 160;
  return (
    <div ref={ref} style={{
      position: 'absolute', top: 0, left: 0, bottom: 0, zIndex: 40,
      width: open ? W_EXPANDED : W_COLLAPSED,
      borderRight: '1.5px solid var(--rule)',
      background: 'var(--paper)',
      padding: '10px 4px',
      display: 'flex', flexDirection: 'column',
      transition: 'width 0.15s ease',
      overflow: 'hidden',
    }}>
      {/* Toggle button */}
      <button
        onClick={(e) => { e.stopPropagation(); setOpen(o => !o); }}
        title={open ? 'Collapse' : 'Expand'}
        style={{
          width: '100%', height: 28, marginBottom: 8,
          display: 'flex', alignItems: 'center',
          padding: '0 8px', gap: 10,
          background: 'transparent', border: 'none', cursor: 'pointer',
          fontFamily: 'var(--hand)', color: 'var(--ink)', fontSize: 18,
        }}>
        <span style={{ width: 20, textAlign: 'center' }}>≡</span>
        {open && <span className="muted" style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: 0.06 }}>Pages</span>}
      </button>

      {pages.map(([id, label, icon]) => {
        const active = id === current;
        return (
          <button
            key={id}
            onClick={() => onNav && onNav(id)}
            title={open ? '' : label}
            style={{
              width: '100%', padding: '6px 8px', marginBottom: 2,
              display: 'flex', alignItems: 'center', gap: 10,
              background: active ? 'var(--paper-2)' : 'transparent',
              border: 'none', cursor: 'pointer', borderRadius: 4,
              fontFamily: 'var(--hand)', fontSize: 13,
              fontWeight: active ? 700 : 400,
              color: 'var(--ink)',
              textAlign: 'left',
            }}
            onMouseEnter={(e) => { if (!active) e.currentTarget.style.background = 'var(--paper-2)'; }}
            onMouseLeave={(e) => { if (!active) e.currentTarget.style.background = 'transparent'; }}>
            <span style={{ width: 20, textAlign: 'center', fontSize: 16 }}>{icon}</span>
            {open && <span style={{ whiteSpace: 'nowrap' }}>{label}</span>}
          </button>
        );
      })}
    </div>
  );
}

// Phone: hamburger menu replaces title/home icon
function HamburgerMenu({ current, onNav, variant = 'phone' }) {
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (!open) return;
    const onDoc = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    setTimeout(() => document.addEventListener('click', onDoc), 0);
    return () => document.removeEventListener('click', onDoc);
  }, [open]);
  const pages = [
    ['plan', 'Plan'], ['expenses', 'Expenses'],
    ['results', 'Results'], ['summary', 'Summary'],
    ['account', 'Account'],
  ];
  const isDesktop = variant === 'desktop';
  return (
    <span style={{ position: 'relative', display: 'inline-flex', alignItems: 'center' }} ref={ref}>
      <button
        onClick={(e) => { e.stopPropagation(); setOpen(o => !o); }}
        style={{
          display: 'inline-flex', alignItems: 'center', gap: 8,
          background: 'transparent', border: 'none', padding: isDesktop ? '2px 4px' : '4px 2px',
          cursor: 'pointer', color: 'var(--ink)',
          font: 'inherit',
        }}>
        <span style={{
          fontSize: isDesktop ? 16 : 20, lineHeight: 1,
          fontFamily: 'var(--hand)',
        }}>≡</span>
        <span style={{
          fontFamily: isDesktop ? 'var(--hand)' : 'var(--display)',
          fontSize: isDesktop ? 13 : 18,
          letterSpacing: isDesktop ? 0 : 0.5,
        }}>
          {isDesktop ? current : current.toUpperCase()}
        </span>
      </button>
      {open && (
        <div style={{
          position: 'absolute', top: 'calc(100% + 4px)', left: 0, zIndex: 50,
          minWidth: 150, background: 'var(--paper)', border: '1.5px solid var(--ink)',
          borderRadius: 6, boxShadow: '2px 2px 0 var(--ink)', padding: 6,
          fontFamily: 'var(--hand)', fontSize: 13,
        }}>
          {pages.map(([id, label]) => (
            <div key={id}
              onClick={() => { onNav && onNav(id); setOpen(false); }}
              style={{
                padding: '5px 10px', cursor: 'pointer', borderRadius: 3,
                background: id === current ? 'var(--paper-2)' : 'transparent',
                fontWeight: id === current ? 700 : 400,
              }}
              onMouseEnter={(e) => e.currentTarget.style.background = 'var(--paper-2)'}
              onMouseLeave={(e) => e.currentTarget.style.background = id === current ? 'var(--paper-2)' : 'transparent'}>
              {label}
            </div>
          ))}
        </div>
      )}
    </span>
  );
}

// Edit Category panel — modal overlay for editing current scoped category
const ICON_CHOICES = ['🏠', '🚗', '🍎', '🛋', '💡', '🎬', '💰', '🎓', '💳', '🏥', '✈️', '🎁', '◆', '◇', '★'];

function EditCategoryPanel({ node, allCats, onClose, onSave, onDelete, mode = 'edit', parentName }) {
  const isCreate = mode === 'create';
  const [name, setName] = React.useState(isCreate ? '' : node.name);
  const [desc, setDesc] = React.useState(isCreate ? '' : (node.description || ''));
  const [icon, setIcon] = React.useState(isCreate ? '◆' : (ICONS[node.name] || '◆'));
  const [amount, setAmount] = React.useState(isCreate ? '' : String(node.amount || ''));
  const [moveTo, setMoveTo] = React.useState(isCreate ? (parentName || '__root__') : '');

  const movables = isCreate ? allCats : allCats.filter(c => c.name !== node.name);

  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 100,
      background: 'rgba(20,18,14,0.35)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: 16,
    }} onClick={onClose}>
      <div onClick={(e) => e.stopPropagation()} style={{
        background: 'var(--paper)',
        border: '1.5px solid var(--ink)',
        borderRadius: 8,
        boxShadow: '4px 4px 0 var(--ink)',
        width: '100%', maxWidth: 420, maxHeight: '100%',
        display: 'flex', flexDirection: 'column',
        fontFamily: 'var(--hand)',
      }}>
        {/* Header */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '12px 14px',
          borderBottom: '1.2px solid var(--rule)',
        }}>
          <div style={{ fontFamily: 'var(--display)', fontSize: 20 }}>
            {isCreate ? 'New category' : 'Edit category'}
          </div>
          <button className="icon-btn" onClick={onClose} title="Close">✕</button>
        </div>

        {/* Body */}
        <div style={{ padding: 14, overflowY: 'auto', flex: 1, fontSize: 13 }}>
          <div style={{ marginBottom: 12 }}>
            <div className="muted" style={{ fontSize: 11, marginBottom: 4, textTransform: 'uppercase', letterSpacing: 0.5 }}>
              Name
            </div>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={isCreate ? 'e.g. Subscriptions' : ''}
              style={{
                width: '100%', padding: '6px 8px',
                border: '1.2px solid var(--rule)', borderRadius: 4,
                background: 'var(--paper-2)', fontFamily: 'var(--hand)', fontSize: 14,
              }} />
          </div>

          <div style={{ marginBottom: 12 }}>
            <div className="muted" style={{ fontSize: 11, marginBottom: 4, textTransform: 'uppercase', letterSpacing: 0.5 }}>
              Description
            </div>
            <textarea
              value={desc}
              placeholder="Optional — what belongs in this bucket?"
              onChange={(e) => setDesc(e.target.value)}
              rows={2}
              style={{
                width: '100%', padding: '6px 8px',
                border: '1.2px solid var(--rule)', borderRadius: 4,
                background: 'var(--paper-2)', fontFamily: 'var(--hand)', fontSize: 13,
                resize: 'vertical',
              }} />
            <div className="muted" style={{ fontSize: 10, marginTop: 4, fontStyle: 'italic' }}>
              Used to auto-categorize real-world expenses when you upload them.
            </div>
          </div>

          <div style={{ marginBottom: 12 }}>
            <div className="muted" style={{ fontSize: 11, marginBottom: 4, textTransform: 'uppercase', letterSpacing: 0.5 }}>
              Monthly amount
            </div>
            <div style={{ position: 'relative' }}>
              <span style={{
                position: 'absolute', left: 8, top: '50%', transform: 'translateY(-50%)',
                fontFamily: 'var(--hand)', fontSize: 14, color: 'var(--muted)',
              }}>$</span>
              <input
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0"
                style={{
                  width: '100%', padding: '6px 8px 6px 20px',
                  border: '1.2px solid var(--rule)', borderRadius: 4,
                  background: 'var(--paper-2)', fontFamily: 'var(--mono, monospace)', fontSize: 14,
                }} />
            </div>
          </div>

          <div style={{ marginBottom: 12 }}>
            <div className="muted" style={{ fontSize: 11, marginBottom: 4, textTransform: 'uppercase', letterSpacing: 0.5 }}>
              Icon
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {ICON_CHOICES.map((ic) => (
                <button key={ic} onClick={() => setIcon(ic)}
                  style={{
                    width: 34, height: 34, fontSize: 18,
                    border: '1.2px solid ' + (icon === ic ? 'var(--ink)' : 'var(--rule)'),
                    background: icon === ic ? 'var(--paper-2)' : 'var(--paper)',
                    borderRadius: 4, cursor: 'pointer',
                    boxShadow: icon === ic ? '1.5px 1.5px 0 var(--ink)' : 'none',
                  }}>{ic}</button>
              ))}
            </div>
          </div>

          <div style={{ marginBottom: 12 }}>
            <div className="muted" style={{ fontSize: 11, marginBottom: 4, textTransform: 'uppercase', letterSpacing: 0.5 }}>
              {isCreate ? 'Parent' : 'Move to'}
            </div>
            <select
              value={moveTo}
              onChange={(e) => setMoveTo(e.target.value)}
              style={{
                width: '100%', padding: '6px 8px',
                border: '1.2px solid var(--rule)', borderRadius: 4,
                background: 'var(--paper-2)', fontFamily: 'var(--hand)', fontSize: 13,
              }}>
              {!isCreate && <option value="">— keep at current location —</option>}
              <option value="__root__">Budget (root)</option>
              {movables.map((c, i) => (
                <option key={i} value={c.name}>{c.name}</option>
              ))}
            </select>
          </div>

          {!isCreate && (
            <div style={{
              marginTop: 18, paddingTop: 12,
              borderTop: '1.2px dashed var(--rule-soft)',
            }}>
              <button
                onClick={() => onDelete(node)}
                style={{
                  width: '100%', padding: '7px 10px',
                  border: '1.2px solid #a33', color: '#a33',
                  background: 'transparent', borderRadius: 4,
                  fontFamily: 'var(--hand)', fontSize: 13, cursor: 'pointer',
                }}>
                Delete "{node.name}"
              </button>
              <div className="muted" style={{ fontSize: 10, textAlign: 'center', marginTop: 4 }}>
                Transactions in this bucket become Unknown.
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div style={{
          padding: '10px 14px',
          borderTop: '1.2px solid var(--rule)',
          display: 'flex', gap: 8, justifyContent: 'flex-end',
        }}>
          <button className="btn-sketch" onClick={onClose}>Cancel</button>
          <button className="btn-sketch solid"
            onClick={() => onSave({ name, description: desc, icon, amount: Number(amount) || 0, moveTo })}>
            {isCreate ? 'Create' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}

// Leaf category view — shown when drilled into a category with no subcategories
function LeafCategoryView({ node, onAddSubcategory }) {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
      height: '100%', minHeight: 320,
      textAlign: 'center',
      padding: '24px 20px',
    }}>
      <div style={{
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10,
        maxWidth: 360,
      }}>
        <div style={{ fontSize: 64, lineHeight: 1, fontFamily: 'var(--hand)' }}>
          {ICONS[node.name] || '◆'}
        </div>
        <div style={{
          fontFamily: 'var(--display)', fontSize: 36, lineHeight: 1.1,
        }}>
          {node.name}
        </div>
        <div className="mono" style={{
          fontSize: 22, color: 'var(--ink-2)',
          padding: '2px 10px',
        }}>
          {fmtMoney(node.amount)} <span className="muted" style={{ fontSize: 14 }}>/ mo</span>
        </div>
        {node.description && (
          <div className="muted" style={{
            fontFamily: 'var(--hand)', fontSize: 13, fontStyle: 'italic',
            maxWidth: 300, marginTop: 4,
          }}>
            {node.description}
          </div>
        )}
      </div>

      <div style={{
        marginTop: 'auto', paddingTop: 32,
        borderTop: '1px dashed var(--rule-soft)',
        width: '100%', maxWidth: 420,
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10,
      }}>
        <div className="muted" style={{
          fontFamily: 'var(--hand)', fontSize: 12, lineHeight: 1.5,
        }}>
          This category doesn't have any subcategories yet.
          You can add one to split it further.
        </div>
        <button
          className="btn-sketch"
          onClick={onAddSubcategory}
          style={{ padding: '6px 14px' }}>
          + Add subcategory
        </button>
      </div>
    </div>
  );
}

// Phone app-header variant with hamburger on left
function AppHeaderHam({ current, onNav, right }) {
  return (
    <div className="app-header">
      <HamburgerMenu current={current} onNav={onNav} />
      <div style={{ flex: 1 }} />
      <div style={{ display: 'flex', gap: 6 }}>{right}</div>
    </div>
  );
}

// Phone (primary): Marimekko rows
function PlanPhone({ drilled, setDrilled, onNav }) {
  const node = drilled || BUDGET;
  const kids = (node.children || []).filter(c => !c.isUnknown);
  const total = kids.reduce((s, c) => s + (c.amount || 0), 0);
  const [editing, setEditing] = React.useState(false);
  const [creating, setCreating] = React.useState(false);

  // build path from drill stack (here we support one level — same as before)
  const path = [{ label: 'Plan', node: null }];
  if (drilled) path.push({ label: drilled.name, node: drilled });
  const jump = (i) => { if (i === 0) setDrilled(null); };

  const allCats = BUDGET.children.filter(c => !c.isUnknown);

  return (
    <PhoneFrame>
      <AppHeaderHam current="plan" onNav={onNav}
        right={<>
          {drilled && (
            <button className="icon-btn" title="Edit category" onClick={() => setEditing(true)}>✎</button>
          )}
          <button className="icon-btn" title="Add category" onClick={() => setCreating(true)}>+</button>
        </>} />
      <PlanCrumbs path={path} onJump={jump}
        rightSlot={<span className="mono muted">{fmtMoney(total)}/mo</span>} />
      <div style={{ flex: 1, position: 'relative', display: 'flex', flexDirection: 'column' }}>
        {drilled && !drilled.children?.length ? (
          <LeafCategoryView node={drilled} onAddSubcategory={() => setCreating(true)} />
        ) : (
          <PlanTreemap rootNode={node} w={296} h={480} mode="rows"
            onDrill={(n) => setDrilled(n)} />
        )}
        {editing && drilled && (
          <EditCategoryPanel
            node={drilled}
            allCats={allCats}
            onClose={() => setEditing(false)}
            onSave={() => setEditing(false)}
            onDelete={() => { setEditing(false); setDrilled(null); }}
          />
        )}
        {creating && (
          <EditCategoryPanel
            mode="create"
            node={{ name: '' }}
            parentName={drilled ? drilled.name : '__root__'}
            allCats={allCats}
            onClose={() => setCreating(false)}
            onSave={() => setCreating(false)}
          />
        )}
      </div>
    </PhoneFrame>
  );
}

// Desktop (primary): breadcrumb + classic squarified w/ inline fill
function PlanDesktop({ drilled, setDrilled, onNav }) {
  const node = drilled || BUDGET;
  const kids = (node.children || []).filter(c => !c.isUnknown);
  const total = kids.reduce((s, c) => s + (c.amount || 0), 0);
  const [editing, setEditing] = React.useState(false);
  const [creating, setCreating] = React.useState(false);

  const path = [{ label: 'Plan', node: null }];
  if (drilled) path.push({ label: drilled.name, node: drilled });
  const jump = (i) => { if (i === 0) setDrilled(null); };

  const allCats = BUDGET.children.filter(c => !c.isUnknown);

  return (
    <div className="desktop">
      <div className="titlebar">
        <span className="dot" /><span className="dot" /><span className="dot" />
        <span style={{ marginLeft: 12, fontFamily: 'var(--hand)', fontSize: 13 }}>plan · monthly budget</span>
      </div>
      <div style={{ display: 'flex', flex: 1, minHeight: 0, position: 'relative' }}>
        <DesktopSidebar current="plan" onNav={onNav} />
        <aside style={{ width: 220, marginLeft: 40, borderRight: '1.5px solid var(--rule)', padding: 14, fontFamily: 'var(--hand)', fontSize: 13 }}>
          <div style={{ fontFamily: 'var(--display)', fontSize: 22, marginBottom: 6 }}>Plan</div>
          <div className="muted" style={{ fontSize: 11, marginBottom: 14 }}>Theoretical monthly budget</div>
          <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
            <li onClick={() => setDrilled(null)}
              style={{ padding: '6px 8px', cursor: 'pointer', borderRadius: 4,
                background: !drilled ? 'var(--paper-2)' : 'transparent', fontWeight: !drilled ? 700 : 400 }}>
              ▾ Budget · <span className="mono muted">{fmtMoney(BUDGET.income)}</span>
            </li>
            {BUDGET.children.filter(c => !c.isUnknown).map((c, i) => (
              <li key={i}>
                <div onClick={() => setDrilled(c)}
                  style={{ padding: '6px 8px 6px 22px', cursor: 'pointer', borderRadius: 4,
                    background: drilled?.name === c.name ? 'var(--paper-2)' : 'transparent',
                    fontWeight: drilled?.name === c.name ? 700 : 400 }}>
                  {c.children?.length ? '▸ ' : '· '}{c.name}
                  <span className="mono muted" style={{ float: 'right' }}>{fmtMoney(c.amount)}</span>
                </div>
              </li>
            ))}
          </ul>
        </aside>
        <main style={{ flex: 1, padding: 18, position: 'relative', minWidth: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
            <PlanCrumbs path={path} onJump={jump}
              rightSlot={<span className="mono muted">{fmtMoney(total)} / mo</span>} />
            <div style={{ display: 'flex', gap: 8 }}>
              {drilled && (
                <button className="btn-sketch" title="Edit category" onClick={() => setEditing(true)}
                  style={{ padding: '6px 10px' }}>✎</button>
              )}
              <button className="btn-sketch solid" title="Add category" style={{ padding: '6px 10px' }}
                onClick={() => setCreating(true)}>+</button>
            </div>
          </div>
          {drilled && !drilled.children?.length ? (
            <LeafCategoryView node={drilled} onAddSubcategory={() => setCreating(true)} />
          ) : (
            <PlanTreemap rootNode={node} w={600} h={440} mode="classic"
              onDrill={(n) => setDrilled(n)} />
          )}
          {editing && drilled && (
            <EditCategoryPanel
              node={drilled}
              allCats={allCats}
              onClose={() => setEditing(false)}
              onSave={() => setEditing(false)}
              onDelete={() => { setEditing(false); setDrilled(null); }}
            />
          )}
          {creating && (
            <EditCategoryPanel
              mode="create"
              node={{ name: '' }}
              parentName={drilled ? drilled.name : '__root__'}
              allCats={allCats}
              onClose={() => setCreating(false)}
              onSave={() => setCreating(false)}
            />
          )}
        </main>
      </div>
    </div>
  );
}

Object.assign(window, { PlanPhone, PlanDesktop, PlanTreemap, PlanCrumbs, HamburgerMenu, AppHeaderHam, DesktopSidebar, LeafCategoryView });
