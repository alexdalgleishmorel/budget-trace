// Upload + categorization review screens — 3 variations

function UploadA({ txns, setTxns }) {
  // Variation A: Phone — drop zone + queue of unknowns to triage
  const unknown = txns.filter(t => !t.cat);
  return (
    <PhoneFrame>
      <AppHeader title="UPLOAD"
        left={<button className="icon-btn">←</button>}
        right={<button className="pill">Mar ‘26</button>} />
      <div className="dropzone" style={{ marginBottom: 12 }}>
        <div className="display" style={{ fontSize: 22, lineHeight: 1 }}>↓</div>
        <div style={{ marginTop: 4 }}>Drop your bank CSV</div>
        <div className="muted" style={{ fontSize: 11, marginTop: 2 }}>or tap to browse</div>
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '0 4px 6px' }}>
        <span className="display" style={{ fontSize: 18 }}>Needs review</span>
        <span className="mono muted">{unknown.length} of {txns.length}</span>
      </div>
      <div style={{ flex: 1, overflowY: 'auto', border: '1.2px solid var(--rule-soft)', borderRadius: 6, background: 'var(--paper)' }}>
        {unknown.map((t, i) => (
          <div className="txn-row" key={i}>
            <div>
              <div className="merchant">{t.merchant}</div>
              <div className="meta">{t.date} · {fmtMoney(t.amount)}</div>
            </div>
            <button className="cat-chip unknown">? assign</button>
          </div>
        ))}
      </div>
    </PhoneFrame>
  );
}

function UploadB({ txns }) {
  // Variation B: Phone — "Inbox" pattern, all txns w/ inferred chips
  return (
    <PhoneFrame>
      <AppHeader title="EXPENSES"
        left={<button className="icon-btn">⌂</button>}
        right={<button className="pill">+ Upload</button>} />
      <div className="sticky" style={{ marginBottom: 8, alignSelf: 'flex-start' }}>
        3 unknowns — tap a chip to fix.
      </div>
      <div style={{ flex: 1, overflowY: 'auto', borderTop: '1.2px dashed var(--rule-soft)' }}>
        {txns.map((t, i) => (
          <div className="txn-row" key={i}>
            <div>
              <div className="merchant">{t.merchant}</div>
              <div className="meta">{t.date}</div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
              <span className="amt">{fmtMoney(t.amount)}</span>
              <span className={'cat-chip' + (t.cat ? '' : ' unknown')}>
                {t.cat || '? unknown'}
              </span>
            </div>
          </div>
        ))}
      </div>
    </PhoneFrame>
  );
}

function UploadC({ txns }) {
  // Variation C: Desktop — split: dropzone + summary by category
  const byCat = {};
  txns.forEach(t => {
    const k = t.cat || 'Unknown';
    byCat[k] = (byCat[k] || 0) + t.amount;
  });
  const rows = Object.entries(byCat).sort((a,b) => b[1] - a[1]);
  return (
    <div className="desktop" style={{ height: 480 }}>
      <div className="titlebar">
        <span className="dot" /><span className="dot" /><span className="dot" />
        <span style={{ marginLeft: 12, fontFamily: 'var(--hand)', fontSize: 13 }}>upload · march 2026</span>
      </div>
      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        <section style={{ flex: 1, padding: 18, borderRight: '1.5px solid var(--rule)' }}>
          <div className="display" style={{ fontSize: 26, marginBottom: 4 }}>Upload expenses</div>
          <div className="muted" style={{ fontSize: 12, marginBottom: 14 }}>CSV, OFX, or paste from clipboard</div>
          <div className="dropzone" style={{ marginBottom: 14 }}>
            <div className="display" style={{ fontSize: 28, lineHeight: 1 }}>↓</div>
            <div style={{ marginTop: 6 }}>Drop file or paste here</div>
            <div className="muted" style={{ fontSize: 11, marginTop: 4 }}>chase, amex, wells fargo, mint export…</div>
          </div>
          <div style={{ fontFamily: 'var(--hand)', fontSize: 13, marginBottom: 6 }}>Last upload</div>
          <div className="mono muted" style={{ fontSize: 11 }}>chase-statement-mar.csv · {txns.length} rows · 3 unknown</div>
        </section>
        <section style={{ flex: 1, padding: 18, display: 'flex', flexDirection: 'column' }}>
          <div className="display" style={{ fontSize: 22, marginBottom: 8 }}>Auto-categorized</div>
          <div style={{ flex: 1, overflowY: 'auto' }}>
            {rows.map(([cat, sum], i) => {
              const isUnknown = cat === 'Unknown';
              return (
                <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 6px', borderBottom: '1px dashed var(--rule-soft)' }}>
                  <span className={'cat-chip' + (isUnknown ? ' unknown' : '')} style={{ minWidth: 110, textAlign: 'center' }}>{cat}</span>
                  <div style={{ flex: 1, height: 8, background: 'var(--paper-2)', borderRadius: 4, position: 'relative', overflow: 'hidden' }}>
                    <div style={{ position: 'absolute', inset: 0, width: Math.min(100, sum / 1500 * 100) + '%', background: isUnknown ? 'var(--accent)' : 'var(--ink-2)' }} />
                  </div>
                  <span className="mono">{fmtMoney(sum)}</span>
                </div>
              );
            })}
          </div>
          <button className="btn-sketch solid" style={{ marginTop: 12, alignSelf: 'flex-end' }}>Review unknowns →</button>
        </section>
      </div>
    </div>
  );
}

Object.assign(window, { UploadA, UploadB, UploadC });
