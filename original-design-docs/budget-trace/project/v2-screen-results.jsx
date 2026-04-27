// v2 — Results (performance) + Summary screens
// Key change: chart shows ideal-MAX-per-day dashed ceiling + actual cumulative line.
// Actual line is segmented: green under dashed, yellow over dashed but under total,
// red over total budget.

function ResultsChart({ w, h, label, daysSpend, budgetTotal, daysInMonth = 31, daysIn = 31 }) {
  const PAD_L = 26, PAD_R = 14, PAD_T = 14, PAD_B = 20;
  const innerW = w - PAD_L - PAD_R;
  const innerH = h - PAD_T - PAD_B;

  // cumulative actual (only through daysIn)
  const cum = [];
  let acc = 0;
  for (let i = 0; i < daysInMonth; i++) {
    acc += (daysSpend[i] || 0);
    cum.push(acc);
  }
  const actualTotal = cum[daysIn - 1] || 0;

  // ideal ceiling = straight line from (0, 0) to (daysInMonth, budgetTotal)
  const idealAt = i => (i / (daysInMonth - 1)) * budgetTotal;

  const yMax = Math.max(budgetTotal * 1.1, actualTotal * 1.1, 1);

  const xAt = i => PAD_L + (i / (daysInMonth - 1)) * innerW;
  const yAt = v => PAD_T + (1 - v / yMax) * innerH;

  // Build segments: classify each point vs ideal and vs total
  // state: 'green' = cum < ideal, 'yellow' = cum > ideal && cum <= total, 'red' = cum > total
  function stateAt(v, i) {
    const ideal = idealAt(i);
    if (v > budgetTotal) return 'red';
    if (v > ideal) return 'yellow';
    return 'green';
  }
  const C = { green: 'var(--good)', yellow: '#d4a017', red: 'var(--accent)' };

  // segment into runs of same color
  const segs = [];
  let curColor = null;
  let curPts = [];
  for (let i = 0; i < daysIn; i++) {
    const v = cum[i];
    const st = stateAt(v, i);
    if (st !== curColor) {
      if (curPts.length) {
        // extend prev seg with first point of this segment to avoid gap
        curPts.push([xAt(i), yAt(v)]);
        segs.push({ color: curColor, pts: curPts });
      }
      curColor = st;
      curPts = i > 0 ? [[xAt(i-1), yAt(cum[i-1])], [xAt(i), yAt(v)]] : [[xAt(i), yAt(v)]];
    } else {
      curPts.push([xAt(i), yAt(v)]);
    }
  }
  if (curPts.length) segs.push({ color: curColor, pts: curPts });

  const pathFor = pts => pts.map((p, j) => (j === 0 ? 'M' : 'L') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');

  const overTotal = actualTotal > budgetTotal;
  const chipColor = C[stateAt(actualTotal, daysIn - 1)];

  return (
    <div className="chart-card" style={{ width: w, marginBottom: 8 }}>
      <div className="ch-title">{label}</div>
      <div className="ch-meta">{fmtMoney(actualTotal)} / {fmtMoney(budgetTotal)}</div>
      <svg width={w - 20} height={h} viewBox={`0 0 ${w - 20} ${h}`} style={{ display: 'block' }}>
        {/* axes */}
        <line x1={PAD_L} y1={PAD_T + innerH} x2={PAD_L + innerW} y2={PAD_T + innerH} stroke="var(--rule-soft)" strokeWidth="1" />
        <line x1={PAD_L} y1={PAD_T} x2={PAD_L} y2={PAD_T + innerH} stroke="var(--rule-soft)" strokeWidth="1" />

        {/* budget ceiling (solid faint) */}
        <line x1={PAD_L} y1={yAt(budgetTotal)} x2={PAD_L + innerW} y2={yAt(budgetTotal)}
          stroke="var(--ink-3)" strokeWidth="0.8" strokeDasharray="1 2" />
        <text x={PAD_L + innerW - 4} y={yAt(budgetTotal) - 3} fontSize="8" fontFamily="var(--mono)" textAnchor="end" fill="var(--ink-3)">
          budget {fmtMoney(budgetTotal)}
        </text>

        {/* ideal max-per-day dashed line */}
        <line x1={PAD_L} y1={yAt(0)} x2={PAD_L + innerW} y2={yAt(budgetTotal)}
          stroke="var(--ink)" strokeWidth="1.1" strokeDasharray="3 3" opacity="0.7" />

        {/* actual line segments colored by zone */}
        {segs.map((s, i) => (
          <path key={i} d={pathFor(s.pts)} fill="none" stroke={C[s.color]} strokeWidth="2"
            strokeLinecap="round" strokeLinejoin="round" />
        ))}
        {/* end dot */}
        <circle cx={xAt(daysIn - 1)} cy={yAt(actualTotal)} r="3" fill={chipColor} stroke="var(--ink)" strokeWidth="0.6" />

        {/* labels */}
        <text x={4} y={yAt(0) + 3} fontSize="9" fontFamily="var(--mono)" fill="var(--ink-3)">$0</text>
        <text x={PAD_L - 2} y={h - 4} fontSize="9" fontFamily="var(--mono)" fill="var(--ink-3)" textAnchor="end">1</text>
        <text x={PAD_L + innerW - 2} y={h - 4} fontSize="9" fontFamily="var(--mono)" fill="var(--ink-3)" textAnchor="end">{daysInMonth}</text>
      </svg>
    </div>
  );
}

function dailySpend(total, daysIn, jitter = 0.4, overshoot = false, daysInMonth = 31) {
  const ideal = total / daysInMonth;
  const arr = [];
  for (let i = 0; i < daysInMonth; i++) {
    if (i >= daysIn) { arr.push(0); continue; }
    let v = ideal * (1 + (Math.sin(i * 0.7) * jitter));
    if (overshoot && i > daysIn * 0.55) v *= 1.5;
    arr.push(Math.max(0, v));
  }
  return arr;
}

// Results mobile — stacked charts + unknown banner
function ResultsPhone({ onNav }) {
  const daysIn = 22;
  const cats = [
    { name: 'House', budget: 1800, days: dailySpend(1820, daysIn, 0.1, true) },
    { name: 'Living', budget: 1450, days: dailySpend(1380, daysIn, 0.5, false) },
    { name: 'Grocery', budget: 540, days: dailySpend(612, daysIn, 0.6, true) },
  ];
  return (
    <PhoneFrame>
      <AppHeaderHam current="results" onNav={onNav}
        right={<button className="icon-btn" title="Upload">↑</button>} />
      <div style={{ background: '#fff3a8', border: '1.2px solid var(--ink)', borderRadius: 6, padding: '8px 10px', marginBottom: 8, display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontFamily: 'var(--hand)', fontSize: 12 }}>
        <span>⚠ 3 expenses need a category</span>
        <span className="mono" style={{ textDecoration: 'underline' }}>Review →</span>
      </div>
      <div style={{ flex: 1, overflowY: 'auto', padding: '0 2px' }}>
        {cats.map((c, i) => (
          <ResultsChart key={i} w={290} h={100} label={c.name.toUpperCase()}
            daysSpend={c.days} budgetTotal={c.budget} daysIn={daysIn} />
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

// Results desktop — grid of small multiples
function ResultsDesktop({ onNav }) {
  const daysIn = 22;
  const cats = [
    { name: 'House', budget: 1800, actual: 1820, jitter: 0.1, over: true },
    { name: 'Living', budget: 1450, actual: 1380, jitter: 0.5, over: false },
    { name: 'Savings', budget: 1500, actual: 1500, jitter: 0.2, over: false },
    { name: 'Grocery', budget: 540, actual: 712, jitter: 0.6, over: true },
    { name: 'Gas', budget: 220, actual: 198, jitter: 0.4, over: false },
    { name: 'Fun', budget: 200, actual: 142, jitter: 0.5, over: false },
  ];
  return (
    <div className="desktop" style={{ height: 560 }}>
      <div className="titlebar">
        <span className="dot" /><span className="dot" /><span className="dot" />
        <span style={{ marginLeft: 12, fontFamily: 'var(--hand)', fontSize: 13 }}>results · march 2026</span>
      </div>
      <div style={{ flex: 1, padding: '18px 18px 18px 58px', overflowY: 'auto', position: 'relative' }}>
        <DesktopSidebar current="results" onNav={onNav} />
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 14 }}>
          <div>
            <div className="display" style={{ fontSize: 28 }}>Results</div>
            <div className="muted" style={{ fontSize: 12 }}>Mar 1 – Mar 31, 2026 · {daysIn} days in</div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <button className="btn-sketch">← Feb</button>
            <button className="btn-sketch">Mar →</button>
          </div>
        </div>
        <div style={{ background: '#fff3a8', border: '1.2px solid var(--ink)', borderRadius: 6, padding: '10px 14px', marginBottom: 14, display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontFamily: 'var(--hand)', fontSize: 13 }}>
          <span>⚠ 3 uploaded expenses ({fmtMoney(87)}) are uncategorized — they won't appear in any chart below until assigned.</span>
          <button className="btn-sketch">Review now</button>
        </div>
        <div style={{ display: 'flex', gap: 14, alignItems: 'center', marginBottom: 10, fontFamily: 'var(--hand)', fontSize: 12 }}>
          <span>Legend:</span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{ width: 16, height: 0, borderTop: '2px dashed var(--ink)' }} /> max-per-day to hit budget
          </span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{ width: 16, height: 2, background: 'var(--good)' }} /> on pace
          </span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{ width: 16, height: 2, background: '#d4a017' }} /> ahead of pace
          </span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{ width: 16, height: 2, background: 'var(--accent)' }} /> over budget
          </span>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
          {cats.map((c, i) => (
            <ResultsChart key={i} w={250} h={140} label={c.name.toUpperCase()}
              daysSpend={dailySpend(c.actual, daysIn, c.jitter, c.over)} budgetTotal={c.budget} daysIn={daysIn} />
          ))}
        </div>
      </div>
    </div>
  );
}

// Summary — mobile: big-number net. Net = savings bucket + excess (budget minus actual on spend buckets).
function SummaryPhoneV2({ onNav }) {
  // savings bucket total + excess savings across other buckets
  const cats = BUDGET.children.filter(c => !c.isUnknown);
  const savingsBucket = cats.find(c => c.name === 'Savings')?.actual || 0;
  const excess = cats.filter(c => c.name !== 'Savings')
    .reduce((s, c) => s + Math.max(0, c.amount - c.actual), 0);
  const net = savingsBucket + excess;
  const spendCats = cats.filter(c => c.name !== 'Savings');
  return (
    <PhoneFrame>
      <AppHeaderHam current="summary" onNav={onNav}
        right={<button className="icon-btn" title="More">…</button>} />
      <div style={{ textAlign: 'center', padding: '10px 0 14px' }}>
        <div className="label muted" style={{ fontSize: 11 }}>NET THIS MONTH</div>
        <div className="display" style={{ fontSize: 46, lineHeight: 1, color: 'var(--good)' }}>+{fmtMoney(net)}</div>
        <div className="muted" style={{ fontSize: 12, marginTop: 4 }}>
          {fmtMoney(savingsBucket)} saved · +{fmtMoney(excess)} under budget
        </div>
      </div>
      <div className="sketch-box" style={{ padding: 10, marginBottom: 8, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
        <div>
          <div className="label muted" style={{ fontSize: 10 }}>INCOME</div>
          <div className="display" style={{ fontSize: 22 }}>{fmtMoney(BUDGET.income)}</div>
        </div>
        <div>
          <div className="label muted" style={{ fontSize: 10 }}>SPENT</div>
          <div className="display" style={{ fontSize: 22 }}>{fmtMoney(cats.reduce((s,c) => s + c.actual, 0))}</div>
        </div>
      </div>
      <div style={{ flex: 1, overflowY: 'auto' }}>
        {spendCats.map((c, i) => {
          const pct = Math.min(150, (c.actual / c.amount) * 100);
          const over = c.actual > c.amount;
          return (
            <div key={i} style={{ padding: '8px 4px', borderBottom: '1px dashed var(--rule-soft)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span style={{ fontWeight: 700 }}>{c.name}</span>
                <span className="mono">{fmtMoney(c.actual)} / {fmtMoney(c.amount)}</span>
              </div>
              <div style={{ height: 5, background: 'var(--paper-2)', borderRadius: 3, marginTop: 4, overflow: 'hidden' }}>
                <div style={{ width: Math.min(100, pct) + '%', height: '100%', background: over ? 'var(--accent)' : 'var(--good)' }} />
              </div>
            </div>
          );
        })}
      </div>
    </PhoneFrame>
  );
}

function SummaryDesktopV2({ onNav }) {
  const cats = BUDGET.children.filter(c => !c.isUnknown);
  const savingsBucket = cats.find(c => c.name === 'Savings')?.actual || 0;
  const excess = cats.filter(c => c.name !== 'Savings')
    .reduce((s, c) => s + Math.max(0, c.amount - c.actual), 0);
  const net = savingsBucket + excess;

  return (
    <div className="desktop" style={{ height: 540 }}>
      <div className="titlebar">
        <span className="dot" /><span className="dot" /><span className="dot" />
        <span style={{ marginLeft: 12, fontFamily: 'var(--hand)', fontSize: 13 }}>summary · march 2026</span>
      </div>
      <div style={{ display: 'flex', flex: 1, position: 'relative', paddingLeft: 40 }}>
        <DesktopSidebar current="summary" onNav={onNav} />
        <section style={{ flex: 2, padding: 22, borderRight: '1.5px solid var(--rule)' }}>
          <div className="display" style={{ fontSize: 30 }}>March 2026</div>
          <div className="muted" style={{ fontSize: 12, marginBottom: 18 }}>Mar 1 – Mar 31 · 22 days in</div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 6 }}>
            <span className="label muted" style={{ fontSize: 11 }}>NET THIS MONTH</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 18 }}>
            <span className="display" style={{ fontSize: 56, lineHeight: 1, color: 'var(--good)' }}>+{fmtMoney(net)}</span>
            <span className="muted" style={{ fontSize: 13 }}>= {fmtMoney(savingsBucket)} saved + {fmtMoney(excess)} under budget</span>
          </div>
          <div className="display" style={{ fontSize: 18, marginBottom: 8 }}>Categories</div>
          {cats.filter(c => c.name !== 'Savings').map((c, i) => {
            const pct = Math.min(150, (c.actual / c.amount) * 100);
            const over = c.actual > c.amount;
            return (
              <div key={i} style={{ display: 'grid', gridTemplateColumns: '120px 1fr 160px', gap: 10, alignItems: 'center', padding: '6px 0' }}>
                <span style={{ fontFamily: 'var(--hand)', fontWeight: 700 }}>{c.name}</span>
                <div style={{ height: 8, background: 'var(--paper-2)', borderRadius: 3, position: 'relative', overflow: 'hidden' }}>
                  <div style={{ width: Math.min(100, pct) + '%', height: '100%', background: over ? 'var(--accent)' : 'var(--good)' }} />
                </div>
                <span className="mono" style={{ textAlign: 'right' }}>
                  {fmtMoney(c.actual)} / {fmtMoney(c.amount)}
                  {over ? <span className="over-chip" style={{ marginLeft: 6 }}>+{fmtMoney(c.actual - c.amount)}</span>
                    : <span className="under-chip" style={{ marginLeft: 6 }}>−{fmtMoney(c.amount - c.actual)}</span>}
                </span>
              </div>
            );
          })}
        </section>
        <aside style={{ flex: 1, padding: 22 }}>
          <div className="display" style={{ fontSize: 20, marginBottom: 8 }}>Needs review</div>
          <div className="sticky" style={{ marginBottom: 12 }}>3 uncategorized txns · {fmtMoney(87)}</div>
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

Object.assign(window, { ResultsChart, ResultsPhone, ResultsDesktop, SummaryPhoneV2, SummaryDesktopV2 });
