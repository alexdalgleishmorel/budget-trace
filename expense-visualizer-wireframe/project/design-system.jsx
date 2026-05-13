/* global React */
const IDS = window.EVIcons;
const UDS = window.EVUtils;

function DesignSystemScreen() {
  return (
    <div style={{ padding: "32px 36px", height: "100%", overflow: "auto" }} className="ev-scroll">
      <UDS.Eyebrow>Design system</UDS.Eyebrow>
      <div className="t-h1" style={{ marginTop: 4, marginBottom: 6 }}>Expense Visualizer · tokens</div>
      <div className="t-body" style={{ color: "var(--ink-3)", marginBottom: 28, maxWidth: 600 }}>
        Liquid-glass surfaces over a saturated ambient background. Soft geometry, tabular numbers, stroke icons. Each token resolves to a CSS custom property the engineer can lift directly.
      </div>

      <Section title="Color · backgrounds">
        <Row>
          <Swatch tok="--bg-0" label="Page" big />
          <Swatch tok="--bg-1" label="Tier 1" big />
          <Swatch tok="--bg-2" label="Tier 2" big />
        </Row>
      </Section>

      <Section title="Color · glass surfaces">
        <Row>
          <Swatch tok="--glass-1" label="Glass 01" big />
          <Swatch tok="--glass-2" label="Glass 02" big />
          <Swatch tok="--glass-3" label="Glass 03" big />
          <Swatch tok="--glass-border" label="Border" big />
        </Row>
      </Section>

      <Section title="Color · ink">
        <Row>
          {["--ink-1", "--ink-2", "--ink-3", "--ink-4"].map((t, i) => (
            <Swatch key={t} tok={t} label={`Ink 0${i + 1}`} />
          ))}
        </Row>
      </Section>

      <Section title="Color · semantic">
        <Row>
          <Swatch tok="--ev-pos" label="Positive" />
          <Swatch tok="--ev-neg" label="Negative" />
          <Swatch tok="--ev-warn" label="Warning" />
          <Swatch tok="--accent" label="Accent" />
          <Swatch tok="--accent-2" label="Accent 2" />
        </Row>
      </Section>

      <Section title="Color · category swatches">
        <div style={{ display: "grid", gridTemplateColumns: "repeat(6, 1fr)", gap: 10 }}>
          {Array.from({ length: 12 }, (_, i) => (
            <div key={i}>
              <div style={{ aspectRatio: "1", borderRadius: 14, background: `var(--cat-${i + 1})`, border: "1px solid var(--glass-border)", boxShadow: `0 4px 14px -6px var(--cat-${i + 1})` }} />
              <div className="t-sm" style={{ marginTop: 6, fontFamily: "var(--ev-font-mono)", color: "var(--ink-3)" }}>cat-{String(i + 1).padStart(2, "0")}</div>
            </div>
          ))}
        </div>
      </Section>

      <Section title="Typography scale">
        <div className="glass" style={{ padding: 20, borderRadius: 16 }}>
          {[["Display", 40, 600, "-0.03em"], ["H1", 28, 600, "-0.02em"], ["H2", 22, 600, "-0.015em"], ["H3", 17, 600, "-0.01em"], ["Body", 14, 400, "0"], ["Small", 12, 400, "0"], ["Eyebrow", 11, 600, "0.06em"], ["Mono · numbers", 16, 500, "0"]].map(([n, sz, w, ls], i) => (
            <div key={i} style={{ display: "flex", alignItems: "baseline", padding: "10px 0", borderBottom: i < 7 ? "1px solid var(--glass-border)" : "none", gap: 24 }}>
              <span style={{ width: 130, fontSize: 12, color: "var(--ink-3)", fontFamily: "var(--ev-font-mono)" }}>{n} · {sz}/{w}</span>
              <span style={{ fontSize: sz, fontWeight: w, letterSpacing: ls, fontFamily: n.includes("Mono") ? "var(--ev-font-mono)" : "var(--ev-font)", textTransform: n === "Eyebrow" ? "uppercase" : "none" }}>
                {n === "Mono · numbers" ? "$2,593.92" : "The quick brown fox jumps"}
              </span>
            </div>
          ))}
        </div>
      </Section>

      <Section title="Radii">
        <Row>
          {[8, 12, 14, 16, 20, 24, 999].map(r => (
            <div key={r} style={{ textAlign: "center" }}>
              <div style={{ width: 64, height: 64, borderRadius: r, background: "var(--glass-2)", border: "1px solid var(--glass-border)" }} />
              <div className="t-sm" style={{ marginTop: 6, fontFamily: "var(--ev-font-mono)", color: "var(--ink-3)" }}>{r === 999 ? "pill" : `${r}px`}</div>
            </div>
          ))}
        </Row>
      </Section>

      <Section title="Glass recipe">
        <div className="glass" style={{ padding: 20, borderRadius: 16 }}>
          <pre style={{ margin: 0, fontFamily: "var(--ev-font-mono)", fontSize: 12, color: "var(--ink-2)", whiteSpace: "pre-wrap", lineHeight: 1.7 }}>{`background: var(--glass-1);   /* tinted translucent fill */
backdrop-filter: blur(22px) saturate(150%);
border: 1px solid var(--glass-border);
box-shadow:
  inset 0 1px 0 var(--glass-hi),   /* top highlight   */
  inset 0 -1px 0 var(--glass-lo),  /* bottom shade    */
  0 18px 40px -16px rgba(0,0,0,.4); /* ambient lift   */
border-radius: 20px;`}</pre>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12, marginTop: 12 }}>
          {[1, 2, 3].map(t => (
            <div key={t} className={t === 1 ? "glass" : t === 2 ? "glass-2" : "glass-strong"} style={{ padding: 16, borderRadius: 16, height: 80, display: "grid", placeItems: "center", fontSize: 13, color: "var(--ink-2)" }}>
              Tier {t.toString().padStart(2, "0")}
            </div>
          ))}
        </div>
      </Section>

      <Section title="Buttons">
        <Row>
          <button className="ev-btn ev-btn-primary">Primary</button>
          <button className="ev-btn ev-btn-secondary">Secondary</button>
          <button className="ev-btn ev-btn-ghost">Ghost</button>
          <button className="ev-btn ev-btn-secondary" style={{ color: "#fb7185", borderColor: "color-mix(in srgb, #fb7185 35%, var(--glass-border))" }}>Destructive</button>
        </Row>
      </Section>

      <Section title="Chips · pills">
        <Row>
          <span className="ev-chip"><span className="cat-dot" style={{ background: "var(--cat-1)", width: 8, height: 8 }} /> Grocery</span>
          <span className="ev-chip ev-chip-active">Active</span>
          <span className="ev-chip"><IDS.Sparkle size={12} style={{ color: "var(--accent)" }} /> AI</span>
          <span className="ev-chip" style={{ color: "var(--ev-warn)", borderColor: "color-mix(in srgb, var(--ev-warn) 35%, var(--glass-border))" }}><IDS.Warn size={12} /> Needs review</span>
        </Row>
      </Section>

      <Section title="Form fields">
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, maxWidth: 600 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "0 14px", height: 42, borderRadius: 12, background: "var(--glass-1)", border: "1px solid var(--glass-border)" }}>
            <IDS.Search size={14} style={{ color: "var(--ink-3)" }} />
            <input placeholder="Text input" style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--ink-1)", fontFamily: "inherit", fontSize: 14 }} />
          </div>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 14px", height: 42, borderRadius: 12, background: "var(--glass-1)", border: "1px solid var(--glass-border)" }}>
            <span style={{ fontSize: 14, color: "var(--ink-2)" }}>Dropdown</span>
            <IDS.ChevronDown size={14} style={{ color: "var(--ink-3)" }} />
          </div>
        </div>
      </Section>

      <Section title="Icons (stroke)">
        <div style={{ display: "grid", gridTemplateColumns: "repeat(8, 1fr)", gap: 10 }}>
          {["Home", "Grid", "List", "Chart", "Search", "Sparkle", "Upload", "Calendar", "Filter", "Plus", "Pencil", "Trash", "Check", "X", "Warn", "Inbox", "Refresh", "ChevronDown", "ChevronRight", "Eye", "EyeOff", "Settings", "User", "History", "ArrowUp", "ChevronLeft"].map(n => {
            const Ic = IDS[n];
            if (!Ic) return null;
            return (
              <div key={n} className="glass" style={{ padding: 12, borderRadius: 12, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                <Ic size={18} />
                <span style={{ fontSize: 10, fontFamily: "var(--ev-font-mono)", color: "var(--ink-3)" }}>{n}</span>
              </div>
            );
          })}
        </div>
      </Section>
    </div>
  );
}

function Section({ title, children }) {
  return (
    <div style={{ marginBottom: 32 }}>
      <UDS.Eyebrow style={{ marginBottom: 12 }}>{title}</UDS.Eyebrow>
      {children}
    </div>
  );
}
function Row({ children }) { return <div style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "flex-end" }}>{children}</div>; }
function Swatch({ tok, label, big }) {
  const sz = big ? 92 : 70;
  return (
    <div style={{ textAlign: "center" }}>
      <div style={{ width: sz, height: sz, borderRadius: 14, background: `var(${tok})`, border: "1px solid var(--glass-border)", boxShadow: "inset 0 1px 0 var(--glass-hi)" }} />
      <div style={{ marginTop: 6, fontSize: 12, fontWeight: 500 }}>{label}</div>
      <div style={{ fontFamily: "var(--ev-font-mono)", fontSize: 10, color: "var(--ink-3)" }}>{tok}</div>
    </div>
  );
}

window.EVDesignSystem = { DesignSystemScreen };
