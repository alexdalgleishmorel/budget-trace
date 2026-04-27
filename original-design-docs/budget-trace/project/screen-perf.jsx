// Performance + Summary screen wireframes — 3 variations each

// ── Sketchy chart primitive ─────────────────────────────
function PerfChart({ w, h, label, daysSpend, dailyBudget, mode = 'cumulative', color = 'var(--ink)' }) {
  // mode: cumulative | burndown | bars
  const PAD_L = 22, PAD_R = 10, PAD_T = 14, PAD_B = 18;
  const innerW = w - PAD_L - PAD_R;
  const innerH = h - PAD_T - PAD_B;
  const days = daysSpend.length;
  const total = days * dailyBudget;

  // cumulative actual
  const cum = [];
  let acc = 0;
  daysSpend.forEach(d => { acc += d; cum.push(acc); });

  // ideal line (straight from 0 to total)
  const idealMax = total;
  const yMax = Math.max(idealMax, ...cum) * 1.05;

  const xAt = i => PAD_L + (i / (days - 1)) * innerW;
  const yAt = v => PAD_T + (1 - v / yMax) * innerH;

  // path of cumulative line
  let path = '';
  cum.forEach((v, i) => {
    const cmd = i === 0 ? 'M' : 'L';
    // jitter for sketchy feel
    const jx = (Math.sin(i * 1.7) * 0.6);
    const jy = (Math.cos(i * 2.1) * 0.5);
    path += `${cmd}${xAt(i).toFixed(1) + jx} ${yAt(v).toFixed(1) + jy} `;
  });

  // ideal dotted line
  const idealStart = `${PAD_L},${yAt(0)}`;
  const idealEnd = `${PAD_L + innerW},${yAt(total)}`;

  // mark over/under: split the path color where cum > ideal at that day
  // simpler: draw cumulative as one path, then a red overlay segment for last point if over
  const lastOver = cum[cum.length - 1] > total;

  return (
    <div className="chart-card" style={{ width: w, marginBottom: 8 }}>
      <div className="ch-title">{label}</div>
      <svg width={w - 20} height={h} viewBox={`0 0 ${w - 20} ${h}`} style={{ display: 'block' }}>
        {/* baseline grid */}
        <line x1={PAD_L} y1={PAD_T + innerH} x2={PAD_L + innerW} y2={PAD_T + innerH}
          stroke="var(--rule-soft)" strokeWidth="1" />
        <line x1={PAD_L} y1={PAD_T} x2={PAD_L} y2={PAD_T + innerH}
          stroke="var(--rule-soft)" strokeWidth="1" />
        {/* ideal dotted */}
        <line x1={PAD_L} y1={yAt(0)} x2={PAD_L + innerW} y2={yAt(total)}
          stroke="var(--ink-3)" strokeWidth="1" strokeDasharray="2 3" />
        {/* actual path */}
        <path d={path} fill="none" stroke={lastOver ? 'var(--accent)' : 'var(--good)'} strokeWidth="1.8"
          strokeLinecap="round" strokeLinejoin="round" />
        {/* end dot */}
        <circle cx={xAt(days - 1)} cy={yAt(cum[cum.length - 1])} r="3"
          fill={lastOver ? 'var(--accent)' : 'var(--good)'} />
        {/* y labels */}
        <text x={4} y={yAt(0) + 3} fontSize="9" fontFamily="var(--mono)" fill="var(--ink-3)">$0</text>
        <text x={4} y={yAt(yMax) + 8} fontSize="9" fontFamily="var(--mono)" fill="var(--ink-3)">{fmtMoney(yMax).replace('$','$')}</text>
        {/* x labels */}
        <text x={PAD_L} y={h - 4} fontSize="9" fontFamily="var(--mono)" fill="var(--ink-3)">1</text>
        <text x={PAD_L + innerW - 8} y={h - 4} fontSize="9" fontFamily="var(--mono)" fill="var(--ink-3)">{days}</text>
        {/* over chip end */}
        {lastOver && (
          <text x={xAt(days - 1) - 4} y={yAt(cum[cum.length - 1]) - 6} fontSize="9" fontFamily="var(--mono)"
            textAnchor="end" fill="var(--accent)">+{fmtMoney(cum[cum.length - 1] - total)}</text>
        )}
      </svg>
    </div>
  );
}

// build fake daily spend curves
function dailySpend(total, daysIn, jitter = 0.4, overshoot = false) {
  const days = 31;
  const ideal = total / days;
  const arr = [];
  for (let i = 0; i < days; i++) {
    if (i >= daysIn) { arr.push(0); continue; }
    let v = ideal * (1 + (Math.sin(i * 0.7) * jitter));
    if (overshoot && i > daysIn * 0.6) v *= 1.4;
    arr.push(Math.max(0, v));
  }
  return arr;
}

// ── A: phone — stack of cumulative charts (matches sketch) ──
function PerfA() {
  const cats = [
    { name: 'House', amt: 1800, days: dailySpend(1820, 31, 0.1, true) },
    { name: 'Living', amt: 1450, days: dailySpend(1380, 31, 0.5, false) },
    { name: 'Grocery', amt: 540, days: dailySpend(612, 31, 0.6, true) },
  ];
  return (
    <PhoneFrame>
      <AppHeader title="BUDGET PERFORMANCE"
        left={<button className="icon-btn">←</button>}
        right={<button className="pill">Upload</button>} />
      <div style={{ flex: 1, overflowY: 'auto', padding: '0 4px' }}>
        {cats.map((c, i) => (
          <PerfChart key={i} w={290} h={86} label={c.name.toUpperCase()}
            daysSpend={c.days} dailyBudget={c.amt / 31} />
        ))}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '6px 8px 0', borderTop: '1.2px dashed var(--rule-soft)' }}>
        <button className="icon-btn">←</button>
        <span className="display" style={{ fontSize: 16 }}>Mar 1 – Mar 31, 2026</span>
        <button className="icon-btn">→</button>
      </div>
    </PhoneFrame>
  );
}

// ── B: phone — single chart with toggle chips ──
function PerfB() {
  const data = dailySpend(540, 31, 0.6, true);
  return (
    <PhoneFrame>
      <AppHeader title="PERFORMANCE"
        left={<button className="icon-btn">←</button>}
        right={<button className="pill">Mar ‘26</button>} />
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', padding: '0 4px 8px' }}>
        {['All', 'House', 'Living', 'Grocery', 'Fun', 'Gas'].map((c, i) => (
          <span key={i} className="cat-chip" style={{
            background: i === 3 ? 'var(--ink)' : 'var(--paper)',
            color: i === 3 ? 'var(--paper)' : 'var(--ink)',
            fontFamily: 'var(--hand)', fontSize: 12,
          }}>{c}</span>
        ))}
      </div>
      <div style={{ flex: 1 }}>
        <PerfChart w={296} h={220} label="GROCERY · cumulative spend" daysSpend={data} dailyBudget={540/31} />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, padding: '8px 6px' }}>
          <div className="sketch-box" style={{ padding: '8px 10px' }}>
            <div className="label muted" style={{ fontSize: 10 }}>SPENT TO DATE</div>
            <div className="display" style={{ fontSize: 22 }}>{fmtMoney(612)}</div>
          </div>
          <div className="sketch-box" style={{ padding: '8px 10px' }}>
            <div className="label muted" style={{ fontSize: 10 }}>OVER BUDGET</div>
            <div className="display" style={{ fontSize: 22, color: 'var(--accent)' }}>+{fmtMoney(72)}</div>
          </div>
        </div>
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '6px 8px 0', borderTop: '1.2px dashed var(--rule-soft)' }}>
        <button className="icon-btn">←</button>
        <span className="display" style={{ fontSize: 16 }}>Mar 1 – Mar 31</span>
        <button className="icon-btn">→</button>
      </div>
    </PhoneFrame>
  );
}

// ── C: desktop — grid of small multiples ──
function PerfC() {
  const cats = [
    { name: 'House', amt: 1800, actual: 1820, jitter: 0.1, over: true },
    { name: 'Living', amt: 1450, actual: 1380, jitter: 0.5, over: false },
    { name: 'Savings', amt: 1500, actual: 1500, jitter: 0.2, over: false },
    { name: 'Grocery', amt: 540, actual: 612, jitter: 0.6, over: true },
    { name: 'Gas', amt: 220, actual: 198, jitter: 0.4, over: false },
    { name: 'Fun', amt: 200, actual: 142, jitter: 0.5, over: false },
  ];
  return (
    <div className="desktop" style={{ height: 540 }}>
      <div className="titlebar">
        <span className="dot" /><span className="dot" /><span className="dot" />
        <span style={{ marginLeft: 12, fontFamily: 'var(--hand)', fontSize: 13 }}>performance · march 2026</span>
      </div>
      <div style={{ flex: 1, padding: 18, overflowY: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 14 }}>
          <div>
            <div className="display" style={{ fontSize: 28 }}>Budget performance</div>
            <div className="muted" style={{ fontSize: 12 }}>Mar 1 – Mar 31, 2026 · 18 days in</div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <button className="btn-sketch">← Feb</button>
            <button className="btn-sketch">Mar →</button>
          </div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
          {cats.map((c, i) => (
            <PerfChart key={i} w={250} h={130} label={c.name.toUpperCase()}
              daysSpend={dailySpend(c.actual, 31, c.jitter, c.over)} dailyBudget={c.amt/31} />
          ))}
        </div>
      </div>
    </div>
  );
}

// ── Period summary screens ──
function SummaryA() {
  return (
    <PhoneFrame>
      <AppHeader title="MARCH 2026"
        left={<button className="icon-btn">⌂</button>}
        right={<button className="pill">…</button>} />
      <div style={{ textAlign: 'center', padding: '8px 0 14px' }}>
        <div className="label muted" style={{ fontSize: 11 }}>NET THIS MONTH</div>
        <div className="display" style={{ fontSize: 44, lineHeight: 1, color: 'var(--good)' }}>+{fmtMoney(380)}</div>
        <div className="muted" style={{ fontSize: 12 }}>{fmtMoney(5400)} in · {fmtMoney(5020)} out</div>
      </div>
      <div className="sketch-box" style={{ padding: 10, marginBottom: 8 }}>
        <div className="label muted" style={{ fontSize: 10 }}>SAVED</div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span className="display" style={{ fontSize: 26 }}>{fmtMoney(1500)}</span>
          <span className="mono">on track</span>
        </div>
        <div style={{ height: 6, background: 'var(--paper-2)', borderRadius: 3, marginTop: 6, overflow: 'hidden' }}>
          <div style={{ width: '100%', height: '100%', background: 'var(--good)' }} />
        </div>
      </div>
      <div style={{ flex: 1, overflowY: 'auto' }}>
        {BUDGET.children.filter(c => !c.isUnknown).map((c, i) => {
          const pct = Math.min(150, (c.actual / c.amount) * 100);
          const over = c.actual > c.amount;
          return (
            <div key={i} style={{ padding: '8px 6px', borderBottom: '1px dashed var(--rule-soft)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span style={{ fontWeight: 700 }}>{c.name}</span>
                <span className="mono">{fmtMoney(c.actual)} / {fmtMoney(c.amount)}</span>
              </div>
              <div style={{ height: 5, background: 'var(--paper-2)', borderRadius: 3, marginTop: 4, overflow: 'hidden', position: 'relative' }}>
                <div style={{ width: Math.min(100, pct) + '%', height: '100%', background: over ? 'var(--accent)' : 'var(--good)' }} />
                {over && <div style={{ position: 'absolute', right: 0, top: 0, height: '100%', width: 2, background: 'var(--ink)' }} />}
              </div>
            </div>
          );
        })}
      </div>
    </PhoneFrame>
  );
}

function SummaryB() {
  // dashboard — KPI tiles
  return (
    <PhoneFrame>
      <AppHeader title="MARCH 2026"
        left={<button className="icon-btn">⌂</button>}
        right={<button className="pill">Edit</button>} />
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, padding: '0 4px 8px' }}>
        <div className="sketch-box" style={{ padding: 10 }}>
          <div className="label muted" style={{ fontSize: 10 }}>INCOME</div>
          <div className="display" style={{ fontSize: 22 }}>{fmtMoney(5400)}</div>
        </div>
        <div className="sketch-box" style={{ padding: 10 }}>
          <div className="label muted" style={{ fontSize: 10 }}>SPENT</div>
          <div className="display" style={{ fontSize: 22 }}>{fmtMoney(5020)}</div>
        </div>
        <div className="sketch-box" style={{ padding: 10, background: 'rgba(47,122,77,0.08)' }}>
          <div className="label muted" style={{ fontSize: 10 }}>SAVED</div>
          <div className="display" style={{ fontSize: 22, color: 'var(--good)' }}>{fmtMoney(1500)}</div>
        </div>
        <div className="sketch-box" style={{ padding: 10, background: 'rgba(217,79,42,0.08)' }}>
          <div className="label muted" style={{ fontSize: 10 }}>OVER IN</div>
          <div className="display" style={{ fontSize: 22, color: 'var(--accent)' }}>2 cats</div>
        </div>
      </div>
      <div style={{ padding: '4px 6px' }}>
        <div className="display" style={{ fontSize: 16, marginBottom: 6 }}>Where it went</div>
        <div style={{ display: 'flex', height: 18, border: '1.2px solid var(--ink)', borderRadius: 3, overflow: 'hidden' }}>
          {BUDGET.children.filter(c => c.actual > 0).map((c, i) => {
            const total = BUDGET.children.reduce((s,c) => s + c.actual, 0);
            const pct = c.actual / total * 100;
            return (
              <div key={i} style={{ width: pct + '%', background: catColor(c), borderRight: i < 3 ? '1.2px solid var(--ink)' : 'none' }} />
            );
          })}
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 8 }}>
          {BUDGET.children.filter(c => c.actual > 0).map((c, i) => (
            <span key={i} style={{ fontSize: 11, fontFamily: 'var(--hand)', display: 'flex', alignItems: 'center', gap: 4 }}>
              <span style={{ width: 9, height: 9, background: catColor(c), border: '1px solid var(--ink)', display: 'inline-block' }} />
              {c.name} {fmtMoney(c.actual)}
            </span>
          ))}
        </div>
      </div>
      <div style={{ flex: 1, padding: '12px 6px 0' }}>
        <div className="display" style={{ fontSize: 16, marginBottom: 4 }}>This week</div>
        <div className="txn-row"><div><div className="merchant">Costco Whse</div><div className="meta">Mar 24 · Grocery</div></div><span className="amt">{fmtMoney(212)}</span></div>
        <div className="txn-row"><div><div className="merchant">Amazon Mktp</div><div className="meta">Mar 22 · ?unknown</div></div><span className="amt">{fmtMoney(38)}</span></div>
        <div className="txn-row"><div><div className="merchant">AMC Theaters</div><div className="meta">Mar 27 · Fun</div></div><span className="amt">{fmtMoney(36)}</span></div>
      </div>
    </PhoneFrame>
  );
}

function SummaryC() {
  // Desktop overview
  return (
    <div className="desktop" style={{ height: 540 }}>
      <div className="titlebar">
        <span className="dot" /><span className="dot" /><span className="dot" />
        <span style={{ marginLeft: 12, fontFamily: 'var(--hand)', fontSize: 13 }}>summary · march 2026</span>
      </div>
      <div style={{ display: 'flex', flex: 1 }}>
        <section style={{ flex: 2, padding: 22, borderRight: '1.5px solid var(--rule)' }}>
          <div className="display" style={{ fontSize: 30 }}>March 2026</div>
          <div className="muted" style={{ fontSize: 12, marginBottom: 18 }}>Mar 1 – Mar 31 · 18 days in</div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 10, marginBottom: 16 }}>
            {[
              { l: 'INCOME', v: fmtMoney(5400), c: 'var(--ink)' },
              { l: 'SPENT', v: fmtMoney(5020), c: 'var(--ink)' },
              { l: 'SAVED', v: fmtMoney(1500), c: 'var(--good)' },
              { l: 'NET', v: '+' + fmtMoney(380), c: 'var(--good)' },
            ].map((k, i) => (
              <div key={i} className="sketch-box" style={{ padding: 12 }}>
                <div className="label muted" style={{ fontSize: 10 }}>{k.l}</div>
                <div className="display" style={{ fontSize: 26, color: k.c }}>{k.v}</div>
              </div>
            ))}
          </div>
          <div className="display" style={{ fontSize: 18, marginBottom: 8 }}>Categories</div>
          {BUDGET.children.filter(c => !c.isUnknown).map((c, i) => {
            const pct = Math.min(150, (c.actual / c.amount) * 100);
            const over = c.actual > c.amount;
            return (
              <div key={i} style={{ display: 'grid', gridTemplateColumns: '120px 1fr 140px', gap: 10, alignItems: 'center', padding: '6px 0' }}>
                <span style={{ fontFamily: 'var(--hand)', fontWeight: 700 }}>{c.name}</span>
                <div style={{ height: 8, background: 'var(--paper-2)', borderRadius: 3, position: 'relative', overflow: 'hidden' }}>
                  <div style={{ width: Math.min(100, pct) + '%', height: '100%', background: over ? 'var(--accent)' : 'var(--good)' }} />
                  <div style={{ position: 'absolute', left: '100%', top: -2, width: 1, height: 12, background: 'var(--ink-3)' }} />
                </div>
                <span className="mono" style={{ textAlign: 'right' }}>
                  {fmtMoney(c.actual)} / {fmtMoney(c.amount)}
                  {over ? <span className="over-chip" style={{ marginLeft: 6 }}>over</span> : null}
                </span>
              </div>
            );
          })}
        </section>
        <aside style={{ flex: 1, padding: 22 }}>
          <div className="display" style={{ fontSize: 20, marginBottom: 8 }}>Needs review</div>
          <div className="sticky" style={{ marginBottom: 12 }}>3 unknown txns · {fmtMoney(87)}</div>
          {makeTransactions().filter(t => !t.cat).map((t, i) => (
            <div key={i} className="txn-row">
              <div>
                <div className="merchant">{t.merchant}</div>
                <div className="meta">{t.date}</div>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
                <span className="amt">{fmtMoney(t.amount)}</span>
                <span className="cat-chip unknown">? assign</span>
              </div>
            </div>
          ))}
        </aside>
      </div>
    </div>
  );
}

Object.assign(window, { PerfA, PerfB, PerfC, SummaryA, SummaryB, SummaryC, PerfChart });
