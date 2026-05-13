/* global React, EVIcons */
// Device chrome wrappers — pure presentational frames.

const { Fragment } = React;

// MOBILE — iPhone-ish frame, 390 wide
function PhoneFrame({ width = 390, height = 844, palette, mode, children, label }) {
  return (
    <div style={{
      width, height,
      borderRadius: 48,
      background: "linear-gradient(160deg, #1a1a22, #0a0a10)",
      padding: 8,
      boxShadow: "0 40px 80px -20px rgba(0,0,0,0.6), inset 0 0 0 1px rgba(255,255,255,0.06)",
      position: "relative",
    }}>
      <div
        className="ev-surface"
        data-palette={palette}
        data-mode={mode}
        style={{
          width: "100%",
          height: "100%",
          borderRadius: 40,
          overflow: "hidden",
          position: "relative",
        }}
      >
        <span className="ev-orb-c" />
        {/* Status bar */}
        <div className="ev-content" style={{ height: "100%", display: "flex", flexDirection: "column" }}>
          <div style={{
            height: 48,
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            padding: "0 28px",
            paddingTop: 14,
            position: "relative",
            zIndex: 2,
          }}>
            <span className="tab-num" style={{ fontSize: 15, fontWeight: 600, color: "var(--ink-1)" }}>9:41</span>
            {/* Notch */}
            <div style={{
              position: "absolute",
              top: 8,
              left: "50%",
              transform: "translateX(-50%)",
              width: 110,
              height: 30,
              background: "#000",
              borderRadius: 999,
            }} />
            <div style={{ display: "flex", gap: 6, alignItems: "center", color: "var(--ink-1)" }}>
              <div style={{ width: 16, height: 10, border: "1px solid currentColor", borderRadius: 2, position: "relative" }}>
                <div style={{ position: "absolute", inset: 1, background: "currentColor", borderRadius: 1, width: "75%" }} />
              </div>
            </div>
          </div>
          <div style={{ flex: 1, minHeight: 0, position: "relative" }}>{children}</div>
        </div>
      </div>
    </div>
  );
}

// DESKTOP — macOS-ish window frame, 1280 wide
function DesktopFrame({ width = 1280, height = 800, palette, mode, children, title = "Expense Visualizer" }) {
  return (
    <div style={{
      width, height,
      borderRadius: 16,
      background: "#1a1a22",
      padding: 0,
      boxShadow: "0 40px 80px -20px rgba(0,0,0,0.5), inset 0 0 0 1px rgba(255,255,255,0.06)",
      overflow: "hidden",
      position: "relative",
    }}>
      {/* Title bar */}
      <div style={{
        height: 38,
        display: "flex",
        alignItems: "center",
        padding: "0 14px",
        gap: 8,
        background: "#0d0d14",
        borderBottom: "1px solid rgba(255,255,255,0.06)",
      }}>
        <div style={{ display: "flex", gap: 7 }}>
          <div style={{ width: 12, height: 12, borderRadius: 999, background: "#ff5f57" }} />
          <div style={{ width: 12, height: 12, borderRadius: 999, background: "#febc2e" }} />
          <div style={{ width: 12, height: 12, borderRadius: 999, background: "#28c840" }} />
        </div>
        <div style={{ flex: 1, textAlign: "center", color: "rgba(255,255,255,0.4)", fontSize: 12, fontWeight: 500 }}>{title}</div>
        <div style={{ width: 52 }} />
      </div>
      <div
        className="ev-surface"
        data-palette={palette}
        data-mode={mode}
        style={{ width: "100%", height: height - 38, position: "relative" }}
      >
        <span className="ev-orb-c" />
        <div className="ev-content">{children}</div>
      </div>
    </div>
  );
}

// Frame label badge
function FrameLabel({ children }) {
  return (
    <div style={{
      fontFamily: "var(--ev-font-mono, ui-monospace, monospace)",
      fontSize: 11,
      color: "rgba(255,255,255,0.5)",
      letterSpacing: "0.06em",
      textTransform: "uppercase",
      marginBottom: 12,
    }}>
      {children}
    </div>
  );
}

window.EVChrome = { PhoneFrame, DesktopFrame, FrameLabel };
