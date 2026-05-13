/* global React */
const IL = window.EVIcons;
const UL = window.EVUtils;
const { useState: useLoginState } = React;

function GoogleG({ size = 18 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ display: "block" }}>
      <path d="M21.6 12.2c0-.7-.1-1.4-.2-2H12v3.8h5.4c-.2 1.2-.9 2.3-2 3v2.5h3.2c1.9-1.7 3-4.3 3-7.3z" fill="#4285F4" />
      <path d="M12 22c2.7 0 5-.9 6.6-2.5L15.4 17c-.9.6-2 1-3.4 1-2.6 0-4.8-1.8-5.6-4.1H3.1v2.6C4.7 19.7 8.1 22 12 22z" fill="#34A853" />
      <path d="M6.4 13.9c-.2-.6-.3-1.2-.3-1.9s.1-1.3.3-1.9V7.5H3.1C2.4 8.9 2 10.4 2 12s.4 3.1 1.1 4.5l3.3-2.6z" fill="#FBBC05" />
      <path d="M12 6c1.5 0 2.8.5 3.8 1.5l2.9-2.9C16.9 2.9 14.7 2 12 2 8.1 2 4.7 4.3 3.1 7.5l3.3 2.6C7.2 7.8 9.4 6 12 6z" fill="#EA4335" />
    </svg>
  );
}

function GitHubMark({ size = 18 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" style={{ display: "block" }}>
      <path d="M12 .5a11.5 11.5 0 0 0-3.6 22.4c.6.1.8-.2.8-.6v-2.2c-3.2.7-3.9-1.4-3.9-1.4-.5-1.3-1.3-1.6-1.3-1.6-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.4 1 .1-.8.4-1.3.7-1.6-2.5-.3-5.2-1.3-5.2-5.7 0-1.3.4-2.3 1.2-3.2-.1-.3-.5-1.5.1-3.1 0 0 1-.3 3.2 1.2a11 11 0 0 1 5.8 0c2.2-1.5 3.2-1.2 3.2-1.2.6 1.6.2 2.8.1 3.1.8.9 1.2 1.9 1.2 3.2 0 4.4-2.7 5.4-5.3 5.7.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A11.5 11.5 0 0 0 12 .5z" />
    </svg>
  );
}

function LoginScreen({ variant = "signin", compact = false }) {
  const isSignup = variant === "signup";

  return (
    <div style={{
      height: "100%", width: "100%",
      display: "grid",
      gridTemplateColumns: compact ? "1fr" : "1.05fr 1fr",
      position: "relative",
    }}>
      {/* LEFT — brand stage (desktop only) */}
      {!compact && (
        <div style={{
          position: "relative",
          padding: "44px 48px",
          display: "flex", flexDirection: "column",
          color: "var(--ink-1)",
        }}>
          {/* Brand mark */}
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <div style={{
              width: 36, height: 36, borderRadius: 11,
              background: "var(--accent-grad)",
              display: "grid", placeItems: "center",
              boxShadow: "inset 0 1px 0 rgba(255,255,255,0.35), 0 8px 24px -8px var(--accent)",
            }}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.4" strokeLinecap="round">
                <path d="M4 18 L9 12 L13 16 L20 6" />
              </svg>
            </div>
            <div style={{ fontSize: 16, fontWeight: 600, letterSpacing: "-0.015em" }}>Expense Visualizer</div>
          </div>

          {/* Headline */}
          <div style={{ marginTop: "auto", marginBottom: "auto", maxWidth: 460 }}>
            <div style={{ fontSize: 11, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--ink-3)", marginBottom: 14 }}>
              Personal finance · single user
            </div>
            <div style={{ fontSize: 48, fontWeight: 600, lineHeight: 1.05, letterSpacing: "-0.025em", marginBottom: 18 }}>
              See where the money goes — and where it's headed.
            </div>
            <div style={{ fontSize: 15, color: "var(--ink-2)", lineHeight: 1.55, maxWidth: 380 }}>
              Drop statements in, let AI sort them, then build any dashboard you want. Your data stays local.
            </div>

            {/* feature pills */}
            <div style={{ display: "flex", gap: 8, marginTop: 28, flexWrap: "wrap" }}>
              {[
                ["Local-first", IL.Save],
                ["AI parsing", IL.Sparkle],
                ["Custom widgets", IL.Chart],
              ].map(([l, Ic]) => (
                <span key={l} className="ev-chip">
                  <Ic size={12} style={{ color: "var(--accent)" }} /> {l}
                </span>
              ))}
            </div>
          </div>

          {/* Footer */}
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, color: "var(--ink-3)" }}>
            <span>v 0.4 · 2026</span>
            <span>Privacy · Terms · Status</span>
          </div>

          {/* Decorative chart preview behind */}
          <div style={{
            position: "absolute", right: -60, bottom: 80,
            width: 280, height: 140,
            opacity: 0.35,
            pointerEvents: "none",
          }}>
            <svg viewBox="0 0 280 140" style={{ width: "100%", height: "100%" }}>
              <defs>
                <linearGradient id="login-line" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%" stopColor="var(--accent)" />
                  <stop offset="100%" stopColor="var(--accent-2)" />
                </linearGradient>
              </defs>
              <polyline points="0,100 30,80 60,90 90,55 120,70 150,40 180,60 210,30 240,45 280,20" fill="none" stroke="url(#login-line)" strokeWidth="2" strokeLinecap="round" />
            </svg>
          </div>
        </div>
      )}

      {/* RIGHT — form card */}
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "center",
        padding: compact ? "20px 18px" : 32,
      }}>
        <div className="glass-strong" style={{
          width: "100%",
          maxWidth: 400,
          padding: compact ? "28px 22px" : "32px 30px",
          borderRadius: 24,
        }}>
          {compact && (
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 24 }}>
              <div style={{
                width: 32, height: 32, borderRadius: 10, background: "var(--accent-grad)",
                display: "grid", placeItems: "center",
                boxShadow: "inset 0 1px 0 rgba(255,255,255,0.3)",
              }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.4" strokeLinecap="round">
                  <path d="M4 18 L9 12 L13 16 L20 6" />
                </svg>
              </div>
              <div style={{ fontSize: 15, fontWeight: 600, letterSpacing: "-0.015em" }}>Expense Visualizer</div>
            </div>
          )}

          <div style={{ fontSize: 24, fontWeight: 600, letterSpacing: "-0.015em" }}>
            {isSignup ? "Create your account" : "Welcome back"}
          </div>
          <div style={{ fontSize: 14, color: "var(--ink-3)", marginTop: 6, marginBottom: 28, lineHeight: 1.5 }}>
            {isSignup
              ? "Pick a provider — we'll use it to sign you in, nothing more."
              : "Sign in to continue to your dashboard."}
          </div>

          {/* OAuth — primary path */}
          <div style={{ display: "flex", flexDirection: "column", gap: 10, marginBottom: 22 }}>
            <button style={{
              height: 52, borderRadius: 14,
              background: "var(--glass-2)",
              border: "1px solid var(--glass-border-strong)",
              color: "var(--ink-1)",
              fontFamily: "inherit", fontSize: 15, fontWeight: 500,
              display: "flex", alignItems: "center", justifyContent: "center", gap: 12,
              cursor: "pointer",
              backdropFilter: "blur(20px) saturate(180%)",
              WebkitBackdropFilter: "blur(20px) saturate(180%)",
              boxShadow: "inset 0 1px 0 var(--glass-highlight), 0 8px 24px -12px rgba(0,0,0,0.3)",
              transition: "transform 0.15s ease",
            }}>
              <GoogleG size={20} /> Continue with Google
            </button>
            <button style={{
              height: 52, borderRadius: 14,
              background: "var(--glass-2)",
              border: "1px solid var(--glass-border-strong)",
              color: "var(--ink-1)",
              fontFamily: "inherit", fontSize: 15, fontWeight: 500,
              display: "flex", alignItems: "center", justifyContent: "center", gap: 12,
              cursor: "pointer",
              backdropFilter: "blur(20px) saturate(180%)",
              WebkitBackdropFilter: "blur(20px) saturate(180%)",
              boxShadow: "inset 0 1px 0 var(--glass-highlight), 0 8px 24px -12px rgba(0,0,0,0.3)",
              transition: "transform 0.15s ease",
            }}>
              <GitHubMark size={18} /> Continue with GitHub
            </button>
          </div>

          {/* Trust line */}
          <div style={{
            display: "flex", alignItems: "flex-start", gap: 8,
            padding: "10px 12px", borderRadius: 10,
            background: "var(--glass-1)",
            border: "1px solid var(--glass-border)",
            fontSize: 12, color: "var(--ink-3)", lineHeight: 1.5,
            marginBottom: 20,
          }}>
            <IL.Eye size={13} style={{ marginTop: 2, flexShrink: 0, color: "var(--ink-2)" }} />
            <span>We only read your email and name. We never touch your messages, repos, or files.</span>
          </div>

          <div style={{ textAlign: "center", fontSize: 12, color: "var(--ink-4)", lineHeight: 1.6 }}>
            By {isSignup ? "creating an account" : "signing in"} you agree to our{" "}
            <a style={{ color: "var(--ink-2)", textDecoration: "underline", textUnderlineOffset: 2 }}>Terms</a>
            {" "}and{" "}
            <a style={{ color: "var(--ink-2)", textDecoration: "underline", textUnderlineOffset: 2 }}>Privacy Policy</a>.
          </div>
        </div>
      </div>
    </div>
  );
}

function LoginField({ label, placeholder, defaultValue, type = "text", icon, trailing }) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ fontSize: 11, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--ink-3)", marginBottom: 6, fontWeight: 500 }}>{label}</div>
      <div style={{
        display: "flex", alignItems: "center", gap: 8,
        padding: "0 6px 0 14px", height: 44,
        borderRadius: 12,
        background: "var(--glass-1)",
        border: "1px solid var(--glass-border)",
        backdropFilter: "blur(20px) saturate(160%)",
        WebkitBackdropFilter: "blur(20px) saturate(160%)",
      }}>
        {icon && <span style={{ color: "var(--ink-3)", display: "grid", placeItems: "center" }}>{icon}</span>}
        <input type={type} defaultValue={defaultValue} placeholder={placeholder} style={{
          flex: 1, background: "transparent", border: "none", outline: "none",
          color: "var(--ink-1)", fontFamily: "inherit", fontSize: 14,
          padding: "0 4px",
        }} />
        {trailing}
      </div>
    </div>
  );
}

function Checkbox({ defaultChecked }) {
  const [on, setOn] = useLoginState(!!defaultChecked);
  return (
    <button onClick={() => setOn(!on)} style={{
      width: 18, height: 18, borderRadius: 5, flexShrink: 0,
      background: on ? "var(--accent-grad)" : "var(--glass-1)",
      border: on ? "none" : "1px solid var(--glass-border)",
      display: "grid", placeItems: "center", cursor: "pointer",
      boxShadow: on ? "0 4px 10px -2px var(--accent)" : "inset 0 1px 0 var(--glass-highlight)",
    }}>
      {on && (
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="4 12 10 18 20 6" />
        </svg>
      )}
    </button>
  );
}

window.EVLogin = { LoginScreen };
