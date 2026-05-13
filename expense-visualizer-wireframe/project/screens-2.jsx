/* global React, EVIcons, EVUtils */
// Widgets dashboard + Insights chat screens.

const { useState: useState2 } = React;
const I2 = window.EVIcons;
const U2 = window.EVUtils;

// ──────────────────────────────────────────── WIDGETS

function WidgetsScreen({ compact, view, setView, onOpenAdd, onOpenSwitcher }) {
  // view: "list" | "dash"
  if (view === "list") {
    return (
      <div style={{ padding: compact ? "16px 16px 8px" : "28px 32px 32px", height: "100%", overflow: "auto" }} className="ev-scroll">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", marginBottom: 20 }}>
          <div>
            <U2.Eyebrow>Widgets</U2.Eyebrow>
            <div className={compact ? "t-h2" : "t-h1"} style={{ marginTop: 4 }}>Dashboards</div>
          </div>
          <button className="ev-btn ev-btn-primary"><I2.Plus size={16} /> {compact ? "" : "New dashboard"}</button>
        </div>

        <div className="glass" style={{ padding: "10px 14px", borderRadius: 14, display: "flex", alignItems: "center", gap: 10, marginBottom: 14 }}>
          <I2.Search size={16} style={{ color: "var(--ink-3)" }} />
          <input placeholder="Search dashboards" style={{
            flex: 1, background: "transparent", border: "none", outline: "none",
            color: "var(--ink-1)", fontFamily: "inherit", fontSize: 14,
          }} />
        </div>

        <div className="glass" style={{ borderRadius: 18, padding: 0, overflow: "hidden" }}>
          {[
            { name: "My Widgets", count: 6, date: "May 12", primary: true },
            { name: "Travel ‘26", count: 3, date: "Apr 30" },
            { name: "Subscriptions audit", count: 4, date: "Apr 18" },
          ].map((d, i) => (
            <div key={i} onClick={() => setView("dash")} style={{
              padding: "14px 18px", display: "flex", alignItems: "center", gap: 14,
              borderBottom: i < 2 ? "1px solid var(--glass-border)" : "none",
              cursor: "pointer",
            }}>
              <div style={{
                width: 38, height: 38, borderRadius: 10,
                background: d.primary ? "var(--accent-grad)" : "var(--glass-2)",
                border: d.primary ? "none" : "1px solid var(--glass-border)",
                display: "grid", placeItems: "center",
                color: d.primary ? "white" : "var(--ink-2)",
              }}>
                <I2.Chart size={16} />
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 15, fontWeight: 600 }}>{d.name}</div>
                <div className="t-sm" style={{ color: "var(--ink-3)" }}>{d.count} widgets · updated {d.date}</div>
              </div>
              <I2.ChevronRight size={16} style={{ color: "var(--ink-3)" }} />
            </div>
          ))}
        </div>
      </div>
    );
  }

  // DASHBOARD VIEW
  return (
    <div style={{ padding: compact ? "12px 12px 8px" : "20px 24px 24px", height: "100%", overflow: "auto" }} className="ev-scroll">
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, marginBottom: 16 }}>
        <button onClick={() => setView("list")} className="ev-btn ev-btn-secondary" style={{ height: 36, padding: "0 12px" }}>
          <I2.ChevronLeft size={14} />
        </button>
        <button onClick={onOpenSwitcher} className="ev-btn ev-btn-secondary" style={{ height: 36 }}>
          My Widgets <I2.ChevronDown size={12} />
        </button>
        <button onClick={onOpenAdd} className="ev-btn ev-btn-primary" style={{ height: 36 }}>
          <I2.Plus size={14} /> {compact ? "Add" : "Add widget"}
        </button>
        <div style={{ flex: compact ? 0 : 1 }} />
        {!compact && (
          <button className="ev-btn ev-btn-secondary" style={{ height: 36 }}>
            <I2.Calendar size={14} /> Last 3 months <I2.ChevronDown size={12} />
          </button>
        )}
      </div>

      <div style={{
        display: "grid",
        gridTemplateColumns: compact ? "1fr" : "2fr 1fr",
        gap: 14,
      }}>
        {/* Time series */}
        <WidgetCard title="Spend over time" subtitle="Day" tall>
          <Sparkline />
        </WidgetCard>

        {/* Big number */}
        <WidgetCard title="Avg per period" subtitle="Month" tall>
          <div style={{ height: "100%", display: "grid", placeItems: "center" }}>
            <div style={{ textAlign: "center" }}>
              <div className="tab-num" style={{ fontSize: 44, fontWeight: 600, letterSpacing: "-0.025em", lineHeight: 1, background: "var(--accent-grad)", WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent" }}>$2,593.92</div>
              <div className="t-sm" style={{ color: "var(--ink-3)", marginTop: 6 }}>last 6 months</div>
            </div>
          </div>
        </WidgetCard>

        {/* Bar chart */}
        <WidgetCard title="Spend by category" subtitle="Bar">
          <BarChart />
        </WidgetCard>

        {/* Pie */}
        <WidgetCard title="Spend by category" subtitle="Donut">
          <Donut />
        </WidgetCard>

        {/* Table */}
        <WidgetCard title="Period comparison" subtitle="Table" wide={!compact}>
          <MiniTable />
        </WidgetCard>
      </div>
    </div>
  );
}

function WidgetCard({ title, subtitle, children, tall, wide }) {
  return (
    <div className="glass" style={{
      borderRadius: 20,
      padding: 0,
      minHeight: tall ? 280 : 220,
      gridColumn: wide ? "1 / -1" : "auto",
      overflow: "hidden",
      display: "flex", flexDirection: "column",
    }}>
      <div style={{
        display: "flex", justifyContent: "space-between", alignItems: "center",
        padding: "14px 16px", borderBottom: "1px solid var(--glass-border)",
      }}>
        <div>
          <div style={{ fontSize: 11, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--ink-3)", marginBottom: 2 }}>{subtitle}</div>
          <div style={{ fontSize: 14, fontWeight: 600 }}>{title}</div>
        </div>
        <div style={{ display: "flex", gap: 4 }}>
          {[I2.Refresh, I2.Pencil, I2.Trash].map((Ic, i) => (
            <button key={i} style={{
              width: 26, height: 26, borderRadius: 7, border: "1px solid var(--glass-border)",
              background: "transparent", color: i === 2 ? "#fb7185" : "var(--ink-3)",
              cursor: "pointer", display: "grid", placeItems: "center",
            }}>
              <Ic size={12} />
            </button>
          ))}
        </div>
      </div>
      <div style={{ flex: 1, padding: 14, minHeight: 0 }}>{children}</div>
    </div>
  );
}

function Sparkline({ small, dashed = true }) {
  const pts = [
    [0, 60], [8, 30], [15, 70], [22, 45], [30, 25], [38, 55], [45, 30], [53, 65],
    [60, 40], [68, 50], [75, 35], [82, 60], [90, 45], [100, 30],
  ];
  // last 3 dashed (forecast)
  const solid = pts.slice(0, -3).map(p => p.join(",")).join(" ");
  const dash = pts.slice(-4).map(p => p.join(",")).join(" ");
  const h = small ? 80 : 200;
  return (
    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column" }}>
      <div style={{ fontSize: 11, color: "var(--ink-3)", marginBottom: 4 }}>USD</div>
      <svg viewBox="0 0 100 100" preserveAspectRatio="none" style={{ width: "100%", flex: 1 }}>
        <defs>
          <linearGradient id="sparkfill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.3" />
            <stop offset="100%" stopColor="var(--accent)" stopOpacity="0" />
          </linearGradient>
          <linearGradient id="sparkline" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="var(--accent)" />
            <stop offset="100%" stopColor="var(--accent-2)" />
          </linearGradient>
        </defs>
        {/* gridlines */}
        <line x1="0" y1="30" x2="100" y2="30" stroke="var(--glass-border)" strokeWidth="0.3" />
        <line x1="0" y1="60" x2="100" y2="60" stroke="var(--glass-border)" strokeWidth="0.3" />
        {/* fill */}
        <polygon points={`0,100 ${solid} ${pts[pts.length - 4].join(",")} 100,100`} fill="url(#sparkfill)" />
        {/* solid line */}
        <polyline points={solid} fill="none" stroke="url(#sparkline)" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
        {/* dashed forecast */}
        {dashed && (
          <polyline points={dash} fill="none" stroke="var(--accent-2)" strokeWidth="1.2" strokeDasharray="2 2" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
        )}
        {/* dot */}
        <circle cx={pts[pts.length - 4][0]} cy={pts[pts.length - 4][1]} r="1.5" fill="var(--accent)" stroke="var(--bg-0)" strokeWidth="0.5" />
      </svg>
      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 10, color: "var(--ink-3)", marginTop: 4, fontFamily: "var(--ev-font-mono)" }}>
        <span>Feb 11</span><span>Mar 5</span><span>Apr 1</span><span>May 11</span>
      </div>
    </div>
  );
}

function BarChart() {
  const data = [
    { n: "Grocery", v: 1730, c: "var(--cat-1)" },
    { n: "Shopping", v: 1328, c: "var(--cat-4)" },
    { n: "Dining", v: 1291, c: "var(--cat-8)" },
    { n: "Unassigned", v: 1008, c: "var(--cat-7)" },
    { n: "Car", v: 826, c: "var(--cat-3)" },
  ];
  const max = 1800;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10, padding: "4px 0" }}>
      {data.map((d, i) => (
        <div key={i} style={{ display: "grid", gridTemplateColumns: "78px 1fr 60px", alignItems: "center", gap: 8 }}>
          <span className="t-sm" style={{ color: "var(--ink-2)" }}>{d.n}</span>
          <div style={{ height: 8, background: "var(--glass-2)", borderRadius: 999, overflow: "hidden" }}>
            <div style={{ height: "100%", width: `${(d.v / max) * 100}%`, background: d.c, borderRadius: 999, boxShadow: `0 0 12px ${d.c}` }} />
          </div>
          <span className="tab-num t-sm" style={{ textAlign: "right", color: "var(--ink-2)" }}>${(d.v / 1000).toFixed(2)}k</span>
        </div>
      ))}
    </div>
  );
}

function Donut() {
  const data = [
    { v: 22, c: "var(--cat-1)" },
    { v: 17, c: "var(--cat-4)" },
    { v: 17, c: "var(--cat-8)" },
    { v: 13, c: "var(--cat-7)" },
    { v: 11, c: "var(--cat-3)" },
    { v: 7, c: "var(--cat-5)" },
    { v: 13, c: "var(--cat-2)" },
  ];
  const C = 2 * Math.PI * 40;
  let off = 0;
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 16, height: "100%" }}>
      <svg viewBox="0 0 100 100" style={{ width: 130, height: 130, flexShrink: 0 }}>
        <circle cx="50" cy="50" r="40" fill="none" stroke="var(--glass-2)" strokeWidth="14" />
        {data.map((d, i) => {
          const len = (d.v / 100) * C;
          const el = (
            <circle key={i} cx="50" cy="50" r="40" fill="none" stroke={d.c} strokeWidth="14"
              strokeDasharray={`${len} ${C - len}`} strokeDashoffset={-off}
              transform="rotate(-90 50 50)" />
          );
          off += len;
          return el;
        })}
        <text x="50" y="48" textAnchor="middle" fill="var(--ink-1)" fontSize="11" fontWeight="600" fontFamily="var(--ev-font-mono)">$7,782</text>
        <text x="50" y="58" textAnchor="middle" fill="var(--ink-3)" fontSize="6">Total</text>
      </svg>
      <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 4, fontSize: 12 }}>
        {[["Grocery", 22], ["Shopping", 17], ["Dining", 17], ["Unassigned", 13], ["Car", 11], ["Fun", 7]].map(([n, v], i) => (
          <div key={i} style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span className="cat-dot" style={{ background: data[i].c }} />
            <span style={{ flex: 1, color: "var(--ink-2)" }}>{n}</span>
            <span className="tab-num" style={{ color: "var(--ink-3)" }}>{v}%</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function MiniTable() {
  const rows = [
    ["Nov 13 → Feb 10", 9461],
    ["Feb 11 → May 11", 7782],
    ["Δ", -1679],
  ];
  return (
    <div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 120px", padding: "6px 0", borderBottom: "1px solid var(--glass-border)", fontSize: 11, color: "var(--ink-3)", textTransform: "uppercase", letterSpacing: "0.06em" }}>
        <div>Window</div>
        <div style={{ textAlign: "right" }}>Total</div>
      </div>
      {rows.map((r, i) => (
        <div key={i} style={{
          display: "grid", gridTemplateColumns: "1fr 120px", padding: "10px 0",
          borderBottom: i < 2 ? "1px solid var(--glass-border)" : "none",
          fontSize: 13,
        }}>
          <div style={{ color: i === 2 ? "var(--accent)" : "var(--ink-2)", fontWeight: i === 2 ? 600 : 400 }}>{r[0]}</div>
          <div className="tab-num" style={{ textAlign: "right", color: r[1] < 0 ? "var(--ev-pos)" : "var(--ink-1)", fontWeight: 600 }}>
            {r[1] < 0 ? "−" : ""}${Math.abs(r[1]).toLocaleString()}
          </div>
        </div>
      ))}
    </div>
  );
}

// ──────────────────────────────────────────── INSIGHTS

function InsightsScreen({ compact, aiOff, onSave }) {
  if (aiOff) {
    return (
      <div style={{ height: "100%", display: "grid", placeItems: "center", padding: 24 }}>
        <div className="glass" style={{ maxWidth: 460, padding: 32, borderRadius: 24, textAlign: "center" }}>
          <div style={{
            width: 80, height: 80, borderRadius: 24,
            background: "var(--accent-grad)",
            margin: "0 auto 20px",
            display: "grid", placeItems: "center",
            boxShadow: "inset 0 1px 0 rgba(255,255,255,0.3), 0 14px 36px -10px var(--accent)",
            color: "white",
          }}>
            <I2.Sparkle size={36} />
          </div>
          <div className="t-h2" style={{ marginBottom: 8 }}>Ask your money anything</div>
          <div className="t-body" style={{ color: "var(--ink-3)", marginBottom: 20 }}>
            Enable AI to chat about your spending, auto-categorize new imports, and parse PDF / image statements.
          </div>
          <button className="ev-btn ev-btn-primary">Enable AI in Account</button>
          <div className="t-sm" style={{ color: "var(--ink-4)", marginTop: 12 }}>Uses your own API key. Stored locally.</div>
        </div>
      </div>
    );
  }

  return (
    <div style={{ height: "100%", display: "flex" }}>
      {!compact && (
        <div style={{
          width: 240, borderRight: "1px solid var(--glass-border)",
          padding: "20px 14px", display: "flex", flexDirection: "column", gap: 4,
        }}>
          <U2.Eyebrow style={{ marginBottom: 10 }}>Sessions</U2.Eyebrow>
          {[
            { t: "Biggest expenses recap", active: true, d: "today" },
            { t: "Are subscriptions creeping up?", d: "yesterday" },
            { t: "Trip budget vs plan", d: "Apr 28" },
            { t: "Why did groceries spike?", d: "Apr 12" },
          ].map((s, i) => (
            <button key={i} style={{
              padding: "10px 12px", borderRadius: 10,
              background: s.active ? "var(--glass-2)" : "transparent",
              border: s.active ? "1px solid var(--glass-border)" : "1px solid transparent",
              textAlign: "left", color: "var(--ink-1)", fontFamily: "inherit", cursor: "pointer",
            }}>
              <div style={{ fontSize: 13, fontWeight: s.active ? 600 : 500, marginBottom: 2 }}>{s.t}</div>
              <div className="t-sm" style={{ color: "var(--ink-3)", fontSize: 11 }}>{s.d}</div>
            </button>
          ))}
        </div>
      )}

      <div style={{ flex: 1, display: "flex", flexDirection: "column", minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: compact ? "12px 16px" : "20px 24px 12px", gap: 10 }}>
          <div>
            <U2.Eyebrow>Insights</U2.Eyebrow>
            <div className={compact ? "t-h3" : "t-h2"} style={{ marginTop: 2 }}>Biggest expenses recap</div>
          </div>
          <div style={{ display: "flex", gap: 8 }}>
            <div className="ev-chip">$0.07 this chat</div>
            <button style={{ width: 36, height: 36, borderRadius: 999, background: "var(--glass-2)", border: "1px solid var(--glass-border)", display: "grid", placeItems: "center", color: "var(--ink-2)", cursor: "pointer" }}>
              <I2.History size={14} />
            </button>
            <button style={{ width: 36, height: 36, borderRadius: 999, background: "var(--accent-grad)", border: "none", display: "grid", placeItems: "center", color: "white", cursor: "pointer" }}>
              <I2.Plus size={14} />
            </button>
          </div>
        </div>

        <div style={{ flex: 1, overflow: "auto", padding: compact ? "8px 16px" : "8px 24px", display: "flex", flexDirection: "column", gap: 14 }} className="ev-scroll">
          <UserBubble compact={compact}>What were my biggest expenses in the past few weeks?</UserBubble>
          <AssistantBubble compact={compact}>
            <p style={{ margin: 0 }}>
              Here are your top expenses over the past 3 weeks (Apr 20 – May 11), sorted by amount. <strong>Trader Joe's</strong>, <strong>Uniqlo</strong>, and <strong>Local Farm Co-op</strong> dominate — groceries and shopping lead.
            </p>
            {/* inline widget */}
            <div className="glass-2" style={{ marginTop: 14, borderRadius: 16, overflow: "hidden" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "10px 14px", borderBottom: "1px solid var(--glass-border)" }}>
                <div style={{ fontSize: 12, fontWeight: 600 }}>Top expenses · Apr 20 → May 11</div>
                <span style={{ fontSize: 10, padding: "2px 8px", borderRadius: 999, background: "var(--glass-3)", color: "var(--ink-3)" }}>Snapshot</span>
              </div>
              <div style={{ padding: "4px 14px" }}>
                {[
                  ["Apr 24", "Trader Joe's #142", "Grocery", 194.24, "var(--cat-1)"],
                  ["Apr 27", "Uniqlo", "Shopping", 189.03, "var(--cat-4)"],
                  ["Apr 22", "Local Farm Co-op", "Grocery", 171.15, "var(--cat-1)"],
                  ["Apr 26", "MUJI", "Shopping", 142.71, "var(--cat-4)"],
                  ["Apr 20", "Shell Oil", "Gas", 72.63, "var(--cat-9)"],
                ].map((r, i) => (
                  <div key={i} style={{
                    display: "grid",
                    gridTemplateColumns: compact ? "70px 1fr 70px" : "70px 1fr 110px 80px",
                    padding: "8px 0", alignItems: "center",
                    borderBottom: i < 4 ? "1px solid var(--glass-border)" : "none",
                    fontSize: 12, fontFamily: "var(--ev-font-mono)",
                  }}>
                    <span style={{ color: "var(--ink-3)" }}>{r[0]}</span>
                    <span style={{ color: "var(--ink-1)", fontWeight: 500, fontFamily: "var(--ev-font)" }}>{r[1]}</span>
                    {!compact && (
                      <span style={{ display: "inline-flex", alignItems: "center", gap: 6, color: "var(--ink-2)", fontFamily: "var(--ev-font)", fontSize: 11 }}>
                        <span className="cat-dot" style={{ background: r[4], width: 6, height: 6 }} /> {r[2]}
                      </span>
                    )}
                    <span className="tab-num" style={{ textAlign: "right", color: "var(--ink-1)", fontWeight: 600 }}>${r[3].toFixed(2)}</span>
                  </div>
                ))}
              </div>
              <button onClick={onSave} style={{
                width: "100%", padding: "10px 14px",
                background: "var(--glass-3)", border: "none",
                borderTop: "1px solid var(--glass-border)",
                color: "var(--accent)", fontFamily: "inherit", fontSize: 12, fontWeight: 600,
                display: "flex", alignItems: "center", gap: 8, justifyContent: "center",
                cursor: "pointer",
              }}>
                <I2.Plus size={12} /> Save as widget
              </button>
            </div>
          </AssistantBubble>
        </div>

        <div style={{ padding: compact ? "12px 16px 16px" : "12px 24px 20px" }}>
          <div className="glass" style={{ borderRadius: 999, padding: "6px 6px 6px 18px", display: "flex", alignItems: "center", gap: 8 }}>
            <I2.Sparkle size={14} style={{ color: "var(--accent)" }} />
            <input placeholder="Ask about your spending…" style={{
              flex: 1, background: "transparent", border: "none", outline: "none",
              fontFamily: "inherit", color: "var(--ink-1)", fontSize: 14, padding: "10px 0",
            }} />
            <button style={{
              width: 36, height: 36, borderRadius: 999, border: "none",
              background: "var(--accent-grad)", color: "white", display: "grid", placeItems: "center", cursor: "pointer",
              boxShadow: "0 6px 16px -4px var(--accent)",
            }}>
              <I2.ArrowUp size={14} />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function UserBubble({ children, compact }) {
  return (
    <div style={{ display: "flex", justifyContent: "flex-end" }}>
      <div className="glass" style={{
        maxWidth: compact ? "85%" : "70%",
        padding: "10px 14px",
        borderRadius: 18,
        borderBottomRightRadius: 6,
        background: "var(--accent-grad)",
        color: "white",
        fontSize: 14,
        border: "none",
        boxShadow: "0 8px 24px -8px var(--accent)",
      }}>{children}</div>
    </div>
  );
}

function AssistantBubble({ children, compact }) {
  return (
    <div style={{ display: "flex", gap: 10 }}>
      <div style={{
        width: 30, height: 30, borderRadius: 999,
        background: "var(--accent-grad)", flexShrink: 0,
        display: "grid", placeItems: "center", color: "white",
        boxShadow: "inset 0 1px 0 rgba(255,255,255,0.3)",
      }}>
        <I2.Sparkle size={14} />
      </div>
      <div className="glass" style={{
        maxWidth: compact ? "85%" : "75%",
        padding: "12px 16px",
        borderRadius: 18,
        borderTopLeftRadius: 6,
        fontSize: 14,
        lineHeight: 1.5,
      }}>{children}</div>
    </div>
  );
}

window.EVScreens2 = { WidgetsScreen, InsightsScreen, Sparkline, BarChart, Donut };
