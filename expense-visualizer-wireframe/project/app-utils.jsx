/* global React, EVIcons */
// All in-app screens. Each <App> instance is a self-contained prototype
// (tabs switch, modals open) so a Mobile or Desktop frame can host one.

const { useState, useMemo } = React;
const I = window.EVIcons;

const CATS = [
  { id: "grocery", name: "Grocery", color: "var(--cat-1)", parent: null },
  { id: "dining", name: "Dining Out", color: "var(--cat-8)", parent: null },
  { id: "shopping", name: "Shopping", color: "var(--cat-4)", parent: null },
  { id: "car", name: "Car", color: "var(--cat-3)", parent: null },
  { id: "fun", name: "Fun", color: "var(--cat-5)", parent: null },
  { id: "travel", name: "Travel", color: "var(--cat-2)", parent: null },
  { id: "medical", name: "Medical", color: "var(--cat-7)", parent: null },
  { id: "subs", name: "Subscriptions", color: "var(--cat-12)", parent: null },
  { id: "day", name: "Day-to-Day", color: "var(--cat-11)", parent: null },
  { id: "gas", name: "Gas", color: "var(--cat-9)", parent: "car" },
  { id: "insurance", name: "Insurance", color: "var(--cat-6)", parent: "car" },
  { id: "streaming", name: "Streaming", color: "var(--cat-10)", parent: "subs" },
];

const TX = [
  { d: "May 02", m: "Trader Joe's #142", c: "grocery", a: 84.22 },
  { d: "May 02", m: "Blue Bottle Coffee", c: "dining", a: 7.5 },
  { d: "May 03", m: "Uniqlo", c: "shopping", a: 142.0 },
  { d: "May 04", m: "Shell Oil", c: "gas", a: 62.18 },
  { d: "May 05", m: "Netflix.com", c: "streaming", a: 15.49 },
  { d: "May 05", m: "Spotify Premium", c: "streaming", a: 11.99 },
  { d: "May 06", m: "Uber *Trip", c: null, a: 18.4 },
  { d: "May 07", m: "Local Farm Co-op", c: "grocery", a: 56.3 },
  { d: "May 08", m: "MUJI", c: "shopping", a: 38.0 },
  { d: "May 09", m: "Sushi Zen", c: "dining", a: 64.5 },
  { d: "May 10", m: "Geico Auto", c: "insurance", a: 120.0 },
  { d: "May 11", m: "DoorDash *Main", c: "dining", a: 32.8 },
];

const TAB_LIST = [
  { id: "categories", label: "Categories", icon: I.Grid },
  { id: "expenses", label: "Expenses", icon: I.List },
  { id: "widgets", label: "Widgets", icon: I.Chart },
  { id: "insights", label: "Insights", icon: I.Sparkle },
];

// ────────── REUSABLE BITS ──────────

function Brand({ size = 22 }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div style={{
        width: size + 6, height: size + 6,
        borderRadius: 10,
        background: "var(--accent-grad)",
        display: "grid", placeItems: "center",
        boxShadow: "inset 0 1px 0 rgba(255,255,255,0.3)",
      }}>
        <div style={{ width: 4, height: size - 6, background: "white", borderRadius: 99, transform: "rotate(0deg)", boxShadow: `4px 4px 0 white, 8px 0 0 white`, marginRight: 8 }} />
      </div>
      <div style={{ fontSize: 16, fontWeight: 600, letterSpacing: "-0.015em", color: "var(--ink-1)" }}>
        Expense<br /><span style={{ opacity: 0.65, fontWeight: 500 }}>Visualizer</span>
      </div>
    </div>
  );
}

function BrandCompact() {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
      <div style={{
        width: 26, height: 26,
        borderRadius: 8,
        background: "var(--accent-grad)",
        display: "grid", placeItems: "center",
        boxShadow: "inset 0 1px 0 rgba(255,255,255,0.3)",
        position: "relative",
      }}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.4" strokeLinecap="round">
          <path d="M4 18 L9 12 L13 16 L20 6" />
        </svg>
      </div>
      <span style={{ fontSize: 15, fontWeight: 600, letterSpacing: "-0.015em" }}>Expense Visualizer</span>
    </div>
  );
}

// Sidebar tab item (desktop)
function SidebarTab({ icon: Ic, label, active, onClick }) {
  return (
    <button
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: 12,
        height: 42, padding: "0 14px",
        borderRadius: 12,
        border: "1px solid transparent",
        background: active ? "var(--glass-2)" : "transparent",
        borderColor: active ? "var(--glass-border)" : "transparent",
        color: active ? "var(--ink-1)" : "var(--ink-2)",
        fontFamily: "inherit", fontSize: 14, fontWeight: active ? 600 : 500,
        cursor: "pointer", width: "100%", textAlign: "left",
        boxShadow: active ? "inset 0 1px 0 var(--glass-highlight)" : "none",
      }}
    >
      <Ic size={18} />
      {label}
    </button>
  );
}

// Mobile bottom-tab item
function MobileTab({ icon: Ic, label, active, onClick }) {
  return (
    <button onClick={onClick} style={{
      flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 4,
      padding: "6px 4px",
      background: "transparent", border: "none",
      color: active ? "var(--accent)" : "var(--ink-3)",
      fontFamily: "inherit", fontSize: 10, fontWeight: 500, cursor: "pointer",
    }}>
      <Ic size={22} sw={active ? 2 : 1.6} />
      <span style={{ letterSpacing: "-0.005em" }}>{label}</span>
    </button>
  );
}

// Glass card wrapper
function Card({ children, style, className = "glass", padding = 16, ...rest }) {
  return (
    <div className={className} style={{ padding, ...style }} {...rest}>
      {children}
    </div>
  );
}

// Section eyebrow label
function Eyebrow({ children, style }) {
  return <div className="t-xs" style={{ color: "var(--ink-3)", ...style }}>{children}</div>;
}

window.EVUtils = { CATS, TX, TAB_LIST, Brand, BrandCompact, SidebarTab, MobileTab, Card, Eyebrow };
