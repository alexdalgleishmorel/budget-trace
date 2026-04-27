// Hi-fi Results — dashed ideal line, segmented actual, unknown banner, legend.

function dailySpendHF(total, daysIn, jitter = 0.4, overshoot = false, daysInMonth = 31) {
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

function HFResultsChart({ w, h, label, daysSpend, budgetTotal, daysInMonth = 31, daysIn = 22, compact = false }) {
  const PAD_L = 36, PAD_R = 18, PAD_T = compact ? 10 : 18, PAD_B = 22;
  const innerW = w - PAD_L - PAD_R;
  const innerH = h - PAD_T - PAD_B;

  const cum = [];
  let acc = 0;
  for (let i = 0; i < daysInMonth; i++) {
    acc += (daysSpend[i] || 0);
    cum.push(acc);
  }
  const actualTotal = cum[daysIn - 1] || 0;
  const idealAt = i => (i / (daysInMonth - 1)) * budgetTotal;
  const yMax = Math.max(budgetTotal * 1.15, actualTotal * 1.1, 1);
  const xAt = i => PAD_L + (i / (daysInMonth - 1)) * innerW;
  const yAt = v => PAD_T + (1 - v / yMax) * innerH;

  const stateAt = (v, i) => {
    const ideal = idealAt(i);
    if (v > budgetTotal) return 'red';
    if (v > ideal) return 'yellow';
    return 'green';
  };
  const C = { green: 'var(--pos)', yellow: 'var(--warn)', red: 'var(--neg)' };

  const segs = [];
  let curColor = null, curPts = [];
  for (let i = 0; i < daysIn; i++) {
    const v = cum[i];
    const st = stateAt(v, i);
    if (st !== curColor) {
      if (curPts.length) {
        curPts.push([xAt(i), yAt(v)]);
        segs.push({ color: curColor, pts: curPts });
      }
      curColor = st;
      curPts = i > 0 ? [[xAt(i - 1), yAt(cum[i - 1])], [xAt(i), yAt(v)]] : [[xAt(i), yAt(v)]];
    } else {
      curPts.push([xAt(i), yAt(v)]);
    }
  }
  if (curPts.length) segs.push({ color: curColor, pts: curPts });
  const pathFor = pts => pts.map((p, j) => (j === 0 ? 'M' : 'L') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');

  const overall = stateAt(actualTotal, daysIn - 1);
  const chipColor = C[overall];
  const dotColor = chipColor;

  // area under actual, thin
  const areaPts = [];
  for (let i = 0; i < daysIn; i++) areaPts.push([xAt(i), yAt(cum[i])]);
  const areaPath =
    `M ${xAt(0).toFixed(1)} ${yAt(0).toFixed(1)} ` +
    areaPts.map(p => `L ${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' ') +
    ` L ${xAt(daysIn - 1).toFixed(1)} ${yAt(0).toFixed(1)} Z`;

  return (
    <div className="card" style={{ width: w, padding: '14px 14px 10px', position: 'relative' }}>
      <div style={{
        display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between',
        marginBottom: compact ? 6 : 10,
        gap: 10,
      }}>
        <div style={{ minWidth: 0 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}>
            <CatIcon name={label} size={14} stroke={1.7} style={{ color: 'var(--ink-3)' }} />
            <div className="label" style={{ fontSize: 10.5 }}>{label}</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, marginTop: 3 }}>
            <span className="num" style={{ fontSize: 17, fontWeight: 500, letterSpacing: -0.015 }}>
              {fmtMoney(actualTotal)}
            </span>
            <span style={{ fontSize: 11.5, color: 'var(--ink-4)' }}>
              of {fmtMoney(budgetTotal)}
            </span>
          </div>
        </div>
        <div style={{
          padding: '3px 8px',
          borderRadius: 999,
          background: overall === 'green' ? 'var(--pos-bg)' : overall === 'yellow' ? 'var(--warn-bg)' : 'var(--neg-bg)',
          border: '1px solid ' + (overall === 'green' ? 'var(--pos-border)' : overall === 'yellow' ? 'var(--warn)' : 'var(--neg-border)'),
          color: chipColor,
          fontSize: 10.5, fontWeight: 500,
          whiteSpace: 'nowrap',
          display: 'inline-flex', alignItems: 'center', gap: 4,
        }}>
          {overall === 'green' && <Icon name="check" size={11} stroke={2.2} />}
          {overall === 'yellow' && <Icon name="alert" size={11} stroke={2.2} />}
          {overall === 'red' && <Icon name="arrow-up" size={11} stroke={2.2} />}
          {overall === 'green' ? 'On pace' : overall === 'yellow' ? 'Ahead of pace' : 'Over budget'}
        </div>
      </div>

      <svg width={w - 28} height={h} viewBox={`0 0 ${w - 28} ${h}`} style={{ display: 'block' }}>
        {/* gridlines */}
        {[0, 0.5, 1].map((f, i) => (
          <line key={i}
            x1={PAD_L} y1={yAt(yMax * f)}
            x2={PAD_L + innerW} y2={yAt(yMax * f)}
            stroke="var(--rule)" strokeWidth="1" />
        ))}
        {/* y labels */}
        <text x={PAD_L - 6} y={yAt(0) + 3} fontSize="10" fontFamily="var(--font-mono)" fill="var(--ink-4)" textAnchor="end">$0</text>
        <text x={PAD_L - 6} y={yAt(budgetTotal) + 3} fontSize="10" fontFamily="var(--font-mono)" fill="var(--ink-4)" textAnchor="end">
          {fmtMoney(budgetTotal).replace('$', '$')}
        </text>

        {/* budget ceiling */}
        <line x1={PAD_L} y1={yAt(budgetTotal)} x2={PAD_L + innerW} y2={yAt(budgetTotal)}
          stroke="var(--ink-4)" strokeWidth="1" strokeDasharray="2 4" opacity="0.8" />

        {/* ideal max-per-day line (0 → budget over days) */}
        <line x1={PAD_L} y1={yAt(0)} x2={PAD_L + innerW} y2={yAt(budgetTotal)}
          stroke="var(--ink-3)" strokeWidth="1.2" strokeDasharray="4 4" opacity="0.85" />

        {/* area under actual, very faint */}
        <path d={areaPath} fill={dotColor} opacity="0.07" />

        {/* actual segments */}
        {segs.map((s, i) => (
          <path key={i} d={pathFor(s.pts)} fill="none" stroke={C[s.color]} strokeWidth="1.75"
            strokeLinecap="round" strokeLinejoin="round" />
        ))}

        {/* end dot */}
        <circle cx={xAt(daysIn - 1)} cy={yAt(actualTotal)} r="3.5" fill={dotColor} />
        <circle cx={xAt(daysIn - 1)} cy={yAt(actualTotal)} r="6" fill={dotColor} opacity="0.18" />

        {/* x labels */}
        <text x={PAD_L} y={h - 5} fontSize="10" fontFamily="var(--font-mono)" fill="var(--ink-4)">1</text>
        <text x={PAD_L + innerW} y={h - 5} fontSize="10" fontFamily="var(--font-mono)" fill="var(--ink-4)" textAnchor="end">{daysInMonth}</text>
      </svg>
    </div>
  );
}

function UnknownBanner({ count, amount, onReview, compact = false }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: compact ? '10px 12px' : '14px 18px',
      borderRadius: 14,
      background: 'var(--warn-bg)',
      border: '1px solid var(--warn)',
      color: 'var(--warn)',
    }}>
      <div style={{
        width: compact ? 28 : 32, height: compact ? 28 : 32, borderRadius: 10,
        background: 'rgba(212,178,106,0.15)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <Icon name="alert" size={compact ? 15 : 17} stroke={1.9} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: compact ? 13 : 13.5, fontWeight: 500, color: 'var(--ink)',
          letterSpacing: -0.005,
        }}>
          {count} {count === 1 ? 'expense needs' : 'expenses need'} a category
        </div>
        <div style={{ fontSize: 11.5, color: 'var(--ink-3)', marginTop: 2 }}>
          {fmtMoney(amount)} won't appear in any chart until assigned.
        </div>
      </div>
      <button className="btn" onClick={onReview}
        style={{ background: 'var(--surface)', whiteSpace: 'nowrap' }}>
        Review
        <Icon name="chevron-right" size={14} stroke={2} />
      </button>
    </div>
  );
}

function ChartLegend({ stacked = false }) {
  const items = [
    { color: 'var(--ink-3)', dash: true, label: 'Max per day' },
    { color: 'var(--pos)', label: 'On pace' },
    { color: 'var(--warn)', label: 'Ahead of pace' },
    { color: 'var(--neg)', label: 'Over budget' },
  ];
  return (
    <div style={{
      display: 'flex', gap: stacked ? 10 : 18,
      flexWrap: 'wrap',
      fontSize: 11.5, color: 'var(--ink-3)',
      alignItems: 'center',
    }}>
      {items.map((it, i) => (
        <span key={i} style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}>
          <span style={{
            width: 18, height: 2, borderRadius: 1,
            background: it.dash ? 'transparent' : it.color,
            borderTop: it.dash ? `1.5px dashed ${it.color}` : 'none',
          }} />
          {it.label}
        </span>
      ))}
    </div>
  );
}

/* ========== Mobile ========== */

function ResultsPhoneHF({ onNav }) {
  const daysIn = 22;
  const cats = [
    { name: 'House', budget: 1800, actual: 1820, jitter: 0.12, over: true },
    { name: 'Living', budget: 1450, actual: 1380, jitter: 0.5, over: false },
    { name: 'Grocery', budget: 540, actual: 712, jitter: 0.55, over: true },
    { name: 'Gas', budget: 220, actual: 198, jitter: 0.4, over: false },
  ];
  return (
    <>
      <StatusBar />
      <MobileHeaderHF
        title="Results"
        right={
          <button className="btn ghost" style={{ padding: '6px 10px', fontSize: 12 }}>
            Mar 2025
            <Icon name="chevron-down" size={13} stroke={2} style={{ marginLeft: 2 }} />
          </button>
        }
      />
      <div style={{ padding: '0 18px 12px' }}>
        <div className="label">Tracking · 22 of 31 days</div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 3 }}>
          <div className="num" style={{ fontSize: 28, fontWeight: 500, letterSpacing: -0.02 }}>
            $4,252
          </div>
          <div style={{ fontSize: 13, color: 'var(--ink-3)' }}>
            of $5,400 planned
          </div>
        </div>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '4px 18px 18px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <UnknownBanner count={3} amount={87} compact />
        {cats.map((c, i) => (
          <HFResultsChart key={i} w={354 - 28} h={150}
            label={c.name} budgetTotal={c.budget} daysIn={daysIn}
            daysSpend={dailySpendHF(c.actual, daysIn, c.jitter, c.over)} />
        ))}
      </div>

      <BottomTabsHF current="results" onNav={onNav} />
      <HomeIndicator />
    </>
  );
}

/* ========== Desktop ========== */

function ResultsDesktopHF({ onNav }) {
  const daysIn = 22;
  const cats = [
    { name: 'House', budget: 1800, actual: 1820, jitter: 0.12, over: true },
    { name: 'Living', budget: 1450, actual: 1380, jitter: 0.5, over: false },
    { name: 'Savings', budget: 1500, actual: 1500, jitter: 0.05, over: false },
    { name: 'Grocery', budget: 540, actual: 712, jitter: 0.55, over: true },
    { name: 'Gas', budget: 220, actual: 198, jitter: 0.4, over: false },
    { name: 'Fun', budget: 200, actual: 142, jitter: 0.5, over: false },
  ];
  return (
    <>
      <WindowTitleBar title="Budget Trace — Results" />
      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        <DesktopSideNav current="results" onNav={onNav} />
        <main style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, overflowY: 'auto' }}>
          <div style={{
            padding: '22px 28px 18px',
            display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
            borderBottom: '1px solid var(--rule)',
          }}>
            <div>
              <div className="label">Results</div>
              <div className="display" style={{ fontSize: 30, letterSpacing: -0.025, marginTop: 4 }}>
                March 2025
              </div>
              <div style={{ fontSize: 13, color: 'var(--ink-3)', marginTop: 4 }}>
                Mar 1 – Mar 31 · {daysIn} days in
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <button className="btn icon">
                <Icon name="chevron-left" size={16} stroke={1.8} />
              </button>
              <button className="btn icon">
                <Icon name="chevron-right" size={16} stroke={1.8} />
              </button>
            </div>
          </div>

          <div style={{ padding: '18px 28px', display: 'flex', flexDirection: 'column', gap: 16 }}>
            <UnknownBanner count={3} amount={87} />

            <div style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              gap: 16, flexWrap: 'wrap',
            }}>
              <div className="display" style={{ fontSize: 17 }}>Category performance</div>
              <ChartLegend />
            </div>

            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
              gap: 14,
            }}>
              {cats.map((c, i) => (
                <HFResultsChart key={i} w={280} h={170}
                  label={c.name} budgetTotal={c.budget} daysIn={daysIn}
                  daysSpend={dailySpendHF(c.actual, daysIn, c.jitter, c.over)} />
              ))}
            </div>
          </div>
        </main>
      </div>
    </>
  );
}

Object.assign(window, { HFResultsChart, UnknownBanner, ChartLegend, ResultsPhoneHF, ResultsDesktopHF, dailySpendHF });
