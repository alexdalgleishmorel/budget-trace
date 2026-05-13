/* global React */
const I3 = window.EVIcons;
const U3 = window.EVUtils;
const { useState: useState3 } = React;

function Backdrop({ children, onClose, align = "center" }) {
  return (
    <div onClick={onClose} style={{
      position: "absolute", inset: 0,
      background: "rgba(8, 6, 20, 0.55)",
      backdropFilter: "blur(8px)",
      WebkitBackdropFilter: "blur(8px)",
      display: "flex", alignItems: align, justifyContent: "center",
      padding: 20, zIndex: 50,
    }}>
      <div onClick={e => e.stopPropagation()} style={{ width: "100%", maxWidth: 560, maxHeight: "100%", overflow: "auto" }} className="ev-scroll">
        {children}
      </div>
    </div>
  );
}

function ModalShell({ title, onClose, children, footer }) {
  return (
    <div className="glass-strong" style={{ borderRadius: 24, overflow: "hidden", boxShadow: "0 32px 80px -16px rgba(0,0,0,0.4)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "16px 20px", borderBottom: "1px solid var(--glass-border)" }}>
        <div style={{ fontSize: 16, fontWeight: 600 }}>{title}</div>
        <button onClick={onClose} style={{ width: 32, height: 32, borderRadius: 999, border: "1px solid var(--glass-border)", background: "var(--glass-2)", color: "var(--ink-2)", cursor: "pointer", display: "grid", placeItems: "center" }}>
          <I3.X size={14} />
        </button>
      </div>
      <div style={{ padding: 20 }}>{children}</div>
      {footer && <div style={{ display: "flex", justifyContent: "flex-end", gap: 10, padding: "14px 20px", borderTop: "1px solid var(--glass-border)", background: "var(--glass-1)" }}>{footer}</div>}
    </div>
  );
}

function Field({ label, children }) {
  return (
    <div style={{ marginBottom: 14 }}>
      <div style={{ fontSize: 11, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--ink-3)", marginBottom: 6 }}>{label}</div>
      {children}
    </div>
  );
}

function Input({ placeholder, defaultValue, type = "text", icon }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "0 14px", height: 42, borderRadius: 12, background: "var(--glass-1)", border: "1px solid var(--glass-border)" }}>
      {icon && <span style={{ color: "var(--ink-3)" }}>{icon}</span>}
      <input type={type} defaultValue={defaultValue} placeholder={placeholder} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--ink-1)", fontFamily: "inherit", fontSize: 14 }} />
    </div>
  );
}

function Toggle({ on, onChange }) {
  return (
    <button onClick={onChange} style={{
      width: 44, height: 26, borderRadius: 999, border: "none", cursor: "pointer",
      background: on ? "var(--accent-grad)" : "var(--glass-3)",
      position: "relative", transition: "background 0.15s",
      boxShadow: on ? "0 4px 12px -2px var(--accent)" : "inset 0 0 0 1px var(--glass-border)",
    }}>
      <span style={{ position: "absolute", top: 3, left: on ? 21 : 3, width: 20, height: 20, borderRadius: 999, background: "white", transition: "left 0.15s", boxShadow: "0 2px 6px rgba(0,0,0,0.2)" }} />
    </button>
  );
}

function FlagRow({ label, desc, defaultOn }) {
  const [on, setOn] = useState3(defaultOn);
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "10px 14px", background: "var(--glass-1)", borderRadius: 12, border: "1px solid var(--glass-border)", marginBottom: 8 }}>
      <div>
        <div style={{ fontSize: 13, fontWeight: 500 }}>{label}</div>
        <div className="t-sm" style={{ color: "var(--ink-3)" }}>{desc}</div>
      </div>
      <Toggle on={on} onChange={() => setOn(!on)} />
    </div>
  );
}

function AccountModal({ onClose, mode, setMode }) {
  const [ai, setAi] = useState3(true);
  const [show, setShow] = useState3({});
  return (
    <Backdrop onClose={onClose} align="flex-start">
      <ModalShell title="Account" onClose={onClose} footer={<button className="ev-btn ev-btn-primary" onClick={onClose}>Done</button>}>
        <div className="glass" style={{ padding: "10px 14px", borderRadius: 12, display: "flex", gap: 10, alignItems: "center", marginBottom: 18 }}>
          <I3.Warn size={16} style={{ color: "var(--ev-warn)" }} />
          <span className="t-sm" style={{ color: "var(--ink-2)" }}>Single-user mode — API keys are stored unencrypted in local SQLite.</span>
        </div>
        <Field label="Appearance">
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 6, padding: 4, background: "var(--glass-1)", borderRadius: 12, border: "1px solid var(--glass-border)" }}>
            {[["System", "system"], ["Light", "light"], ["Dark", "dark"]].map(([l, v]) => (
              <button key={v} onClick={() => setMode(v)} style={{ padding: "8px 10px", borderRadius: 9, fontFamily: "inherit", fontSize: 13, fontWeight: 500, background: mode === v ? "var(--glass-3)" : "transparent", color: mode === v ? "var(--ink-1)" : "var(--ink-3)", border: mode === v ? "1px solid var(--glass-border)" : "1px solid transparent", cursor: "pointer" }}>{l}</button>
            ))}
          </div>
        </Field>
        <Field label="AI features">
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "10px 14px", background: "var(--glass-1)", borderRadius: 12, border: "1px solid var(--glass-border)" }}>
            <div>
              <div style={{ fontSize: 14, fontWeight: 500 }}>AI features</div>
              <div className="t-sm" style={{ color: "var(--ink-3)" }}>Auto-categorize, parse statements, enable chat.</div>
            </div>
            <Toggle on={ai} onChange={() => setAi(!ai)} />
          </div>
        </Field>
        <Field label="API keys">
          {[["Anthropic", "Env", "sk-ant-…masked…"], ["OpenAI", "Not set", ""], ["Google", "Not set", ""]].map(([p, badge, v]) => (
            <div key={p} style={{ marginBottom: 10 }}>
              <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 6, display: "flex", alignItems: "center", gap: 8 }}>
                {p}
                <span style={{ fontSize: 10, padding: "2px 8px", borderRadius: 999, background: badge === "Env" ? "color-mix(in srgb, var(--ev-pos) 18%, transparent)" : "var(--glass-3)", color: badge === "Env" ? "var(--ev-pos)" : "var(--ink-3)" }}>{badge}</span>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "0 12px", height: 38, borderRadius: 10, background: "var(--glass-1)", border: "1px solid var(--glass-border)" }}>
                <input type={show[p] ? "text" : "password"} defaultValue={v} placeholder={`Paste ${p} API key…`} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--ink-1)", fontFamily: "var(--ev-font-mono)", fontSize: 12 }} />
                <button onClick={() => setShow(s => ({ ...s, [p]: !s[p] }))} style={{ width: 28, height: 28, borderRadius: 8, border: "none", background: "transparent", color: "var(--ink-3)", cursor: "pointer", display: "grid", placeItems: "center" }}>
                  {show[p] ? <I3.EyeOff size={14} /> : <I3.Eye size={14} />}
                </button>
              </div>
            </div>
          ))}
        </Field>
        <Field label="Feature flags">
          <FlagRow label="Widgets" desc="Enable saved dashboards" defaultOn />
          <FlagRow label="Forecast lines" desc="Show dashed forecast on charts" defaultOn />
        </Field>
        <Field label="AI spend">
          <div style={{ padding: 14, borderRadius: 12, background: "var(--glass-1)", border: "1px solid var(--glass-border)" }}>
            <div className="t-sm" style={{ color: "var(--ink-3)" }}>Cumulative</div>
            <div className="tab-num" style={{ fontSize: 22, fontWeight: 600, background: "var(--accent-grad)", WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent" }}>$4.27</div>
          </div>
        </Field>
      </ModalShell>
    </Backdrop>
  );
}

const CAT_SWATCHES = ["var(--cat-1)", "var(--cat-2)", "var(--cat-3)", "var(--cat-4)", "var(--cat-5)", "var(--cat-6)", "var(--cat-7)", "var(--cat-8)", "var(--cat-9)", "var(--cat-10)", "var(--cat-11)", "var(--cat-12)"];

function CategoryModal({ onClose, cat }) {
  const [color, setColor] = useState3(cat ? cat.color : "var(--cat-4)");
  return (
    <Backdrop onClose={onClose}>
      <ModalShell title={cat ? "Edit category" : "New category"} onClose={onClose} footer={<><button className="ev-btn ev-btn-secondary" onClick={onClose}>Cancel</button><button className="ev-btn ev-btn-primary" onClick={onClose}>{cat ? "Save" : "Create category"}</button></>}>
        <Field label="Name"><Input placeholder="e.g. Subscriptions" defaultValue={cat ? cat.name : ""} /></Field>
        <Field label="Description">
          <textarea defaultValue={cat ? cat.desc : ""} placeholder="What kinds of expenses belong here?" style={{ width: "100%", minHeight: 76, padding: 12, borderRadius: 12, background: "var(--glass-1)", border: "1px solid var(--glass-border)", color: "var(--ink-1)", fontFamily: "inherit", fontSize: 14, outline: "none", resize: "vertical" }} />
          <div className="t-sm" style={{ color: "var(--ink-3)", marginTop: 6 }}>Helps the AI assistant file expenses correctly.</div>
        </Field>
        <Field label="Color">
          <div style={{ display: "grid", gridTemplateColumns: "repeat(6, 1fr)", gap: 10 }}>
            {CAT_SWATCHES.map(c => (
              <button key={c} onClick={() => setColor(c)} style={{ aspectRatio: "1", borderRadius: 14, background: c, border: color === c ? "2px solid var(--ink-1)" : "1px solid var(--glass-border)", cursor: "pointer", boxShadow: color === c ? `0 0 0 3px var(--glass-2), 0 8px 24px -6px ${c}` : "none", transition: "transform 0.1s", transform: color === c ? "scale(1.05)" : "scale(1)" }} />
            ))}
          </div>
        </Field>
        <Field label="Parent category">
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 14px", height: 42, borderRadius: 12, background: "var(--glass-1)", border: "1px solid var(--glass-border)" }}>
            <span style={{ fontSize: 14 }}>— None —</span>
            <I3.ChevronDown size={14} style={{ color: "var(--ink-3)" }} />
          </div>
        </Field>
      </ModalShell>
    </Backdrop>
  );
}

function TxModal({ onClose, tx }) {
  return (
    <Backdrop onClose={onClose}>
      <ModalShell title="Edit transaction" onClose={onClose} footer={<><button className="ev-btn ev-btn-ghost" style={{ color: "#fb7185", marginRight: "auto" }}>Delete</button><button className="ev-btn ev-btn-secondary" onClick={onClose}>Cancel</button><button className="ev-btn ev-btn-primary" onClick={onClose}>Save</button></>}>
        <Field label="Merchant"><Input defaultValue={tx ? tx.m : "Trader Joe's"} /></Field>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          <Field label="Date"><Input defaultValue={tx ? tx.d : "2026-05-08"} icon={<I3.Calendar size={14} />} /></Field>
          <Field label="Amount"><Input defaultValue={tx ? tx.a.toFixed(2) : "82.40"} icon={<span style={{ fontFamily: "var(--ev-font-mono)" }}>$</span>} /></Field>
        </div>
        <Field label="Category">
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {U3.CATS.filter(c => !c.parent).slice(0, 8).map(c => (
              <button key={c.id} className="ev-chip" style={{ cursor: "pointer", fontFamily: "inherit" }}>
                <span className="cat-dot" style={{ background: c.color, width: 8, height: 8 }} /> {c.name}
              </button>
            ))}
          </div>
        </Field>
        <Field label="Notes">
          <textarea placeholder="Optional note…" style={{ width: "100%", minHeight: 60, padding: 12, borderRadius: 12, background: "var(--glass-1)", border: "1px solid var(--glass-border)", color: "var(--ink-1)", fontFamily: "inherit", fontSize: 14, outline: "none" }} />
        </Field>
      </ModalShell>
    </Backdrop>
  );
}

function AddWidgetDrawer({ onClose }) {
  const [type, setType] = useState3("Time series");
  const types = ["Time series", "Bar", "Pie", "Big number", "Table", "Treemap"];
  return (
    <Backdrop onClose={onClose} align="flex-start">
      <ModalShell title="Add widget" onClose={onClose} footer={<><button className="ev-btn ev-btn-secondary" onClick={onClose}>Cancel</button><button className="ev-btn ev-btn-primary" onClick={onClose}>Add widget</button></>}>
        <Field label="Preview">
          <div className="glass" style={{ borderRadius: 14, padding: 14, height: 180 }}>
            {type === "Time series" && <window.EVScreens2.Sparkline />}
            {type === "Bar" && <window.EVScreens2.BarChart />}
            {type === "Pie" && <window.EVScreens2.Donut />}
            {type === "Big number" && <div style={{ height: "100%", display: "grid", placeItems: "center" }}><div className="tab-num" style={{ fontSize: 36, fontWeight: 600, background: "var(--accent-grad)", WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent" }}>$2,593.92</div></div>}
            {(type === "Table" || type === "Treemap") && <div style={{ height: "100%", display: "grid", placeItems: "center", color: "var(--ink-3)", fontSize: 12 }}>{type} preview</div>}
          </div>
        </Field>
        <Field label="Widget type">
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {types.map(t => (
              <button key={t} onClick={() => setType(t)} className={"ev-chip " + (t === type ? "ev-chip-active" : "")} style={{ cursor: "pointer", fontFamily: "inherit" }}>{t}</button>
            ))}
          </div>
        </Field>
        <div style={{ padding: 12, borderRadius: 12, background: "var(--glass-1)", border: "1px solid var(--glass-border)", marginBottom: 14, fontSize: 13, color: "var(--ink-2)", lineHeight: 1.5 }}>A line chart over time. Best for spotting trends and seasonality.</div>
        <Field label="Metric"><Input defaultValue="Spend over time" icon={<I3.ChevronDown size={14} />} /></Field>
        <Field label="Rollup period"><Input defaultValue="Day" icon={<I3.ChevronDown size={14} />} /></Field>
      </ModalShell>
    </Backdrop>
  );
}

function DashSwitcher({ onClose }) {
  return (
    <Backdrop onClose={onClose} align="flex-start">
      <div style={{ marginTop: 60, width: "100%", maxWidth: 420 }} className="glass-strong">
        <div style={{ borderRadius: 18, padding: 8 }}>
          <div style={{ padding: "8px 12px 6px", fontSize: 11, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--ink-3)" }}>Switch dashboard</div>
          {[["My Widgets", true], ["Travel ‘26", false], ["Subscriptions audit", false]].map(([n, active]) => (
            <button key={n} onClick={onClose} style={{ width: "100%", padding: "10px 12px", display: "flex", alignItems: "center", gap: 10, background: active ? "var(--glass-2)" : "transparent", border: "none", borderRadius: 10, cursor: "pointer", color: "var(--ink-1)", fontFamily: "inherit", fontSize: 14, textAlign: "left" }}>
              <span style={{ width: 28, height: 28, borderRadius: 8, background: active ? "var(--accent-grad)" : "var(--glass-3)", display: "grid", placeItems: "center", color: active ? "white" : "var(--ink-2)" }}>
                <I3.Chart size={13} />
              </span>
              <span style={{ flex: 1, fontWeight: active ? 600 : 400 }}>{n}</span>
              {active && <I3.Check size={14} style={{ color: "var(--accent)" }} />}
            </button>
          ))}
          <div style={{ padding: 6 }}>
            <button onClick={onClose} className="ev-btn ev-btn-primary" style={{ width: "100%" }}><I3.Plus size={14} /> New dashboard</button>
          </div>
        </div>
      </div>
    </Backdrop>
  );
}

function ImportModal({ onClose, state = "idle", setState }) {
  return (
    <Backdrop onClose={onClose}>
      <ModalShell title="Import statement" onClose={onClose} footer={
        state === "review" ? (<><button className="ev-btn ev-btn-secondary" onClick={onClose}>Cancel</button><button className="ev-btn ev-btn-primary" onClick={() => setState("success")}>Confirm 12 rows</button></>)
        : state === "success" || state === "error" ? (<button className="ev-btn ev-btn-primary" onClick={onClose}>Done</button>) : null
      }>
        {state === "idle" && (
          <div className="glass" style={{ borderRadius: 18, padding: "36px 20px", textAlign: "center", borderStyle: "dashed" }}>
            <div style={{ width: 64, height: 64, borderRadius: 18, background: "var(--accent-grad)", margin: "0 auto 16px", display: "grid", placeItems: "center", color: "white", boxShadow: "0 14px 36px -10px var(--accent)" }}><I3.Upload size={26} /></div>
            <div className="t-h3" style={{ marginBottom: 6 }}>Drop a statement here</div>
            <div className="t-sm" style={{ color: "var(--ink-3)", marginBottom: 14 }}>CSV, PDF or image · parsed by AI</div>
            <button className="ev-btn ev-btn-secondary" onClick={() => setState("hover")}>Show drop state →</button>
          </div>
        )}
        {state === "hover" && (
          <div className="glass" style={{ borderRadius: 18, padding: "36px 20px", textAlign: "center", borderStyle: "dashed", borderColor: "var(--accent)", background: "color-mix(in srgb, var(--accent) 8%, var(--glass-1))" }}>
            <div style={{ width: 64, height: 64, borderRadius: 18, background: "var(--accent-grad)", margin: "0 auto 16px", display: "grid", placeItems: "center", color: "white", boxShadow: "0 0 40px var(--accent)" }}><I3.Upload size={26} /></div>
            <div className="t-h3" style={{ marginBottom: 6, color: "var(--accent)" }}>Release to upload</div>
            <div className="t-sm" style={{ color: "var(--ink-2)", marginBottom: 14 }}>statement-april-2026.pdf · 142 KB</div>
            <button className="ev-btn ev-btn-primary" onClick={() => setState("parsing")}>Continue →</button>
          </div>
        )}
        {state === "parsing" && (
          <div style={{ padding: "20px 0", textAlign: "center" }}>
            <div className="glass" style={{ width: 64, height: 64, borderRadius: 18, margin: "0 auto 18px", display: "grid", placeItems: "center", color: "var(--accent)" }}><I3.Sparkle size={28} /></div>
            <div className="t-h3" style={{ marginBottom: 6 }}>Parsing statement…</div>
            <div className="t-sm" style={{ color: "var(--ink-3)", marginBottom: 18 }}>AI is extracting rows.</div>
            <div style={{ height: 6, borderRadius: 999, background: "var(--glass-2)", overflow: "hidden", marginBottom: 12 }}>
              <div style={{ height: "100%", width: "62%", background: "var(--accent-grad)", borderRadius: 999, boxShadow: "0 0 10px var(--accent)" }} />
            </div>
            <div className="tab-num t-sm" style={{ color: "var(--ink-3)" }}>8 / 12 rows · $0.04 spent</div>
            <button onClick={() => setState("review")} className="ev-btn ev-btn-ghost" style={{ marginTop: 14 }}>Skip to review →</button>
          </div>
        )}
        {state === "review" && (
          <div>
            <div className="t-body" style={{ marginBottom: 12, color: "var(--ink-2)" }}>Review 12 rows before commit. <strong>2</strong> need a category.</div>
            <div className="glass" style={{ borderRadius: 12, padding: 0, overflow: "hidden" }}>
              {[["Apr 04", "UBER *TRIP", null, 70.37], ["Apr 05", "Netflix.com", "Subscriptions", 15.14], ["Apr 05", "DoorDash", "Dining Out", 66.45], ["Apr 07", "PayPal", null, 14.12], ["Apr 15", "Lyft *Ride", "Travel", 93.81]].map((r, i) => (
                <div key={i} style={{ display: "grid", gridTemplateColumns: "60px 1fr 110px 70px", padding: "8px 12px", alignItems: "center", fontSize: 12, borderBottom: i < 4 ? "1px solid var(--glass-border)" : "none", fontFamily: "var(--ev-font-mono)", color: "var(--ink-2)" }}>
                  <span>{r[0]}</span>
                  <span style={{ fontFamily: "var(--ev-font)", color: "var(--ink-1)" }}>{r[1]}</span>
                  <span style={{ fontFamily: "var(--ev-font)" }}>{r[2] ? <span style={{ color: "var(--ink-2)" }}>{r[2]}</span> : <span style={{ color: "var(--ev-warn)", display: "inline-flex", gap: 4, alignItems: "center", fontSize: 11 }}><I3.Warn size={10} /> Needs cat</span>}</span>
                  <span style={{ textAlign: "right", color: "var(--ink-1)" }}>${r[3].toFixed(2)}</span>
                </div>
              ))}
            </div>
            <div className="t-sm" style={{ color: "var(--ink-3)", textAlign: "center", padding: "8px 0" }}>+ 7 more rows</div>
          </div>
        )}
        {state === "success" && (
          <div style={{ padding: "16px 0", textAlign: "center" }}>
            <div style={{ width: 72, height: 72, borderRadius: 999, background: "color-mix(in srgb, var(--ev-pos) 20%, transparent)", margin: "0 auto 18px", display: "grid", placeItems: "center", color: "var(--ev-pos)", border: "1px solid color-mix(in srgb, var(--ev-pos) 50%, transparent)" }}><I3.Check size={32} /></div>
            <div className="t-h2" style={{ marginBottom: 8 }}>Imported</div>
            <div className="t-body" style={{ color: "var(--ink-3)", marginBottom: 18 }}>April 2026 statement processed.</div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
              {[["Rows", "12"], ["Auto-cat", "10"], ["Dupes", "2"]].map(([l, v]) => (
                <div key={l} className="glass" style={{ padding: 12, borderRadius: 12 }}>
                  <div className="t-sm" style={{ color: "var(--ink-3)" }}>{l}</div>
                  <div className="tab-num" style={{ fontSize: 20, fontWeight: 600 }}>{v}</div>
                </div>
              ))}
            </div>
          </div>
        )}
        {state === "error" && (
          <div style={{ padding: "16px 0", textAlign: "center" }}>
            <div style={{ width: 72, height: 72, borderRadius: 999, background: "color-mix(in srgb, var(--ev-neg) 20%, transparent)", margin: "0 auto 18px", display: "grid", placeItems: "center", color: "var(--ev-neg)", border: "1px solid color-mix(in srgb, var(--ev-neg) 50%, transparent)" }}><I3.X size={32} /></div>
            <div className="t-h2" style={{ marginBottom: 8 }}>Couldn't parse</div>
            <div className="t-body" style={{ color: "var(--ink-3)", marginBottom: 14 }}>The file format wasn't recognized. We support CSV, PDF, or images.</div>
            <button className="ev-btn ev-btn-secondary">Try another file</button>
          </div>
        )}
      </ModalShell>
    </Backdrop>
  );
}

window.EVModals = { AccountModal, CategoryModal, TxModal, AddWidgetDrawer, DashSwitcher, ImportModal };
