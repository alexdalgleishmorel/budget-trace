/* global React, EVIcons, EVUtils */
// Screen views — Categories, Expenses, Widgets, Insights.
// Tabs are responsive via the `compact` prop: true = mobile layout.

const { useState } = React;
const I = window.EVIcons;
const U = window.EVUtils;

// ──────────────────────────────────────────── CATEGORIES

function CategoriesScreen({ compact, onOpenCreate, onOpenEdit, empty }) {
  if (empty) {
    return (
      <div style={{ height: "100%", display: "grid", placeItems: "center", padding: 24 }}>
        <div style={{ textAlign: "center", maxWidth: 360 }}>
          <div className="glass" style={{
            width: 72, height: 72, borderRadius: 20,
            margin: "0 auto 20px", display: "grid", placeItems: "center",
            color: "var(--ink-2)",
          }}>
            <I.Grid size={30} />
          </div>
          <div className="t-h2" style={{ marginBottom: 8 }}>No categories yet</div>
          <div className="t-body" style={{ color: "var(--ink-3)", marginBottom: 20 }}>
            Categories are how Expense Visualizer organises your spending — and how the AI knows where to file things.
          </div>
          <div style={{ display: "flex", gap: 10, justifyContent: "center" }}>
            <button className="ev-btn ev-btn-primary" onClick={onOpenCreate}>
              <I.Plus size={16} /> Create category
            </button>
            <button className="ev-btn ev-btn-secondary">Use defaults</button>
          </div>
        </div>
      </div>
    );
  }

  const top = U.CATS.filter(c => !c.parent);
  const Subs = U.CATS.filter(c => c.parent === "subs");
  const CarSubs = U.CATS.filter(c => c.parent === "car");

  return (
    <div style={{ padding: compact ? "16px 16px 8px" : "28px 32px 32px", height: "100%", overflow: "auto" }} className="ev-scroll">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", marginBottom: 20 }}>
        <div>
          <Eyebrow>Categories</Eyebrow>
          <div className={compact ? "t-h2" : "t-h1"} style={{ marginTop: 4 }}>Organize spending</div>
          {!compact && <div className="t-body" style={{ color: "var(--ink-3)", marginTop: 4 }}>Drill in to see subcategories. Tap a tile to view its expenses.</div>}
        </div>
        <button className="ev-btn ev-btn-primary" onClick={onOpenCreate}>
          <I.Plus size={16} /> {compact ? "" : "New category"}
        </button>
      </div>

      <div style={{ display: "flex", gap: 6, alignItems: "center", marginBottom: 16, fontSize: 13, color: "var(--ink-3)" }}>
        <I.Home size={14} /> <span>All</span>
        <I.ChevronRight size={12} />
        <span style={{ color: "var(--ink-1)", fontWeight: 500 }}>Top-level</span>
      </div>

      <div style={{
        display: "grid",
        gridTemplateColumns: compact ? "1fr 1fr" : "repeat(4, 1fr)",
        gap: 12,
      }}>
        {top.map(c => (
          <CategoryTile key={c.id} cat={c} compact={compact} onEdit={onOpenEdit} expanded={c.id === "car" || c.id === "subs"}
            subs={c.id === "car" ? CarSubs : c.id === "subs" ? Subs : []} />
        ))}
      </div>

      {!compact && (
        <div style={{ marginTop: 28 }}>
          <Eyebrow style={{ marginBottom: 12 }}>Nested — Subscriptions</Eyebrow>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12 }}>
            {Subs.concat([
              { id: "s2", name: "Music", color: "var(--cat-11)", parent: "subs" },
              { id: "s3", name: "Cloud", color: "var(--cat-3)", parent: "subs" },
              { id: "s4", name: "News", color: "var(--cat-6)", parent: "subs" },
            ]).map(c => <CategoryTile key={c.id} cat={c} compact={compact} onEdit={onOpenEdit} small />)}
          </div>
        </div>
      )}
    </div>
  );
}

function CategoryTile({ cat, compact, onEdit, expanded, subs = [], small }) {
  const h = small ? 110 : compact ? 140 : 180;
  return (
    <div className="glass" style={{
      height: h,
      borderRadius: 20,
      padding: 14,
      display: "flex", flexDirection: "column",
      justifyContent: "space-between",
      position: "relative",
      overflow: "hidden",
      cursor: "pointer",
    }}>
      {/* color wash */}
      <div style={{
        position: "absolute", inset: 0,
        background: `radial-gradient(120% 100% at 0% 100%, ${cat.color}, transparent 70%)`,
        opacity: 0.5,
        pointerEvents: "none",
      }} />
      <div style={{ position: "relative", display: "flex", justifyContent: "space-between" }}>
        <span className="cat-dot" style={{ background: cat.color, width: 12, height: 12 }} />
        <button onClick={(e) => { e.stopPropagation(); onEdit && onEdit(cat); }} style={{
          width: 26, height: 26, borderRadius: 8, border: "1px solid var(--glass-border)",
          background: "var(--glass-2)", color: "var(--ink-2)", display: "grid", placeItems: "center",
          cursor: "pointer",
        }}>
          <I.Pencil size={12} />
        </button>
      </div>
      <div style={{ position: "relative" }}>
        <div style={{ fontSize: small ? 15 : 18, fontWeight: 600, letterSpacing: "-0.015em" }}>{cat.name}</div>
        {expanded && subs.length > 0 && (
          <div style={{ display: "flex", gap: 4, marginTop: 8, flexWrap: "wrap" }}>
            {subs.map(s => (
              <span key={s.id} style={{
                fontSize: 10, padding: "3px 8px", borderRadius: 999,
                background: "var(--glass-3)", color: "var(--ink-2)",
                border: "1px solid var(--glass-border)",
              }}>{s.name}</span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

const Eyebrow = U.Eyebrow;

// ──────────────────────────────────────────── EXPENSES

function ExpensesScreen({ compact, onOpenEdit, onOpenImport, empty }) {
  const [month, setMonth] = useState("May 2026");
  const [activeCat, setActiveCat] = useState("all");
  const txs = empty ? [] : U.TX;
  const total = txs.reduce((s, t) => s + t.a, 0);
  const unknown = txs.filter(t => !t.c).length;

  return (
    <div style={{ padding: compact ? "16px 16px 8px" : "28px 32px 32px", height: "100%", overflow: "auto" }} className="ev-scroll">
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 20, gap: 12, flexWrap: "wrap" }}>
        <div>
          <Eyebrow>Expenses</Eyebrow>
          <div className={compact ? "t-h2" : "t-h1"} style={{ marginTop: 4, display: "flex", alignItems: "center", gap: 10 }}>
            <span>{month}</span>
            <button style={{
              display: "inline-flex", alignItems: "center", gap: 6,
              padding: "4px 10px", borderRadius: 999,
              background: "var(--glass-2)", border: "1px solid var(--glass-border)",
              fontSize: 12, fontWeight: 500, color: "var(--ink-2)", cursor: "pointer",
            }}>
              <I.Calendar size={12} /> <I.ChevronDown size={12} />
            </button>
          </div>
          {!compact && <div className="t-body" style={{ color: "var(--ink-3)", marginTop: 4 }}>Real transactions from your linked statements.</div>}
        </div>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          <div className="ev-chip" style={{ height: 36, padding: "0 14px" }}>
            <I.Sparkle size={12} style={{ color: "var(--accent)" }} /> $0.18 spent on AI
          </div>
          <div style={{ textAlign: "right" }}>
            <Eyebrow>Total</Eyebrow>
            <div className="tab-num" style={{ fontSize: compact ? 20 : 26, fontWeight: 600 }}>${total.toFixed(2)}</div>
          </div>
        </div>
      </div>

      {/* Dropzone */}
      <div className="glass" style={{
        padding: 16,
        borderRadius: 20,
        marginBottom: 16,
        display: "flex", gap: 16, alignItems: "center",
        flexDirection: compact ? "column" : "row",
        borderStyle: "dashed",
        cursor: "pointer",
      }} onClick={onOpenImport}>
        <div style={{
          width: 56, height: 56, borderRadius: 16,
          background: "var(--accent-grad)",
          display: "grid", placeItems: "center", color: "white",
          boxShadow: "inset 0 1px 0 rgba(255,255,255,0.3)",
          flexShrink: 0,
        }}>
          <I.Upload size={22} />
        </div>
        <div style={{ flex: 1, textAlign: compact ? "center" : "left" }}>
          <div className="t-h3">Drop a statement</div>
          <div className="t-sm" style={{ color: "var(--ink-3)" }}>CSV, PDF, or image — parsed by AI</div>
        </div>
        {!compact && (
          <button className="ev-btn ev-btn-secondary">Browse files</button>
        )}
      </div>

      {/* Category chips */}
      <div style={{ display: "flex", gap: 8, marginBottom: 14, overflowX: "auto", paddingBottom: 4 }} className="ev-scroll">
        <button onClick={() => setActiveCat("all")} className={"ev-chip " + (activeCat === "all" ? "ev-chip-active" : "")} style={{ cursor: "pointer", fontFamily: "inherit" }}>
          <I.Filter size={12} /> All
        </button>
        {U.CATS.filter(c => !c.parent).slice(0, 7).map(c => (
          <button key={c.id} onClick={() => setActiveCat(c.id)} className={"ev-chip " + (activeCat === c.id ? "ev-chip-active" : "")} style={{ cursor: "pointer", fontFamily: "inherit" }}>
            <span className="cat-dot" style={{ background: c.color, width: 8, height: 8 }} /> {c.name}
          </button>
        ))}
      </div>

      {/* Needs-review banner */}
      {!empty && unknown > 0 && (
        <div className="glass" style={{
          padding: "10px 14px", borderRadius: 14, marginBottom: 12,
          display: "flex", alignItems: "center", gap: 10,
          borderColor: "color-mix(in srgb, var(--ev-warn) 35%, var(--glass-border))",
        }}>
          <I.Warn size={16} style={{ color: "var(--ev-warn)" }} />
          <span className="t-sm" style={{ flex: 1 }}>
            <strong>{unknown} transactions</strong> need a category
          </span>
          <button className="ev-btn ev-btn-ghost" style={{ height: 30, fontSize: 12 }}>Review →</button>
        </div>
      )}

      {/* List */}
      {empty ? (
        <div style={{ padding: "60px 20px", textAlign: "center" }}>
          <div className="glass" style={{
            width: 64, height: 64, borderRadius: 18,
            margin: "0 auto 16px", display: "grid", placeItems: "center",
            color: "var(--ink-2)",
          }}>
            <I.Inbox size={26} />
          </div>
          <div className="t-h3" style={{ marginBottom: 6 }}>No expenses in {month}</div>
          <div className="t-sm" style={{ color: "var(--ink-3)", maxWidth: 320, margin: "0 auto" }}>
            Drop a statement above — or use the cycle picker to jump to a month that has data.
          </div>
        </div>
      ) : (
        <div className="glass" style={{ borderRadius: 20, overflow: "hidden", padding: 0 }}>
          {!compact && (
            <div style={{
              display: "grid",
              gridTemplateColumns: "100px 1fr 160px 110px 40px",
              padding: "12px 18px",
              fontSize: 11, letterSpacing: "0.06em", textTransform: "uppercase",
              color: "var(--ink-3)",
              borderBottom: "1px solid var(--glass-border)",
            }}>
              <div>Date</div>
              <div>Merchant</div>
              <div>Category</div>
              <div style={{ textAlign: "right" }}>Amount</div>
              <div />
            </div>
          )}
          {txs.map((t, i) => <TxRow key={i} t={t} compact={compact} onEdit={() => onOpenEdit(t)} />)}
        </div>
      )}
    </div>
  );
}

function TxRow({ t, compact, onEdit }) {
  const cat = U.CATS.find(c => c.id === t.c);
  if (compact) {
    return (
      <div style={{
        padding: "12px 16px", display: "flex", alignItems: "center", gap: 12,
        borderBottom: "1px solid var(--glass-border)",
      }}>
        <span className="cat-dot" style={{ background: cat ? cat.color : "var(--ev-warn)", width: 10, height: 10 }} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14, fontWeight: 500 }}>{t.m}</div>
          <div className="t-sm" style={{ color: "var(--ink-3)", display: "flex", gap: 6 }}>
            <span>{t.d}</span><span>·</span>
            <span style={{ color: cat ? "var(--ink-2)" : "var(--ev-warn)" }}>{cat ? cat.name : "Needs category"}</span>
          </div>
        </div>
        <div className="tab-num" style={{ fontWeight: 600, fontSize: 15 }}>${t.a.toFixed(2)}</div>
      </div>
    );
  }
  return (
    <div style={{
      display: "grid",
      gridTemplateColumns: "100px 1fr 160px 110px 40px",
      padding: "12px 18px", alignItems: "center",
      borderBottom: "1px solid var(--glass-border)",
      transition: "background 0.15s",
    }}
      onMouseEnter={e => e.currentTarget.style.background = "var(--glass-1)"}
      onMouseLeave={e => e.currentTarget.style.background = "transparent"}
    >
      <div className="tab-num t-sm" style={{ color: "var(--ink-2)" }}>{t.d}</div>
      <div style={{ fontSize: 14, fontWeight: 500, display: "flex", alignItems: "center", gap: 8 }}>
        <span className="cat-dot" style={{ background: cat ? cat.color : "var(--ev-warn)" }} />
        {t.m}
      </div>
      <div>
        {cat ? (
          <span style={{
            display: "inline-flex", alignItems: "center", gap: 6,
            padding: "4px 10px", borderRadius: 999,
            background: "var(--glass-2)", border: "1px solid var(--glass-border)",
            fontSize: 12, color: "var(--ink-2)",
          }}>
            {cat.name} <I.ChevronDown size={10} />
          </span>
        ) : (
          <span style={{
            display: "inline-flex", alignItems: "center", gap: 6,
            padding: "4px 10px", borderRadius: 999,
            background: "color-mix(in srgb, var(--ev-warn) 18%, transparent)",
            color: "var(--ev-warn)", fontSize: 12, fontWeight: 500,
            border: "1px solid color-mix(in srgb, var(--ev-warn) 35%, transparent)",
          }}>
            <I.Warn size={11} /> Needs category
          </span>
        )}
      </div>
      <div className="tab-num" style={{ textAlign: "right", fontWeight: 600 }}>${t.a.toFixed(2)}</div>
      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <button onClick={onEdit} style={{
          width: 28, height: 28, borderRadius: 8, border: "1px solid var(--glass-border)",
          background: "var(--glass-1)", color: "var(--ink-2)", display: "grid", placeItems: "center",
          cursor: "pointer",
        }}>
          <I.Pencil size={12} />
        </button>
      </div>
    </div>
  );
}

window.EVScreens1 = { CategoriesScreen, ExpensesScreen };
