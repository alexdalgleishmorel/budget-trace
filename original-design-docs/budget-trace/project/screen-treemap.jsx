// Treemap screen wireframes — 3 variations each (root + drilled)

function Treemap({ rootNode, w, h, mode = 'classic', onDrill, showFill = false }) {
  // mode: classic | rows | nested-with-fill
  const items = (rootNode.children || []).map(c => ({
    node: c, value: Math.max(c.amount || c.actual || 1, 1),
  }));
  const PAD = 4;

  if (mode === 'rows') {
    // Marimekko style — stacked rows, each row split horizontally
    const rows = items;
    const total = rows.reduce((s, r) => s + r.value, 0);
    let yy = 0;
    return (
      <div style={{ position: 'relative', width: w, height: h }}>
        {rows.map((r, i) => {
          const rh = (r.value / total) * h;
          const y0 = yy;
          yy += rh;
          return (
            <div key={i}
              className="row-tile"
              onClick={() => onDrill && onDrill(r.node)}
              style={{
                position: 'absolute',
                left: 0, top: y0 + 1,
                width: w, height: rh - 2,
                background: catColor(r.node),
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                padding: '0 12px',
              }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span className="display" style={{ fontSize: 18 }}>{ICONS[r.node.name] || '◆'}</span>
                <span className="tile-name">{r.node.name}</span>
              </div>
              <span className="tile-amt">{fmtMoney(r.node.amount)}</span>
            </div>
          );
        })}
      </div>
    );
  }

  // Classic squarified
  const rects = squarify(items, 0, 0, w, h);
  return (
    <div style={{ position: 'relative', width: w, height: h }}>
      {rects.map((r, i) => {
        const node = r.node;
        const isOver = node.actual > node.amount && node.amount > 0;
        const fillPct = showFill && node.amount > 0
          ? Math.min(1.5, (node.actual || 0) / node.amount)
          : 0;
        const small = r.w < 80 || r.h < 60;
        return (
          <div key={i}
            className={'tile' + (small ? ' small' : '') + (isOver ? ' over' : '')}
            onClick={() => onDrill && onDrill(node)}
            style={{
              position: 'absolute',
              left: r.x + PAD/2, top: r.y + PAD/2,
              width: r.w - PAD, height: r.h - PAD,
              background: catColor(node),
            }}>
            {showFill && (
              <div className={'tile-fill' + (isOver ? ' over' : '')}
                style={{ width: Math.min(100, fillPct * 100) + '%' }} />
            )}
            <div style={{ position: 'relative', zIndex: 1 }}>
              <div className="tile-name">{node.name}</div>
              {!small && (
                <div className="tile-amt">
                  {fmtMoney(node.amount)}
                  {showFill && node.amount > 0 && (
                    <span style={{ marginLeft: 6, opacity: 0.7 }}>
                      → {fmtMoney(node.actual)}
                    </span>
                  )}
                </div>
              )}
            </div>
            <div className="tile-corner" />
            {isOver && !small && (
              <span className="over-chip" style={{ position: 'absolute', bottom: 6, right: 6, zIndex: 2 }}>
                +{fmtMoney(node.actual - node.amount)}
              </span>
            )}
          </div>
        );
      })}
    </div>
  );
}

function PhoneFrame({ children }) {
  return <div className="phone">{children}</div>;
}

function AppHeader({ title, left, right }) {
  return (
    <div className="app-header">
      <div style={{ width: 28 }}>{left}</div>
      <div className="title">{title}</div>
      <div>{right}</div>
    </div>
  );
}

// ── Variation A: Classic squarified, color tiles, drill via tap ──
function TreemapA({ drilled, setDrilled }) {
  const node = drilled || BUDGET;
  return (
    <PhoneFrame>
      <AppHeader
        title={node.name}
        left={drilled ? <button className="icon-btn" onClick={() => setDrilled(null)}>←</button> : <button className="icon-btn">⌂</button>}
        right={<button className="pill">+ Add</button>}
      />
      <div style={{ flex: 1, position: 'relative' }}>
        <Treemap rootNode={node} w={296} h={520} mode="classic"
          onDrill={(n) => n.children?.length && setDrilled(n)} />
      </div>
    </PhoneFrame>
  );
}

// ── Variation B: Treemap + breadcrumb + inline progress fill ──
function TreemapB({ drilled, setDrilled }) {
  const node = drilled || BUDGET;
  const total = (node.children || []).reduce((s, c) => s + (c.amount || 0), 0);
  return (
    <PhoneFrame>
      <AppHeader
        title="Budget Trace"
        left={<button className="icon-btn">⌂</button>}
        right={<button className="pill">Mar ‘26</button>}
      />
      <div className="crumbs">
        <span>Budget</span>
        {drilled && <><span>›</span><b>{drilled.name}</b></>}
        <span style={{ marginLeft: 'auto' }} className="mono muted">{fmtMoney(total)}</span>
      </div>
      <div style={{ flex: 1, position: 'relative' }}>
        <Treemap rootNode={node} w={296} h={490} mode="classic" showFill={true}
          onDrill={(n) => n.children?.length && setDrilled(n)} />
      </div>
    </PhoneFrame>
  );
}

// ── Variation C: Marimekko rows (more text-friendly), tap to drill ──
function TreemapC({ drilled, setDrilled }) {
  const node = drilled || BUDGET;
  return (
    <PhoneFrame>
      <AppHeader
        title={node.name.toUpperCase()}
        left={drilled ? <button className="icon-btn" onClick={() => setDrilled(null)}>←</button> : <button className="icon-btn">≡</button>}
        right={<button className="pill">+ Group</button>}
      />
      <div style={{ padding: '0 4px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span className="display" style={{ fontSize: 22 }}>{fmtMoney((node.children || []).reduce((s,c)=>s+(c.amount||0),0))}</span>
        <span className="label muted">of {fmtMoney(BUDGET.income)} income</span>
      </div>
      <div style={{ flex: 1, position: 'relative' }}>
        <Treemap rootNode={node} w={296} h={460} mode="rows"
          onDrill={(n) => n.children?.length && setDrilled(n)} />
      </div>
    </PhoneFrame>
  );
}

// ── Desktop: tree + treemap side by side (one variation, fits well desktop) ──
function TreemapDesktop({ drilled, setDrilled }) {
  const node = drilled || BUDGET;
  return (
    <div className="desktop">
      <div className="titlebar">
        <span className="dot" /><span className="dot" /><span className="dot" />
        <span style={{ marginLeft: 12, fontFamily: 'var(--hand)', fontSize: 13 }}>budget-trace · march 2026</span>
      </div>
      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        <aside style={{ width: 220, borderRight: '1.5px solid var(--rule)', padding: 14, fontFamily: 'var(--hand)', fontSize: 13 }}>
          <div style={{ fontFamily: 'var(--display)', fontSize: 22, marginBottom: 6 }}>Budget</div>
          <div className="muted" style={{ fontSize: 11, marginBottom: 14 }}>Mar 1 – Mar 31, 2026</div>
          <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
            <li onClick={() => setDrilled(null)}
              style={{ padding: '6px 8px', cursor: 'pointer', borderRadius: 4,
                background: !drilled ? 'var(--paper-2)' : 'transparent', fontWeight: !drilled ? 700 : 400 }}>
              ▾ Budget · <span className="mono muted">{fmtMoney(BUDGET.income)}</span>
            </li>
            {BUDGET.children.map((c, i) => (
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
          <button className="btn-sketch" style={{ marginTop: 14, width: '100%' }}>+ Add Group</button>
        </aside>
        <main style={{ flex: 1, padding: 18, position: 'relative', minWidth: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
            <div className="crumbs" style={{ padding: 0 }}>
              <span>Budget</span>{drilled && <><span>›</span><b>{drilled.name}</b></>}
            </div>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn-sketch">Edit</button>
              <button className="btn-sketch solid">+ Add Category</button>
            </div>
          </div>
          <Treemap rootNode={node} w={600} h={440} mode="classic" showFill
            onDrill={(n) => n.children?.length && setDrilled(n)} />
        </main>
      </div>
    </div>
  );
}

Object.assign(window, { TreemapA, TreemapB, TreemapC, TreemapDesktop, Treemap, PhoneFrame, AppHeader });
