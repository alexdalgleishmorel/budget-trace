// Hi-fi Expenses — dropzone, needs-review queue, all-txns table, chip popover.

function HFCategoryChip({ value, onChange }) {
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

  const unknown = !value;
  return (
    <span style={{ position: 'relative', display: 'inline-flex' }} ref={ref}>
      <button
        onClick={(e) => { e.stopPropagation(); setOpen(o => !o); }}
        style={{
          display: 'inline-flex', alignItems: 'center', gap: 6,
          padding: '4px 10px 4px 8px',
          borderRadius: 999,
          border: '1px solid ' + (unknown ? 'var(--warn)' : 'var(--rule-strong)'),
          background: unknown ? 'var(--warn-bg)' : 'var(--surface-2)',
          color: unknown ? 'var(--warn)' : 'var(--ink-2)',
          cursor: 'pointer',
          font: 'inherit', fontSize: 12, fontWeight: 500,
          whiteSpace: 'nowrap',
        }}>
        {unknown
          ? <Icon name="alert" size={12} stroke={2} />
          : <CatIcon name={value} size={13} stroke={1.8} />}
        <span>{value || 'Needs category'}</span>
        <Icon name="chevron-down" size={12} stroke={2} style={{ opacity: 0.55 }} />
      </button>
      {open && (
        <div
          onClick={(e) => e.stopPropagation()}
          className="glass-strong"
          style={{
            position: 'absolute', top: 'calc(100% + 6px)', right: 0, zIndex: 60,
            minWidth: 220,
            background: 'var(--surface)',
            borderRadius: 14,
            padding: 6,
            boxShadow: 'var(--shadow-pop)',
          }}>
          <div className="label" style={{ padding: '8px 10px 6px' }}>Assign to</div>
          <div style={{ maxHeight: 240, overflowY: 'auto' }}>
            {allCats.map((c, i) => (
              <div key={i}
                onClick={() => { onChange(c.name); setOpen(false); }}
                style={{
                  padding: '7px 10px',
                  cursor: 'pointer',
                  borderRadius: 8,
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                  gap: 10,
                  fontSize: 13,
                }}
                onMouseEnter={(e) => e.currentTarget.style.background = 'var(--surface-2)'}
                onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                  <CatIcon name={c.name} size={14} stroke={1.7} />
                  {c.name}
                </span>
                {c.group !== c.name && (
                  <span style={{ fontSize: 11, color: 'var(--ink-4)' }}>{c.group}</span>
                )}
              </div>
            ))}
          </div>
          <div style={{
            borderTop: '1px solid var(--rule)',
            margin: '6px 4px 0', padding: '8px 6px 4px',
            fontSize: 11.5, color: 'var(--ink-4)',
          }}>
            Need a new bucket? Create it in <b style={{ color: 'var(--ink-2)' }}>Plan</b>.
          </div>
        </div>
      )}
    </span>
  );
}

function Dropzone({ compact = false }) {
  return (
    <div style={{
      border: '1.5px dashed var(--rule-strong)',
      borderRadius: 16,
      background: 'var(--surface-2)',
      padding: compact ? '20px 16px' : '28px 20px',
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6,
      textAlign: 'center',
      cursor: 'pointer',
      transition: 'border-color var(--dur) var(--ease), background var(--dur) var(--ease)',
    }}
    onMouseEnter={(e) => { e.currentTarget.style.borderColor = 'var(--ink-3)'; }}
    onMouseLeave={(e) => { e.currentTarget.style.borderColor = 'var(--rule-strong)'; }}>
      <div style={{
        width: 44, height: 44, borderRadius: 14,
        background: 'var(--surface)',
        border: '1px solid var(--rule-strong)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: 'var(--ink-2)',
      }}>
        <Icon name="upload" size={20} stroke={1.8} />
      </div>
      <div style={{ fontSize: 14, fontWeight: 500, marginTop: 4 }}>
        Drop a statement
      </div>
      <div style={{ fontSize: 12, color: 'var(--ink-4)' }}>
        CSV, OFX, or paste &middot; Chase &middot; Amex &middot; Wells Fargo
      </div>
    </div>
  );
}

/* ========== Mobile ========== */

function ExpensesPhoneHF({ txns, onAssign, onNav }) {
  const unknown = txns.filter(t => !t.cat);
  const known = txns.filter(t => t.cat);
  const total = txns.reduce((s, t) => s + t.amount, 0);

  return (
    <>
      <StatusBar />
      <MobileHeaderHF
        title="Expenses"
        right={
          <button className="btn ghost" style={{ padding: '6px 10px', fontSize: 12 }}>
            Mar 2025
            <Icon name="chevron-down" size={13} stroke={2} style={{ marginLeft: 2 }} />
          </button>
        }
      />

      <div style={{ padding: '0 18px 10px' }}>
        <div className="label">This cycle</div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 2 }}>
          <div className="num" style={{ fontSize: 28, fontWeight: 500, letterSpacing: -0.02 }}>
            {fmtMoney(total)}
          </div>
          <div style={{ fontSize: 13, color: 'var(--ink-3)' }}>
            {txns.length} transactions
          </div>
        </div>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '6px 18px 18px' }}>
        <Dropzone compact />

        {unknown.length > 0 && (
          <div style={{ marginTop: 18 }}>
            <div style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '0 2px 8px',
            }}>
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                <Icon name="alert" size={14} stroke={2} style={{ color: 'var(--warn)' }} />
                <div className="display" style={{ fontSize: 15 }}>Needs review</div>
              </div>
              <span className="num" style={{ fontSize: 12, color: 'var(--ink-4)' }}>
                {unknown.length} of {txns.length}
              </span>
            </div>
            <div className="card" style={{ overflow: 'hidden' }}>
              {unknown.map((t, i) => (
                <div key={i} style={{
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                  padding: '12px 14px',
                  borderTop: i === 0 ? 'none' : '1px solid var(--rule)',
                  gap: 10,
                }}>
                  <div style={{ minWidth: 0, flex: 1 }}>
                    <div style={{
                      fontSize: 13.5, fontWeight: 500,
                      whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                    }}>{t.merchant}</div>
                    <div className="num" style={{ fontSize: 11, color: 'var(--ink-4)', marginTop: 2 }}>
                      {t.date} &middot; {fmtMoney(t.amount)}
                    </div>
                  </div>
                  <HFCategoryChip value={null} onChange={(cat) => onAssign(t, cat)} />
                </div>
              ))}
            </div>
          </div>
        )}

        <div style={{ marginTop: 20 }}>
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '0 2px 8px',
          }}>
            <div className="display" style={{ fontSize: 15 }}>All transactions</div>
            <span className="num" style={{ fontSize: 12, color: 'var(--ink-4)' }}>
              {known.length}
            </span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 10 }}>
            <div style={{ display: 'flex', gap: 8 }}>
              <div style={{ position: 'relative', flex: 1 }}>
                <span style={{
                  position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)',
                  color: 'var(--ink-4)', display: 'inline-flex',
                }}>
                  <Icon name="search" size={15} stroke={1.8} />
                </span>
                <input className="input" placeholder="Search merchant"
                  style={{ paddingLeft: 32, fontSize: 13 }} />
              </div>
              <button className="btn icon">
                <Icon name="filter" size={17} stroke={1.8} />
              </button>
            </div>
            <select className="input" style={{ fontSize: 13, padding: '10px 12px' }}>
              <option>All categories</option>
              {BUDGET.children.filter(c => !c.isUnknown).map((c, i) => (
                <option key={i}>{c.name}</option>
              ))}
            </select>
          </div>
          <div className="card" style={{ overflow: 'hidden' }}>
            {known.map((t, i) => (
              <div key={i} style={{
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                padding: '11px 14px',
                borderTop: i === 0 ? 'none' : '1px solid var(--rule)',
                gap: 10,
              }}>
                <div style={{ minWidth: 0, flex: 1 }}>
                  <div style={{
                    fontSize: 13.5, fontWeight: 500,
                    whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                  }}>{t.merchant}</div>
                  <div className="num" style={{ fontSize: 11, color: 'var(--ink-4)', marginTop: 2 }}>
                    {t.date}
                  </div>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 5 }}>
                  <span className="num" style={{ fontSize: 14, fontWeight: 500 }}>
                    {fmtMoney(t.amount)}
                  </span>
                  <HFCategoryChip value={t.cat} onChange={(cat) => onAssign(t, cat)} />
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <BottomTabsHF current="expenses" onNav={onNav} />
      <HomeIndicator />
    </>
  );
}

/* ========== Desktop ========== */

function ExpensesDesktopHF({ txns, onAssign, onNav }) {
  const unknown = txns.filter(t => !t.cat);
  const total = txns.reduce((s, t) => s + t.amount, 0);

  return (
    <>
      <WindowTitleBar title="Budget Trace — Expenses" />
      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        <DesktopSideNav current="expenses" onNav={onNav} />
        <main style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
          {/* Top strip */}
          <div style={{
            padding: '22px 28px 18px',
            display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
            borderBottom: '1px solid var(--rule)',
          }}>
            <div>
              <div className="label">Expenses</div>
              <div className="display" style={{ fontSize: 30, letterSpacing: -0.025, marginTop: 4 }}>
                March 2025
              </div>
              <div style={{ fontSize: 13, color: 'var(--ink-3)', marginTop: 4 }}>
                Real transactions from your linked statements.
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'flex-end', gap: 28 }}>
              <div style={{ textAlign: 'right' }}>
                <div className="label">Unknown</div>
                <div className="num" style={{
                  fontSize: 18, fontWeight: 500, marginTop: 2, color: 'var(--warn)',
                }}>
                  {unknown.length}
                </div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div className="label">Total spent</div>
                <div className="num" style={{
                  fontSize: 30, fontWeight: 500, letterSpacing: -0.02, marginTop: 2,
                }}>
                  {fmtMoney(total)}
                </div>
              </div>
            </div>
          </div>

          {/* Body: upload/review rail + main table */}
          <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
            <aside style={{
              width: 340, flexShrink: 0,
              borderRight: '1px solid var(--rule)',
              padding: '20px 22px',
              display: 'flex', flexDirection: 'column', gap: 18, minHeight: 0,
            }}>
              <div>
                <div className="label" style={{ marginBottom: 8 }}>Import</div>
                <Dropzone />
              </div>

              <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
                <div style={{
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                  marginBottom: 8,
                }}>
                  <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                    <Icon name="alert" size={14} stroke={2} style={{ color: 'var(--warn)' }} />
                    <div className="display" style={{ fontSize: 15 }}>Needs review</div>
                  </div>
                  <span className="num" style={{ fontSize: 12, color: 'var(--ink-4)' }}>
                    {unknown.length} unknown
                  </span>
                </div>

                <div className="card" style={{ flex: 1, overflowY: 'auto', minHeight: 0 }}>
                  {unknown.length === 0 ? (
                    <div style={{ padding: 20, fontSize: 12.5, color: 'var(--ink-4)', textAlign: 'center' }}>
                      Nothing to review. Nice.
                    </div>
                  ) : unknown.map((t, i) => (
                    <div key={i} style={{
                      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                      padding: '11px 14px',
                      borderTop: i === 0 ? 'none' : '1px solid var(--rule)',
                      gap: 10,
                    }}>
                      <div style={{ minWidth: 0, flex: 1 }}>
                        <div style={{
                          fontSize: 13, fontWeight: 500,
                          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                        }}>{t.merchant}</div>
                        <div className="num" style={{ fontSize: 11, color: 'var(--ink-4)', marginTop: 2 }}>
                          {t.date} &middot; {fmtMoney(t.amount)}
                        </div>
                      </div>
                      <HFCategoryChip value={null} onChange={(cat) => onAssign(t, cat)} />
                    </div>
                  ))}
                </div>
              </div>
            </aside>

            {/* Main table */}
            <section style={{ flex: 1, padding: '20px 24px', display: 'flex', flexDirection: 'column', minWidth: 0, minHeight: 0 }}>
              <div style={{ marginBottom: 12 }}>
                <div className="display" style={{ fontSize: 18, marginBottom: 10 }}>All transactions</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <div style={{ position: 'relative' }}>
                    <span style={{
                      position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)',
                      color: 'var(--ink-4)', display: 'inline-flex',
                    }}>
                      <Icon name="search" size={15} stroke={1.8} />
                    </span>
                    <input className="input" placeholder="Search merchant"
                      style={{ fontSize: 13, padding: '8px 10px 8px 32px' }} />
                  </div>
                  <select className="input" style={{ fontSize: 13, padding: '8px 10px' }}>
                    <option>All categories</option>
                    {BUDGET.children.filter(c => !c.isUnknown).map((c, i) => (
                      <option key={i}>{c.name}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="card" style={{ flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
                <div style={{
                  display: 'grid',
                  gridTemplateColumns: '88px 1fr 180px 120px',
                  gap: 14, padding: '11px 18px',
                  borderBottom: '1px solid var(--rule)',
                }}>
                  <span className="label">Date</span>
                  <span className="label">Merchant</span>
                  <span className="label">Category</span>
                  <span className="label" style={{ textAlign: 'right' }}>Amount</span>
                </div>
                <div style={{ flex: 1, overflowY: 'auto' }}>
                  {txns.map((t, i) => (
                    <div key={i} style={{
                      display: 'grid',
                      gridTemplateColumns: '88px 1fr 180px 120px',
                      gap: 14, padding: '11px 18px',
                      borderBottom: '1px solid var(--rule-soft)',
                      alignItems: 'center',
                    }}>
                      <span className="num" style={{ fontSize: 12.5, color: 'var(--ink-3)' }}>{t.date}</span>
                      <span style={{ fontSize: 13.5, fontWeight: 500 }}>{t.merchant}</span>
                      <HFCategoryChip value={t.cat} onChange={(cat) => onAssign(t, cat)} />
                      <span className="num" style={{
                        textAlign: 'right', fontSize: 14, fontWeight: 500,
                      }}>{fmtMoney(t.amount)}</span>
                    </div>
                  ))}
                </div>
              </div>
            </section>
          </div>
        </main>
      </div>
    </>
  );
}

Object.assign(window, { ExpensesPhoneHF, ExpensesDesktopHF, HFCategoryChip, Dropzone });
