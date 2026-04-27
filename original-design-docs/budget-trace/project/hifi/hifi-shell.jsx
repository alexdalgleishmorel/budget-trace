// Hi-fi shared shell: phone/desktop frames, status bar, headers, nav, modal glass overlay.

function StatusBar({ mode = 'light' }) {
  return (
    <div style={{
      position: 'relative',
      height: 44,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '0 28px 0 28px',
      fontFamily: 'var(--font-text)',
      fontWeight: 600,
      fontSize: 15,
      color: 'var(--ink)',
      flexShrink: 0,
    }}>
      <span className="num" style={{ letterSpacing: 0 }}>9:41</span>
      {/* Dynamic island */}
      <div style={{
        position: 'absolute', left: '50%', top: 10, transform: 'translateX(-50%)',
        width: 118, height: 34, borderRadius: 20,
        background: '#000',
      }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        {/* signal */}
        <svg width="18" height="11" viewBox="0 0 18 11" fill="currentColor">
          <rect x="0"  y="7" width="3" height="4" rx="1"/>
          <rect x="5"  y="5" width="3" height="6" rx="1"/>
          <rect x="10" y="2" width="3" height="9" rx="1"/>
          <rect x="15" y="0" width="3" height="11" rx="1"/>
        </svg>
        {/* wifi */}
        <svg width="16" height="11" viewBox="0 0 16 11" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
          <path d="M1 4.5a11 11 0 0 1 14 0"/>
          <path d="M3.5 7a7 7 0 0 1 9 0"/>
          <path d="M6 9.5a3 3 0 0 1 4 0"/>
        </svg>
        {/* battery */}
        <svg width="27" height="12" viewBox="0 0 27 12" fill="none">
          <rect x="0.5" y="0.5" width="22" height="11" rx="3" stroke="currentColor" strokeOpacity="0.4"/>
          <rect x="2"   y="2"   width="19" height="8"  rx="1.5" fill="currentColor"/>
          <rect x="23.5" y="4" width="1.5" height="4" rx="0.5" fill="currentColor" fillOpacity="0.4"/>
        </svg>
      </div>
    </div>
  );
}

function HomeIndicator() {
  return (
    <div style={{
      height: 34, display: 'flex', alignItems: 'flex-end',
      justifyContent: 'center', paddingBottom: 8, flexShrink: 0,
    }}>
      <div style={{
        width: 134, height: 5, borderRadius: 3,
        background: 'var(--ink)', opacity: 0.85,
      }} />
    </div>
  );
}

function PhoneFrameHF({ mode, children, label }) {
  return (
    <div className={'bt theme-' + mode} style={{ position: 'relative' }}>
      {label && (
        <div style={{
          position: 'absolute', top: -28, left: 0, fontSize: 11,
          textTransform: 'uppercase', letterSpacing: 0.14, color: 'var(--ink-4)',
          fontFamily: 'var(--font-text)', fontWeight: 500,
        }}>
          {label}
        </div>
      )}
      <div className="frame-phone" style={{ color: 'var(--ink)' }}>
        {children}
      </div>
    </div>
  );
}

function DesktopFrameHF({ mode, children, label }) {
  return (
    <div className={'bt theme-' + mode} style={{ position: 'relative' }}>
      {label && (
        <div style={{
          position: 'absolute', top: -28, left: 0, fontSize: 11,
          textTransform: 'uppercase', letterSpacing: 0.14, color: 'var(--ink-4)',
          fontFamily: 'var(--font-text)', fontWeight: 500,
        }}>
          {label}
        </div>
      )}
      <div className="frame-desktop" style={{ color: 'var(--ink)' }}>
        {children}
      </div>
    </div>
  );
}

/* ========== Desktop window chrome ========== */

function WindowTitleBar({ title, right }) {
  return (
    <div style={{
      height: 40, flexShrink: 0,
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '0 14px',
      borderBottom: '1px solid var(--rule)',
      background: 'var(--surface-glass)',
      backdropFilter: 'saturate(140%) blur(12px)',
    }}>
      <div style={{ display: 'flex', gap: 6 }}>
        <span style={{ width: 12, height: 12, borderRadius: 999, background: '#FF5F57' }} />
        <span style={{ width: 12, height: 12, borderRadius: 999, background: '#FEBC2E' }} />
        <span style={{ width: 12, height: 12, borderRadius: 999, background: '#28C840' }} />
      </div>
      <div style={{
        flex: 1, textAlign: 'center',
        fontSize: 12.5, fontWeight: 500, color: 'var(--ink-3)',
        letterSpacing: -0.005,
      }}>
        {title}
      </div>
      <div style={{ width: 54, display: 'flex', justifyContent: 'flex-end', gap: 4 }}>
        {right}
      </div>
    </div>
  );
}

/* ========== Mobile top bar ========== */

function MobileHeaderHF({ title, left, right, subtitle }) {
  return (
    <div style={{
      flexShrink: 0,
      padding: '8px 18px 14px',
      display: 'flex',
      flexDirection: 'column',
      gap: 4,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        height: 40,
      }}>
        <div style={{ width: 72, display: 'flex', justifyContent: 'flex-start' }}>{left}</div>
        <div className="display" style={{
          fontSize: 17, fontWeight: 600,
        }}>{title}</div>
        <div style={{ width: 72, display: 'flex', justifyContent: 'flex-end', gap: 2 }}>{right}</div>
      </div>
      {subtitle}
    </div>
  );
}

/* ========== Desktop side nav ========== */

function DesktopSideNav({ current, onNav }) {
  const items = [
    ['plan', 'Plan'],
    ['expenses', 'Expenses'],
    ['results', 'Results'],
    ['summary', 'Summary'],
  ];
  return (
    <nav style={{
      width: 212,
      flexShrink: 0,
      borderRight: '1px solid var(--rule)',
      padding: '22px 14px',
      display: 'flex', flexDirection: 'column', gap: 2,
      background: 'var(--bg)',
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10, padding: '0 8px 18px',
      }}>
        <div style={{
          width: 26, height: 26, borderRadius: 8,
          background: 'var(--ink)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: 'var(--bg)',
          fontFamily: 'var(--font-display)', fontWeight: 700,
          fontSize: 13, letterSpacing: -0.02,
        }}>
          BT
        </div>
        <div style={{ fontFamily: 'var(--font-display)', fontSize: 15, fontWeight: 600, letterSpacing: -0.015 }}>
          Budget Trace
        </div>
      </div>

      {items.map(([id, label]) => {
        const active = id === current;
        return (
          <button
            key={id}
            onClick={() => onNav && onNav(id)}
            style={{
              display: 'flex', alignItems: 'center', gap: 11,
              padding: '9px 10px',
              borderRadius: 10,
              background: active ? 'var(--surface-2)' : 'transparent',
              border: active ? '1px solid var(--rule)' : '1px solid transparent',
              color: active ? 'var(--ink)' : 'var(--ink-3)',
              fontSize: 13.5,
              fontWeight: active ? 500 : 400,
              cursor: 'pointer',
              textAlign: 'left',
              transition: 'background var(--dur-fast) var(--ease)',
            }}
            onMouseEnter={(e) => { if (!active) e.currentTarget.style.background = 'var(--surface-2)'; }}
            onMouseLeave={(e) => { if (!active) e.currentTarget.style.background = 'transparent'; }}
          >
            <Icon name={id} size={18} stroke={1.6} />
            <span>{label}</span>
          </button>
        );
      })}

      <div style={{ marginTop: 'auto', padding: '8px 10px' }}>
        <div className="label">Cycle</div>
        <div style={{ fontSize: 13, marginTop: 4 }}>March 2025</div>
        <div className="label num" style={{ marginTop: 8 }}>Net income</div>
        <div className="num" style={{ fontSize: 17, marginTop: 2, fontWeight: 500 }}>$5,400</div>
      </div>
    </nav>
  );
}

/* ========== Bottom tab bar (mobile) ========== */

function BottomTabsHF({ current, onNav }) {
  const items = [
    ['plan', 'Plan'],
    ['expenses', 'Expenses'],
    ['results', 'Results'],
    ['summary', 'Summary'],
  ];
  return (
    <div style={{ flexShrink: 0, padding: '0 12px 8px' }}>
      <div className="glass" style={{
        display: 'flex',
        padding: 6,
        borderRadius: 20,
        gap: 2,
      }}>
        {items.map(([id, label]) => {
          const active = id === current;
          return (
            <button key={id} onClick={() => onNav && onNav(id)} style={{
              flex: 1,
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2,
              padding: '7px 4px',
              background: active ? 'var(--surface)' : 'transparent',
              border: '1px solid ' + (active ? 'var(--rule)' : 'transparent'),
              borderRadius: 14,
              cursor: 'pointer',
              color: active ? 'var(--ink)' : 'var(--ink-4)',
              boxShadow: active ? 'var(--shadow-1)' : 'none',
            }}>
              <Icon name={id} size={18} stroke={1.6} />
              <span style={{
                fontSize: 10.5,
                fontWeight: active ? 600 : 500,
                letterSpacing: 0.01,
              }}>{label}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

/* ========== Breadcrumbs ========== */

function Crumbs({ path, onJump, align = 'left' }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 6,
      fontSize: 13, color: 'var(--ink-3)',
      flexWrap: 'wrap',
    }}>
      {path.map((p, i) => {
        const isLast = i === path.length - 1;
        return (
          <React.Fragment key={i}>
            {i > 0 && (
              <span style={{ color: 'var(--ink-5)', display: 'inline-flex' }}>
                <Icon name="chevron-right" size={13} stroke={2} />
              </span>
            )}
            <span
              onClick={() => !isLast && onJump && onJump(i)}
              style={{
                cursor: isLast ? 'default' : 'pointer',
                color: isLast ? 'var(--ink)' : 'var(--ink-3)',
                fontWeight: isLast ? 600 : 400,
              }}>
              {p.label}
            </span>
          </React.Fragment>
        );
      })}
    </div>
  );
}

/* ========== Glass modal overlay ========== */

function ModalHF({ children, onClose, width = 440 }) {
  return (
    <div
      onClick={onClose}
      style={{
        position: 'absolute', inset: 0, zIndex: 100,
        background: 'rgba(10, 8, 4, 0.32)',
        backdropFilter: 'blur(6px)',
        WebkitBackdropFilter: 'blur(6px)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 20,
      }}>
      <div
        onClick={(e) => e.stopPropagation()}
        className="glass-strong"
        style={{
          background: 'var(--surface)',
          borderRadius: 22,
          width: '100%',
          maxWidth: width,
          maxHeight: '90%',
          display: 'flex', flexDirection: 'column',
          boxShadow: 'var(--shadow-pop)',
          overflow: 'hidden',
        }}>
        {children}
      </div>
    </div>
  );
}

/* ========== Section label (2x2 grid backplates) ========== */

function VariantGroup({ title, sub, children }) {
  return (
    <section style={{
      marginBottom: 80,
    }}>
      <div style={{
        marginBottom: 32,
        paddingBottom: 20,
        borderBottom: '1px solid rgba(18, 17, 16, 0.08)',
      }}>
        <div style={{
          fontSize: 11, textTransform: 'uppercase', letterSpacing: 0.14,
          color: 'rgba(18,17,16,0.5)',
          fontFamily: 'var(--font-text)', fontWeight: 500, marginBottom: 6,
        }}>
          Screen
        </div>
        <h2 style={{
          fontFamily: 'var(--font-display)',
          fontSize: 32, fontWeight: 600, letterSpacing: -0.025,
          margin: 0, color: '#0C0B09',
        }}>
          {title}
        </h2>
        {sub && <div style={{
          fontSize: 14, color: 'rgba(18,17,16,0.55)', marginTop: 6, maxWidth: 640,
        }}>{sub}</div>}
      </div>
      {children}
    </section>
  );
}

function VariantCell({ mode, device, children }) {
  const isDark = mode === 'dark';
  return (
    <div style={{
      background: isDark ? '#0C0B09' : '#F6F3EC',
      borderRadius: 24,
      padding: device === 'phone' ? '56px 40px' : '48px 40px',
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 20,
      border: isDark ? '1px solid rgba(240,236,226,0.08)' : '1px solid rgba(18,17,16,0.06)',
    }}>
      <div style={{
        fontSize: 10.5, textTransform: 'uppercase', letterSpacing: 0.14,
        fontFamily: '-apple-system, "SF Pro Text", system-ui',
        fontWeight: 500,
        color: isDark ? 'rgba(240,236,226,0.5)' : 'rgba(18,17,16,0.48)',
      }}>
        {device} · {mode}
      </div>
      {children}
    </div>
  );
}

Object.assign(window, {
  StatusBar, HomeIndicator, PhoneFrameHF, DesktopFrameHF,
  WindowTitleBar, MobileHeaderHF, DesktopSideNav, BottomTabsHF,
  Crumbs, ModalHF, VariantGroup, VariantCell,
});
