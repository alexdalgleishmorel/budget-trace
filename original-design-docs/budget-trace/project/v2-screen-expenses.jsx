// v2 — Expenses (single consolidated screen)
// One view: Dropzone → Needs Review → All Expenses
// (was previously split into Upload + Manage — now merged)

function ExpensesPhone({ txns, onAssign, onNav }) {
  const unknown = txns.filter(t => !t.cat);
  const known = txns.filter(t => t.cat);
  return (
    <PhoneFrame>
      <AppHeaderHam current="expenses" onNav={onNav}
        right={<button className="pill">Mar ‘26</button>} />

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* Dropzone */}
        <div className="dropzone" style={{ marginBottom: 10 }}>
          <div className="display" style={{ fontSize: 22, lineHeight: 1 }}>↓</div>
          <div style={{ marginTop: 4 }}>Drop your bank CSV</div>
          <div className="muted" style={{ fontSize: 11, marginTop: 2 }}>chase · amex · wells fargo</div>
        </div>

        {/* Needs review */}
        {unknown.length > 0 && (
          <>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '4px 4px 6px' }}>
              <span className="display" style={{ fontSize: 18 }}>Needs review</span>
              <span className="mono muted">{unknown.length} of {txns.length}</span>
            </div>
            <div style={{ border: '1.2px solid var(--rule-soft)', borderRadius: 6, background: 'var(--paper)', marginBottom: 14 }}>
              {unknown.map((t, i) => (
                <div className="txn-row" key={i}>
                  <div>
                    <div className="merchant">{t.merchant}</div>
                    <div className="meta">{t.date} · {fmtMoney(t.amount)}</div>
                  </div>
                  <CategoryChip value={null} onChange={(cat) => onAssign(t, cat)} />
                </div>
              ))}
            </div>
          </>
        )}

        {/* All expenses */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '4px 4px 6px' }}>
          <span className="display" style={{ fontSize: 18 }}>All expenses</span>
          <span className="mono muted">{txns.length} txns</span>
        </div>
        <div style={{ display: 'flex', gap: 6, marginBottom: 8 }}>
          <input
            type="text"
            placeholder="Search merchant…"
            style={{
              flex: 1, padding: '6px 8px',
              border: '1.2px solid var(--rule)', borderRadius: 4,
              background: 'var(--paper-2)', fontFamily: 'var(--hand)', fontSize: 13,
              minWidth: 0,
            }} />
          <select
            defaultValue=""
            style={{
              padding: '6px 8px', maxWidth: 130,
              border: '1.2px solid var(--rule)', borderRadius: 4,
              background: 'var(--paper-2)', fontFamily: 'var(--hand)', fontSize: 13,
            }}>
            <option value="">All cats</option>
            {BUDGET.children.filter(c => !c.isUnknown).map((c, i) => (
              <option key={i} value={c.name}>{c.name}</option>
            ))}
          </select>
        </div>
        <div className="sticky" style={{ alignSelf: 'flex-start', marginBottom: 6 }}>
          Tap any category to reassign. New buckets live in Plan.
        </div>
        <div style={{ borderTop: '1.2px dashed var(--rule-soft)' }}>
          {known.map((t, i) => (
            <div className="txn-row" key={i}>
              <div>
                <div className="merchant">{t.merchant}</div>
                <div className="meta">{t.date}</div>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
                <span className="amt">{fmtMoney(t.amount)}</span>
                <CategoryChip value={t.cat} onChange={(cat) => onAssign(t, cat)} />
              </div>
            </div>
          ))}
        </div>
      </div>
    </PhoneFrame>
  );
}

function ExpensesDesktop({ txns, onAssign, onNav }) {
  const unknown = txns.filter(t => !t.cat);
  return (
    <div className="desktop" style={{ height: 560 }}>
      <div className="titlebar">
        <span className="dot" /><span className="dot" /><span className="dot" />
        <span style={{ marginLeft: 12, fontFamily: 'var(--hand)', fontSize: 13 }}>expenses · march 2026</span>
      </div>

      <div style={{ display: 'flex', flex: 1, minHeight: 0, position: 'relative' }}>
        <DesktopSidebar current="expenses" onNav={onNav} />
        {/* Left column: upload + review */}
        <aside style={{ width: 320, marginLeft: 40, padding: 18, borderRight: '1.5px solid var(--rule)', display: 'flex', flexDirection: 'column', minHeight: 0 }}>
          <div className="display" style={{ fontSize: 22, marginBottom: 2 }}>Upload</div>
          <div className="muted" style={{ fontSize: 11, marginBottom: 10 }}>CSV, OFX, or paste</div>
          <div className="dropzone" style={{ marginBottom: 14 }}>
            <div className="display" style={{ fontSize: 26, lineHeight: 1 }}>↓</div>
            <div style={{ marginTop: 6 }}>Drop file or paste here</div>
            <div className="muted" style={{ fontSize: 11, marginTop: 4 }}>any bank export</div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 6 }}>
            <div className="display" style={{ fontSize: 18 }}>Needs review</div>
            <span className="mono muted">{unknown.length} unknown</span>
          </div>
          {unknown.length > 0 && (
            <div className="sticky" style={{ marginBottom: 8 }}>
              Assign a category — or create one in Plan if you need a new bucket.
            </div>
          )}
          <div style={{ flex: 1, overflowY: 'auto', border: '1.2px solid var(--rule-soft)', borderRadius: 6 }}>
            {unknown.length === 0 ? (
              <div className="muted" style={{ padding: 14, fontSize: 12, textAlign: 'center' }}>Nothing to review. Nice.</div>
            ) : unknown.map((t, i) => (
              <div className="txn-row" key={i}>
                <div>
                  <div className="merchant">{t.merchant}</div>
                  <div className="meta">{t.date}</div>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span className="amt">{fmtMoney(t.amount)}</span>
                  <CategoryChip value={null} onChange={(cat) => onAssign(t, cat)} />
                </div>
              </div>
            ))}
          </div>
        </aside>

        {/* Right column: all expenses */}
        <main style={{ flex: 1, padding: 18, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
            <div>
              <div className="display" style={{ fontSize: 26 }}>All expenses</div>
              <div className="muted" style={{ fontSize: 12 }}>Mar 1 – Mar 31, 2026 · {txns.length} txns</div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8, marginBottom: 10 }}>
            <input
              type="text"
              placeholder="Search merchant…"
              style={{
                flex: 1, padding: '7px 10px',
                border: '1.2px solid var(--rule)', borderRadius: 4,
                background: 'var(--paper-2)', fontFamily: 'var(--hand)', fontSize: 13,
                minWidth: 0,
              }} />
            <select
              defaultValue=""
              style={{
                padding: '7px 10px', minWidth: 160,
                border: '1.2px solid var(--rule)', borderRadius: 4,
                background: 'var(--paper-2)', fontFamily: 'var(--hand)', fontSize: 13,
              }}>
              <option value="">All categories</option>
              {BUDGET.children.filter(c => !c.isUnknown).map((c, i) => (
                <option key={i} value={c.name}>{c.name}</option>
              ))}
            </select>
          </div>
          <div className="sticky" style={{ marginBottom: 10, alignSelf: 'flex-start' }}>
            Click any category chip to reassign. To add a new bucket, head to <b>Plan</b>.
          </div>
          <div style={{ flex: 1, overflowY: 'auto', border: '1.2px solid var(--rule-soft)', borderRadius: 6 }}>
            <div style={{ display: 'grid', gridTemplateColumns: '90px 1fr 160px 120px', gap: 12, padding: '8px 14px', borderBottom: '1.2px solid var(--rule)', fontFamily: 'var(--hand)', fontSize: 11, textTransform: 'uppercase', letterSpacing: 0.06, color: 'var(--ink-3)' }}>
              <span>Date</span><span>Merchant</span><span>Category</span><span style={{ textAlign: 'right' }}>Amount</span>
            </div>
            {txns.map((t, i) => (
              <div key={i} style={{ display: 'grid', gridTemplateColumns: '90px 1fr 160px 120px', gap: 12, padding: '8px 14px', borderBottom: '1px dashed var(--rule-soft)', alignItems: 'center', fontFamily: 'var(--hand)', fontSize: 13 }}>
                <span className="mono">{t.date}</span>
                <span style={{ fontWeight: 500 }}>{t.merchant}</span>
                <CategoryChip value={t.cat} onChange={(cat) => onAssign(t, cat)} />
                <span className="mono" style={{ textAlign: 'right' }}>{fmtMoney(t.amount)}</span>
              </div>
            ))}
          </div>
        </main>
      </div>
    </div>
  );
}

// Clickable chip w/ popover picker
function CategoryChip({ value, onChange }) {
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (!open) return;
    const onDoc = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    setTimeout(() => document.addEventListener('click', onDoc), 0);
    return () => document.removeEventListener('click', onDoc);
  }, [open]);

  const allCats = [];
  BUDGET.children.filter(c => !c.isUnknown).forEach(g => {
    if (g.children?.length) g.children.forEach(l => allCats.push({ name: l.name, group: g.name }));
    else allCats.push({ name: g.name, group: g.name });
  });

  return (
    <span style={{ position: 'relative' }} ref={ref}>
      <button
        className={'cat-chip' + (value ? '' : ' unknown')}
        onClick={(e) => { e.stopPropagation(); setOpen(o => !o); }}
        style={{ cursor: 'pointer', whiteSpace: 'nowrap' }}>
        {value || '? unknown'} <span style={{ opacity: 0.55, marginLeft: 3 }}>▾</span>
      </button>
      {open && (
        <div style={{
          position: 'absolute', top: 'calc(100% + 4px)', right: 0, zIndex: 50,
          minWidth: 180, background: 'var(--paper)', border: '1.5px solid var(--ink)',
          borderRadius: 6, boxShadow: '2px 2px 0 var(--ink)', padding: 6,
          fontFamily: 'var(--hand)', fontSize: 13,
        }}>
          <div className="muted" style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: 0.06, padding: '4px 6px' }}>Assign to</div>
          <div style={{ maxHeight: 200, overflowY: 'auto' }}>
            {allCats.map((c, i) => (
              <div key={i}
                onClick={() => { onChange(c.name); setOpen(false); }}
                style={{ padding: '4px 8px', cursor: 'pointer', borderRadius: 3, display: 'flex', justifyContent: 'space-between' }}
                onMouseDown={(e) => e.currentTarget.style.background = 'var(--paper-2)'}
                onMouseEnter={(e) => e.currentTarget.style.background = 'var(--paper-2)'}
                onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}>
                <span>{c.name}</span>
                <span className="muted" style={{ fontSize: 10 }}>{c.group !== c.name ? c.group : ''}</span>
              </div>
            ))}
          </div>
          <div style={{ borderTop: '1px dashed var(--rule-soft)', marginTop: 4, padding: '6px 6px 2px', fontSize: 10, color: 'var(--ink-3)' }}>
            Need a new bucket? Create it in <b>Plan</b>.
          </div>
        </div>
      )}
    </span>
  );
}

// Legacy aliases so old refs don't break
Object.assign(window, {
  ExpensesPhone, ExpensesDesktop, CategoryChip,
  ExpUploadPhone: ExpensesPhone, ExpManagePhone: ExpensesPhone,
  ExpUploadDesktop: ExpensesDesktop, ExpManageDesktop: ExpensesDesktop,
});
