// Hi-fi Summary — big-number net + breakdown + category bars.

function SummaryPhoneHF({ onNav }) {
  const cats = BUDGET.children.filter(c => !c.isUnknown);
  const savingsBucket = cats.find(c => c.name === 'Savings')?.actual || 0;
  const excess = cats.filter(c => c.name !== 'Savings')
    .reduce((s, c) => s + Math.max(0, c.amount - c.actual), 0);
  const net = savingsBucket + excess;
  const spent = cats.reduce((s, c) => s + c.actual, 0);
  const spendCats = cats.filter(c => c.name !== 'Savings');

  return (
    <>
      <StatusBar />
      <MobileHeaderHF
        title="Summary"
        right={
          <button className="btn icon ghost">
            <Icon name="more" size={18} stroke={1.8} />
          </button>
        }
      />

      <div style={{ flex: 1, overflowY: 'auto', padding: '4px 18px 18px' }}>
        {/* Big number */}
        <div style={{
          textAlign: 'center', padding: '12px 0 20px',
        }}>
          <div className="label">Net this cycle</div>
          <div style={{
            fontFamily: 'var(--font-mono)', fontSize: 56, fontWeight: 500,
            letterSpacing: -0.03, lineHeight: 1,
            color: 'var(--pos)', marginTop: 6,
          }}>
            +{fmtMoney(net)}
          </div>
          <div style={{ fontSize: 12.5, color: 'var(--ink-3)', marginTop: 10, lineHeight: 1.5 }}>
            <span className="num">{fmtMoney(savingsBucket)}</span> into savings
            <br/>
            <span className="num">+{fmtMoney(excess)}</span> under budget on spend
          </div>
        </div>

        {/* Income / spent cards */}
        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 1fr',
          gap: 10, marginBottom: 18,
        }}>
          <div className="card" style={{ padding: 14 }}>
            <div className="label">Income</div>
            <div className="num" style={{
              fontSize: 22, fontWeight: 500, letterSpacing: -0.015, marginTop: 4,
            }}>
              {fmtMoney(BUDGET.income)}
            </div>
          </div>
          <div className="card" style={{ padding: 14 }}>
            <div className="label">Spent</div>
            <div className="num" style={{
              fontSize: 22, fontWeight: 500, letterSpacing: -0.015, marginTop: 4,
            }}>
              {fmtMoney(spent)}
            </div>
          </div>
        </div>

        {/* Category bars */}
        <div className="display" style={{ fontSize: 15, marginBottom: 10 }}>Categories</div>
        <div className="card" style={{ overflow: 'hidden' }}>
          {spendCats.map((c, i) => {
            const pct = Math.min(150, (c.actual / c.amount) * 100);
            const over = c.actual > c.amount;
            return (
              <div key={i} style={{
                padding: '12px 14px',
                borderTop: i === 0 ? 'none' : '1px solid var(--rule)',
              }}>
                <div style={{
                  display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                  marginBottom: 6,
                }}>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                    <CatIcon name={c.name} size={14} stroke={1.7} style={{ color: 'var(--ink-3)' }} />
                    <span style={{ fontSize: 13, fontWeight: 500 }}>{c.name}</span>
                  </span>
                  <span className="num" style={{
                    fontSize: 12.5,
                    color: over ? 'var(--neg)' : 'var(--ink-2)',
                  }}>
                    {fmtMoney(c.actual)}
                    <span style={{ color: 'var(--ink-4)' }}> / {fmtMoney(c.amount)}</span>
                  </span>
                </div>
                <div style={{
                  height: 4, background: 'var(--surface-2)', borderRadius: 2,
                  overflow: 'hidden', position: 'relative',
                }}>
                  <div style={{
                    width: Math.min(100, pct) + '%',
                    height: '100%',
                    background: over ? 'var(--neg)' : 'var(--pos)',
                    borderRadius: 2,
                  }} />
                </div>
              </div>
            );
          })}
        </div>
      </div>

      <BottomTabsHF current="summary" onNav={onNav} />
      <HomeIndicator />
    </>
  );
}

function SummaryDesktopHF({ onNav }) {
  const cats = BUDGET.children.filter(c => !c.isUnknown);
  const savingsBucket = cats.find(c => c.name === 'Savings')?.actual || 0;
  const excess = cats.filter(c => c.name !== 'Savings')
    .reduce((s, c) => s + Math.max(0, c.amount - c.actual), 0);
  const net = savingsBucket + excess;
  const spent = cats.reduce((s, c) => s + c.actual, 0);
  const spendCats = cats.filter(c => c.name !== 'Savings');
  const unknowns = makeTransactions().filter(t => !t.cat);

  return (
    <>
      <WindowTitleBar title="Budget Trace — Summary" />
      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        <DesktopSideNav current="summary" onNav={onNav} />
        <main style={{ flex: 1, display: 'flex', minWidth: 0 }}>
          {/* Left: headline + categories */}
          <section style={{
            flex: 2, padding: '26px 28px', borderRight: '1px solid var(--rule)',
            overflowY: 'auto',
          }}>
            <div className="label">Summary</div>
            <div className="display" style={{ fontSize: 30, letterSpacing: -0.025, marginTop: 4 }}>
              March 2025
            </div>
            <div style={{ fontSize: 13, color: 'var(--ink-3)', marginTop: 4 }}>
              Mar 1 – Mar 31 · 22 days in · cycle closes Mar 31.
            </div>

            {/* Big net */}
            <div style={{
              marginTop: 26,
              padding: '24px 26px',
              borderRadius: 20,
              background: 'linear-gradient(180deg, var(--pos-bg) 0%, transparent 100%)',
              border: '1px solid var(--pos-border)',
            }}>
              <div className="label" style={{ color: 'var(--pos)' }}>Net this cycle</div>
              <div style={{
                fontFamily: 'var(--font-mono)', fontSize: 64, fontWeight: 500,
                letterSpacing: -0.035, lineHeight: 1,
                color: 'var(--pos)', marginTop: 8,
              }}>
                +{fmtMoney(net)}
              </div>
              <div style={{
                display: 'flex', gap: 18, marginTop: 14,
                fontSize: 13, color: 'var(--ink-2)',
              }}>
                <span>
                  <span className="num" style={{ fontWeight: 500 }}>{fmtMoney(savingsBucket)}</span>
                  <span style={{ color: 'var(--ink-4)', marginLeft: 6 }}>into savings</span>
                </span>
                <span style={{ color: 'var(--ink-5)' }}>+</span>
                <span>
                  <span className="num" style={{ fontWeight: 500 }}>{fmtMoney(excess)}</span>
                  <span style={{ color: 'var(--ink-4)', marginLeft: 6 }}>under budget on spend</span>
                </span>
              </div>
            </div>

            {/* Income / spent */}
            <div style={{
              display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
              gap: 10, marginTop: 20,
            }}>
              {[
                ['Income', fmtMoney(BUDGET.income), null],
                ['Spent', fmtMoney(spent), null],
                ['Remaining', fmtMoney(BUDGET.income - spent), 'pos'],
              ].map(([lab, val, tone], i) => (
                <div key={i} className="card" style={{ padding: 14 }}>
                  <div className="label">{lab}</div>
                  <div className="num" style={{
                    fontSize: 24, fontWeight: 500, letterSpacing: -0.015, marginTop: 4,
                    color: tone === 'pos' ? 'var(--pos)' : 'var(--ink)',
                  }}>
                    {val}
                  </div>
                </div>
              ))}
            </div>

            <div className="display" style={{ fontSize: 17, margin: '28px 0 10px' }}>
              Categories
            </div>
            <div className="card" style={{ overflow: 'hidden' }}>
              <div style={{
                display: 'grid',
                gridTemplateColumns: '160px 1fr 200px',
                gap: 16, padding: '11px 18px',
                borderBottom: '1px solid var(--rule)',
              }}>
                <span className="label">Category</span>
                <span className="label">Pace</span>
                <span className="label" style={{ textAlign: 'right' }}>Actual / Planned</span>
              </div>
              {spendCats.map((c, i) => {
                const pct = Math.min(150, (c.actual / c.amount) * 100);
                const over = c.actual > c.amount;
                const delta = c.actual - c.amount;
                return (
                  <div key={i} style={{
                    display: 'grid',
                    gridTemplateColumns: '160px 1fr 200px',
                    gap: 16, padding: '13px 18px',
                    borderTop: '1px solid var(--rule-soft)',
                    alignItems: 'center',
                  }}>
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 9 }}>
                      <CatIcon name={c.name} size={15} stroke={1.7} style={{ color: 'var(--ink-3)' }} />
                      <span style={{ fontSize: 13.5, fontWeight: 500 }}>{c.name}</span>
                    </span>
                    <div style={{
                      height: 6, background: 'var(--surface-2)', borderRadius: 3,
                      overflow: 'hidden',
                    }}>
                      <div style={{
                        width: Math.min(100, pct) + '%',
                        height: '100%',
                        background: over ? 'var(--neg)' : 'var(--pos)',
                      }} />
                    </div>
                    <div style={{
                      textAlign: 'right',
                      display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 8,
                    }}>
                      <span className="num" style={{ fontSize: 13 }}>
                        {fmtMoney(c.actual)}
                        <span style={{ color: 'var(--ink-4)' }}> / {fmtMoney(c.amount)}</span>
                      </span>
                      <span className={'chip ' + (over ? 'neg' : 'pos')} style={{ minWidth: 56, justifyContent: 'center' }}>
                        {over ? '+' : '−'}{fmtMoney(Math.abs(delta))}
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>
          </section>

          {/* Right: needs review rail */}
          <aside style={{
            width: 340, flexShrink: 0, padding: '26px 24px',
            overflowY: 'auto',
          }}>
            <div className="label">Attention</div>
            <div className="display" style={{ fontSize: 18, marginTop: 4, marginBottom: 10 }}>
              Needs review
            </div>
            <div style={{
              padding: '11px 14px', marginBottom: 14,
              borderRadius: 12,
              background: 'var(--warn-bg)',
              border: '1px solid var(--warn)',
              fontSize: 12.5, color: 'var(--ink-2)',
            }}>
              <span className="num" style={{ fontWeight: 500 }}>{unknowns.length}</span> uncategorized &middot;{' '}
              <span className="num">{fmtMoney(unknowns.reduce((s, t) => s + t.amount, 0))}</span>
            </div>

            <div className="card" style={{ overflow: 'hidden' }}>
              {unknowns.map((t, i) => (
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
                  <HFCategoryChip value={null} onChange={() => {}} />
                </div>
              ))}
            </div>

            <button className="btn" style={{ width: '100%', marginTop: 12, justifyContent: 'center' }}>
              Open expenses
              <Icon name="chevron-right" size={14} stroke={2} />
            </button>
          </aside>
        </main>
      </div>
    </>
  );
}

Object.assign(window, { SummaryPhoneHF, SummaryDesktopHF });
