// Hi-fi Plan — treemap (desktop), marimekko rows (mobile), leaf view, edit modal.

function HFTreemapResponsive({ rootNode, mode, onDrill }) {
  const ref = React.useRef(null);
  const [size, setSize] = React.useState({ w: 0, h: 0 });
  React.useLayoutEffect(() => {
    if (!ref.current) return;
    const ro = new ResizeObserver((entries) => {
      for (const e of entries) {
        setSize({ w: e.contentRect.width, h: e.contentRect.height });
      }
    });
    ro.observe(ref.current);
    return () => ro.disconnect();
  }, []);
  return (
    <div ref={ref} style={{ position: 'absolute', inset: 0 }}>
      {size.w > 0 && size.h > 0 && (
        <HFTreemap rootNode={rootNode} w={size.w} h={size.h}
          mode={mode} onDrill={onDrill} />
      )}
    </div>
  );
}

/* ========== Treemap ========== */

function HFTreemap({ rootNode, w, h, mode = 'classic', onDrill }) {
  const kids = (rootNode.children || []).filter(c => !c.isUnknown);
  const items = kids.map((c, i) => ({
    node: c, value: Math.max(c.amount || 1, 1), idx: i,
  }));
  const total = items.reduce((s, r) => s + r.value, 0);

  // tone mapping: largest = darkest
  const sorted = [...items].sort((a, b) => b.value - a.value);
  const toneMap = new Map();
  sorted.forEach((it, i) => {
    const tone = Math.min(5, Math.max(1, 5 - Math.floor(i * 5 / Math.max(sorted.length, 1))));
    toneMap.set(it.node.name, tone);
  });

  if (mode === 'rows') {
    let yy = 0;
    return (
      <div style={{ position: 'relative', width: w, height: h }}>
        {items.map((r, i) => {
          const rh = (r.value / total) * h;
          const y0 = yy; yy += rh;
          const tone = toneMap.get(r.node.name);
          return (
            <HFTile key={i} node={r.node} tone={tone}
              x={0} y={y0 + 3} w={w} h={rh - 6}
              onDrill={onDrill} layout="row" />
          );
        })}
      </div>
    );
  }

  const rects = squarify(items, 0, 0, w, h);
  const PAD = 6;
  return (
    <div style={{ position: 'relative', width: w, height: h }}>
      {rects.map((r, i) => {
        const tone = toneMap.get(r.node.name);
        return (
          <HFTile key={i} node={r.node} tone={tone}
            x={r.x + PAD/2} y={r.y + PAD/2}
            w={r.w - PAD} h={r.h - PAD}
            onDrill={onDrill} />
        );
      })}
    </div>
  );
}

function HFTile({ node, tone, x, y, w, h, onDrill, layout = 'rect' }) {
  const small = w < 120 || h < 70;
  const tiny = w < 80 || h < 54;

  return (
    <div
      className="tile-hf"
      data-tone={tone}
      onClick={() => onDrill && onDrill(node)}
      style={{
        position: 'absolute',
        left: x, top: y, width: w, height: h,
        padding: small ? 12 : 16,
        display: 'flex',
        flexDirection: layout === 'row' ? 'row' : 'column',
        alignItems: layout === 'row' ? 'center' : 'center',
        justifyContent: 'center',
        gap: layout === 'row' ? 12 : 10,
        color: 'var(--tile-ink)',
        textAlign: layout === 'row' ? 'left' : 'center',
      }}>
      {layout === 'row' ? (
        <>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0, flex: 1 }}>
            <div style={{
              width: 32, height: 32, borderRadius: 10,
              background: 'var(--surface)',
              border: '1px solid var(--rule-strong)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}>
              <CatIcon name={node.name} size={17} />
            </div>
            <div style={{ minWidth: 0 }}>
              <div style={{
                fontFamily: 'var(--font-display)',
                fontSize: 15, fontWeight: 600, letterSpacing: -0.01,
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
              }}>{node.name}</div>
              <div className="num" style={{
                fontSize: 11, color: 'var(--tile-ink-2)', marginTop: 1,
              }}>
                {Math.round((node.amount / (BUDGET.income || 1)) * 100)}% of income
              </div>
            </div>
          </div>
          <div className="num" style={{
            fontSize: 17, fontWeight: 500, letterSpacing: -0.015,
            whiteSpace: 'nowrap', flexShrink: 0,
          }}>
            {fmtMoney(node.amount)}
          </div>
        </>
      ) : (
        <>
          <div style={{
            width: tiny ? 30 : 40, height: tiny ? 30 : 40, borderRadius: 12,
            background: 'var(--surface)',
            border: '1px solid var(--rule-strong)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0,
          }}>
            <CatIcon name={node.name} size={tiny ? 15 : 20} />
          </div>
          <div style={{ width: '100%', minWidth: 0, overflow: 'hidden' }}>
            <div style={{
              fontFamily: 'var(--font-display)',
              fontSize: small ? 14 : 18,
              fontWeight: 600, letterSpacing: -0.015,
              lineHeight: 1.15,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
            }}>{node.name}</div>
            {!tiny && (
              <div className="num" style={{
                fontSize: 11, color: 'var(--tile-ink-2)', marginTop: 4,
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
              }}>
                {Math.round((node.amount / (BUDGET.income || 1)) * 100)}% of income
              </div>
            )}
            {!tiny && (
              <div className="num" style={{
                fontSize: small ? 16 : 24, fontWeight: 500, letterSpacing: -0.02,
                color: 'var(--tile-ink)', marginTop: 8,
                whiteSpace: 'nowrap',
              }}>{fmtMoney(node.amount)}</div>
            )}
            {tiny && (
              <div className="num" style={{ fontSize: 11, color: 'var(--tile-ink-2)', marginTop: 2, whiteSpace: 'nowrap' }}>
                {fmtMoney(node.amount)}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

/* ========== Leaf category view ========== */

function HFLeafView({ node, onAdd }) {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      height: '100%', padding: '24px 20px',
      gap: 20,
    }}>
      <div style={{
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14,
        textAlign: 'center', marginTop: 'auto',
      }}>
        <div style={{
          width: 84, height: 84, borderRadius: 26,
          background: 'var(--surface)',
          border: '1px solid var(--rule-strong)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: 'var(--shadow-1)',
        }}>
          <CatIcon name={node.name} size={40} stroke={1.5} />
        </div>
        <div className="display" style={{ fontSize: 30, letterSpacing: -0.025 }}>
          {node.name}
        </div>
        <div className="num" style={{
          fontSize: 30, fontWeight: 500, letterSpacing: -0.02, color: 'var(--ink)',
        }}>
          {fmtMoney(node.amount)}
          <span style={{
            fontFamily: 'var(--font-text)',
            fontSize: 13, color: 'var(--ink-4)', marginLeft: 6, fontWeight: 400,
          }}>/ mo</span>
        </div>
        {node.description && (
          <div style={{
            fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5,
            maxWidth: 320, marginTop: 4,
          }}>
            {node.description}
          </div>
        )}
      </div>

      <div style={{
        marginTop: 'auto', paddingTop: 24, width: '100%', maxWidth: 380,
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12,
        borderTop: '1px dashed var(--rule-strong)',
      }}>
        <div style={{
          fontSize: 12.5, color: 'var(--ink-4)', lineHeight: 1.5,
          textAlign: 'center', marginTop: 16,
        }}>
          No subcategories yet. Break this into smaller buckets if you want to track it in more detail.
        </div>
        <button className="btn" onClick={onAdd}>
          <Icon name="plus" size={15} stroke={2} />
          Add subcategory
        </button>
      </div>
    </div>
  );
}

/* ========== Edit modal ========== */

const HF_ICON_CHOICES = [
  'home', 'fork', 'piggy', 'shield', 'zap', 'wifi', 'car', 'fuel',
  'cart', 'sparkle', 'bag', 'plane', 'hourglass', 'music', 'coffee',
  'heart', 'briefcase',
];

function HFEditModal({ node, mode = 'edit', parentName, onClose, onSave, onDelete }) {
  const isCreate = mode === 'create';
  const [name, setName] = React.useState(isCreate ? '' : node.name);
  const [desc, setDesc] = React.useState(isCreate ? '' : (node.description || ''));
  const [icon, setIcon] = React.useState(isCreate ? 'sparkle' : (CAT_ICONS[node.name] || 'sparkle'));
  const [amount, setAmount] = React.useState(isCreate ? '' : String(node.amount || ''));
  const [parent, setParent] = React.useState(isCreate ? (parentName || '__root__') : '');

  return (
    <ModalHF onClose={onClose} width={460}>
      <div style={{
        padding: '18px 22px 14px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        borderBottom: '1px solid var(--rule)',
      }}>
        <div className="display" style={{ fontSize: 20 }}>
          {isCreate ? 'New category' : 'Edit category'}
        </div>
        <button className="btn icon ghost" onClick={onClose}>
          <Icon name="close" size={18} />
        </button>
      </div>

      <div style={{ padding: '18px 22px', overflowY: 'auto', flex: 1 }}>
        <Field label="Name">
          <input className="input" value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={isCreate ? 'e.g. Subscriptions' : ''} />
        </Field>

        <Field label="Monthly amount">
          <div style={{ position: 'relative' }}>
            <span style={{
              position: 'absolute', left: 13, top: '50%', transform: 'translateY(-50%)',
              color: 'var(--ink-4)', fontFamily: 'var(--font-mono)', fontSize: 14,
            }}>$</span>
            <input className="input mono" type="number" value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0"
              style={{ paddingLeft: 26 }} />
          </div>
        </Field>

        <Field label="Description" sub="Helps auto-categorize uploaded expenses">
          <textarea className="input" rows={2} value={desc}
            onChange={(e) => setDesc(e.target.value)}
            placeholder="What belongs in this bucket?" />
        </Field>

        <Field label="Icon">
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {HF_ICON_CHOICES.map((ic) => {
              const active = icon === ic;
              return (
                <button key={ic} onClick={() => setIcon(ic)}
                  style={{
                    width: 38, height: 38, borderRadius: 10,
                    border: '1px solid ' + (active ? 'var(--ink)' : 'var(--rule-strong)'),
                    background: active ? 'var(--ink)' : 'var(--surface-2)',
                    color: active ? 'var(--bg)' : 'var(--ink-2)',
                    cursor: 'pointer',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    transition: 'all var(--dur-fast) var(--ease)',
                  }}>
                  <Icon name={ic} size={17} stroke={1.6} />
                </button>
              );
            })}
          </div>
        </Field>

        <Field label={isCreate ? 'Parent category' : 'Move to'}>
          <select className="input" value={parent}
            onChange={(e) => setParent(e.target.value)}>
            {!isCreate && <option value="">Keep at current location</option>}
            <option value="__root__">Budget (root)</option>
            {BUDGET.children.filter(c => !c.isUnknown && c.name !== name).map((c, i) => (
              <option key={i} value={c.name}>{c.name}</option>
            ))}
          </select>
        </Field>

        {!isCreate && (
          <div style={{
            marginTop: 22, paddingTop: 18,
            borderTop: '1px dashed var(--rule-strong)',
          }}>
            <button onClick={() => onDelete && onDelete(node)}
              style={{
                width: '100%', padding: '10px 12px',
                border: '1px solid var(--neg-border)',
                color: 'var(--neg)',
                background: 'var(--neg-bg)',
                borderRadius: 12,
                font: 'inherit', fontSize: 13, fontWeight: 500,
                cursor: 'pointer',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
              }}>
              <Icon name="trash" size={15} stroke={1.8} />
              Delete "{node.name}"
            </button>
            <div style={{
              fontSize: 11.5, color: 'var(--ink-4)',
              textAlign: 'center', marginTop: 6,
            }}>
              Transactions in this bucket will move to Unknown.
            </div>
          </div>
        )}
      </div>

      <div style={{
        padding: '14px 22px',
        borderTop: '1px solid var(--rule)',
        display: 'flex', gap: 8, justifyContent: 'flex-end',
        background: 'var(--surface-2)',
      }}>
        <button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn primary" onClick={() => onSave && onSave({ name, desc, icon, amount })}>
          {isCreate ? 'Create category' : 'Save changes'}
        </button>
      </div>
    </ModalHF>
  );
}

function Field({ label, sub, children }) {
  return (
    <div style={{ marginBottom: 16 }}>
      <div className="label" style={{ marginBottom: 7 }}>{label}</div>
      {children}
      {sub && <div style={{
        fontSize: 11.5, color: 'var(--ink-4)', marginTop: 5,
      }}>{sub}</div>}
    </div>
  );
}

/* ========== Plan Mobile ========== */

function PlanPhoneHF({ drilled, setDrilled, onNav }) {
  const node = drilled || BUDGET;
  const kids = (node.children || []).filter(c => !c.isUnknown);
  const total = kids.length ? kids.reduce((s, c) => s + (c.amount || 0), 0) : (node.amount || 0);
  const [editing, setEditing] = React.useState(false);
  const [creating, setCreating] = React.useState(false);

  const path = [{ label: 'Plan' }];
  if (drilled) path.push({ label: drilled.name });
  const jump = (i) => { if (i === 0) setDrilled(null); };

  return (
    <>
      <StatusBar />
      <MobileHeaderHF
        title="Plan"
        left={
          drilled ? (
            <button className="btn icon ghost" onClick={() => setDrilled(null)}>
              <Icon name="chevron-left" size={20} stroke={1.8} />
            </button>
          ) : null
        }
        right={
          <>
            {drilled && (
              <button className="btn icon ghost" onClick={() => setEditing(true)}>
                <Icon name="edit" size={18} stroke={1.8} />
              </button>
            )}
            <button className="btn icon ghost" onClick={() => setCreating(true)}>
              <Icon name="plus" size={20} stroke={1.8} />
            </button>
          </>
        }
      />

      <div style={{ padding: '0 18px 14px' }}>
        <div style={{
          display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
          gap: 12,
        }}>
          <div style={{ minWidth: 0 }}>
            <div className="label">{drilled ? 'Category' : 'Monthly plan'}</div>
            <div className="display" style={{ fontSize: 28, letterSpacing: -0.025, marginTop: 2 }}>
              {drilled ? drilled.name : 'Budget'}
            </div>
          </div>
          <div style={{ textAlign: 'right', flexShrink: 0 }}>
            <div className="label">Total</div>
            <div className="num" style={{
              fontSize: 22, fontWeight: 500, letterSpacing: -0.015, marginTop: 2,
            }}>
              {fmtMoney(total)}
            </div>
          </div>
        </div>
        {path.length > 1 && (
          <div style={{ marginTop: 10 }}>
            <Crumbs path={path} onJump={jump} />
          </div>
        )}
      </div>

      <div style={{ flex: 1, padding: '0 16px 10px', display: 'flex', flexDirection: 'column', position: 'relative', minHeight: 0 }}>
        {drilled && !drilled.children?.length ? (
          <HFLeafView node={drilled} onAdd={() => setCreating(true)} />
        ) : (
          <HFTreemap rootNode={node} w={358} h={540} mode="rows"
            onDrill={(n) => setDrilled(n)} />
        )}
      </div>

      <BottomTabsHF current="plan" onNav={onNav} />
      <HomeIndicator />

      {editing && drilled && (
        <HFEditModal node={drilled} onClose={() => setEditing(false)}
          onSave={() => setEditing(false)}
          onDelete={() => { setEditing(false); setDrilled(null); }} />
      )}
      {creating && (
        <HFEditModal mode="create" node={{ name: '' }}
          parentName={drilled ? drilled.name : '__root__'}
          onClose={() => setCreating(false)}
          onSave={() => setCreating(false)} />
      )}
    </>
  );
}

/* ========== Plan Desktop ========== */

function PlanDesktopHF({ drilled, setDrilled, onNav }) {
  const node = drilled || BUDGET;
  const kids = (node.children || []).filter(c => !c.isUnknown);
  const total = kids.length ? kids.reduce((s, c) => s + (c.amount || 0), 0) : (node.amount || 0);
  const [editing, setEditing] = React.useState(false);
  const [creating, setCreating] = React.useState(false);

  const path = [{ label: 'Plan' }];
  if (drilled) path.push({ label: drilled.name });
  const jump = (i) => { if (i === 0) setDrilled(null); };

  return (
    <>
      <WindowTitleBar title="Budget Trace — Plan" />
      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        <DesktopSideNav current="plan" onNav={onNav} />
        <main style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, position: 'relative' }}>
          {/* Top strip */}
          <div style={{
            padding: '22px 28px 18px',
            display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
            borderBottom: '1px solid var(--rule)',
          }}>
            <div>
              <Crumbs path={path} onJump={jump} />
              <div className="display" style={{ fontSize: 30, letterSpacing: -0.025, marginTop: 6 }}>
                {drilled ? drilled.name : 'Monthly plan'}
              </div>
              <div style={{ fontSize: 13, color: 'var(--ink-3)', marginTop: 4 }}>
                {drilled
                  ? (drilled.children?.length ? `${drilled.children.length} subcategories` : 'Leaf category')
                  : 'Theoretical budget — where every dollar is supposed to go.'}
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'flex-end', gap: 24 }}>
              <div style={{ textAlign: 'right' }}>
                <div className="label">{drilled ? 'Subtotal' : 'Planned / mo'}</div>
                <div className="num" style={{
                  fontSize: 30, fontWeight: 500, letterSpacing: -0.02, marginTop: 2,
                }}>
                  {fmtMoney(total)}
                </div>
              </div>
              <div style={{ display: 'flex', gap: 8 }}>
                {drilled && (
                  <button className="btn" onClick={() => setEditing(true)}>
                    <Icon name="edit" size={15} stroke={1.8} />
                    Edit
                  </button>
                )}
                <button className="btn primary" onClick={() => setCreating(true)}>
                  <Icon name="plus" size={15} stroke={2} />
                  New category
                </button>
              </div>
            </div>
          </div>

          {/* Body */}
          <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
            {/* Sub-rail: tree */}
            <aside style={{
              width: 230, flexShrink: 0,
              borderRight: '1px solid var(--rule)',
              padding: '18px 14px',
              overflowY: 'auto',
            }}>
              <div className="label" style={{ padding: '0 8px 8px' }}>Tree</div>
              <div
                onClick={() => setDrilled(null)}
                style={{
                  padding: '8px 10px', borderRadius: 10, cursor: 'pointer',
                  background: !drilled ? 'var(--surface-2)' : 'transparent',
                  fontWeight: !drilled ? 600 : 400,
                  fontSize: 13.5,
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                  border: !drilled ? '1px solid var(--rule)' : '1px solid transparent',
                }}>
                <span>Budget</span>
                <span className="num" style={{ color: 'var(--ink-4)', fontSize: 12 }}>
                  {fmtMoney(BUDGET.income)}
                </span>
              </div>
              <div style={{ marginTop: 2 }}>
                {BUDGET.children.filter(c => !c.isUnknown).map((c, i) => {
                  const active = drilled?.name === c.name;
                  return (
                    <div key={i}
                      onClick={() => setDrilled(c)}
                      style={{
                        padding: '7px 10px 7px 20px',
                        borderRadius: 10, cursor: 'pointer',
                        background: active ? 'var(--surface-2)' : 'transparent',
                        fontWeight: active ? 600 : 400,
                        fontSize: 13,
                        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                        gap: 8,
                        border: active ? '1px solid var(--rule)' : '1px solid transparent',
                        color: active ? 'var(--ink)' : 'var(--ink-2)',
                      }}>
                      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 9, minWidth: 0 }}>
                        <CatIcon name={c.name} size={14} stroke={1.7} />
                        <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                          {c.name}
                        </span>
                      </span>
                      <span className="num" style={{ color: 'var(--ink-4)', fontSize: 12, flexShrink: 0 }}>
                        {fmtMoney(c.amount)}
                      </span>
                    </div>
                  );
                })}
              </div>
            </aside>

            {/* Main canvas */}
            <div style={{ flex: '0 0 auto', padding: '22px 24px', position: 'relative', minWidth: 0 }}>
              {drilled && !drilled.children?.length ? (
                <HFLeafView node={drilled} onAdd={() => setCreating(true)} />
              ) : (
                <div style={{ borderRadius: 18, overflow: 'hidden', position: 'relative' }}>
                  <HFTreemap rootNode={node} w={620} h={480} mode="classic"
                    onDrill={(n) => setDrilled(n)} />
                </div>
              )}
            </div>
          </div>

          {editing && drilled && (
            <HFEditModal node={drilled} onClose={() => setEditing(false)}
              onSave={() => setEditing(false)}
              onDelete={() => { setEditing(false); setDrilled(null); }} />
          )}
          {creating && (
            <HFEditModal mode="create" node={{ name: '' }}
              parentName={drilled ? drilled.name : '__root__'}
              onClose={() => setCreating(false)}
              onSave={() => setCreating(false)} />
          )}
        </main>
      </div>
    </>
  );
}

Object.assign(window, {
  HFTreemap, HFTreemapResponsive, HFTile, HFLeafView, HFEditModal, PlanPhoneHF, PlanDesktopHF,
});
