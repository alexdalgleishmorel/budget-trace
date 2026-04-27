// Hi-fi icons — inline SVG in the Lucide style (24x24, 1.75 stroke)
// Using custom strokes tuned to match the refined look. Each is a pure component.

function Icon({ name, size = 20, stroke = 1.75, style, ...rest }) {
  const s = size;
  const common = {
    width: s, height: s, viewBox: '0 0 24 24',
    fill: 'none', stroke: 'currentColor',
    strokeWidth: stroke, strokeLinecap: 'round', strokeLinejoin: 'round',
    style,
    ...rest,
  };
  const paths = ICON_PATHS[name];
  if (!paths) return <svg {...common} />;
  return <svg {...common}>{paths}</svg>;
}

const ICON_PATHS = {
  // nav
  'plan':       (<><rect x="3" y="3" width="8" height="12" rx="2"/><rect x="13" y="3" width="8" height="7" rx="2"/><rect x="13" y="12" width="8" height="9" rx="2"/><rect x="3" y="17" width="8" height="4" rx="2"/></>),
  'expenses':   (<><path d="M4 5h16"/><path d="M4 12h16"/><path d="M4 19h10"/></>),
  'results':    (<><path d="M3 3v18h18"/><path d="M7 16l4-5 3 3 5-7"/></>),
  'summary':    (<><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>),
  'account':    (<><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></>),

  // actions
  'plus':       (<><path d="M12 5v14"/><path d="M5 12h14"/></>),
  'edit':       (<><path d="M17 3.5a2.1 2.1 0 1 1 3 3L7.5 19l-4 1 1-4z"/></>),
  'close':      (<><path d="M6 6l12 12"/><path d="M18 6L6 18"/></>),
  'check':      (<><path d="M5 12l5 5 9-11"/></>),
  'chevron-right': (<><path d="M9 6l6 6-6 6"/></>),
  'chevron-down':  (<><path d="M6 9l6 6 6-6"/></>),
  'chevron-left':  (<><path d="M15 6l-6 6 6 6"/></>),
  'arrow-up':   (<><path d="M12 19V5"/><path d="M5 12l7-7 7 7"/></>),
  'arrow-down': (<><path d="M12 5v14"/><path d="M5 12l7 7 7-7"/></>),
  'search':     (<><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></>),
  'filter':     (<><path d="M3 5h18"/><path d="M6 12h12"/><path d="M10 19h4"/></>),
  'upload':     (<><path d="M12 16V4"/><path d="M7 9l5-5 5 5"/><path d="M4 20h16"/></>),
  'file-text':  (<><path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4"/><path d="M9 13h6"/><path d="M9 17h4"/></>),
  'menu':       (<><path d="M4 6h16"/><path d="M4 12h16"/><path d="M4 18h16"/></>),
  'more':       (<><circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/></>),
  'info':       (<><circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><circle cx="12" cy="8" r="0.5" fill="currentColor" stroke="none"/></>),
  'alert':      (<><path d="M12 3l10 18H2z"/><path d="M12 10v5"/><circle cx="12" cy="18" r="0.5" fill="currentColor" stroke="none"/></>),
  'trash':      (<><path d="M4 7h16"/><path d="M6 7v13a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7"/><path d="M9 7V4h6v3"/><path d="M10 11v7"/><path d="M14 11v7"/></>),
  'sun':        (<><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="M4.93 4.93l1.41 1.41"/><path d="M17.66 17.66l1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="M4.93 19.07l1.41-1.41"/><path d="M17.66 6.34l1.41-1.41"/></>),
  'moon':       (<><path d="M21 13A9 9 0 0 1 11 3a7 7 0 1 0 10 10z"/></>),

  // categories (inline only; used inside tiles)
  'home':       (<><path d="M3 10l9-7 9 7v11H3z"/><path d="M9 21v-7h6v7"/></>),
  'fork':       (<><path d="M4 4v7a4 4 0 0 0 4 4h0a4 4 0 0 0 4-4V4"/><path d="M8 15v5"/><path d="M18 4v8"/><path d="M18 15v5"/></>),
  'piggy':      (<><path d="M15 5H8a5 5 0 0 0 0 10h.5l1.5 4h3l.5-2H16l1.5 2H20l-1-4a6 6 0 0 0-4-8z"/><circle cx="16" cy="11" r="0.5" fill="currentColor" stroke="none"/></>),
  'zap':        (<><path d="M13 3L4 14h7l-1 7 9-11h-7z"/></>),
  'wifi':       (<><path d="M2 8.5a15 15 0 0 1 20 0"/><path d="M5 12a11 11 0 0 1 14 0"/><path d="M8.5 15.5a6 6 0 0 1 7 0"/><circle cx="12" cy="19" r="0.8" fill="currentColor" stroke="none"/></>),
  'car':        (<><path d="M5 17h14l-1.5-6a2 2 0 0 0-2-1.5h-7a2 2 0 0 0-2 1.5L5 17z"/><circle cx="8" cy="17" r="2"/><circle cx="16" cy="17" r="2"/></>),
  'fuel':       (<><rect x="5" y="4" width="9" height="17" rx="1"/><path d="M14 8h2a2 2 0 0 1 2 2v7a2 2 0 0 0 2 2"/><path d="M7 9h5"/></>),
  'cart':       (<><circle cx="9" cy="20" r="1"/><circle cx="18" cy="20" r="1"/><path d="M3 3h2l2.5 11a2 2 0 0 0 2 1.5h7a2 2 0 0 0 2-1.5L21 7H6.5"/></>),
  'sparkle':    (<><path d="M12 3l2 5 5 2-5 2-2 5-2-5-5-2 5-2z"/></>),
  'bag':        (<><path d="M6 7h12l-1 13H7z"/><path d="M9 7a3 3 0 1 1 6 0"/></>),
  'shield':     (<><path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/></>),
  'hourglass':  (<><path d="M7 3h10"/><path d="M7 21h10"/><path d="M7 3c0 5 5 5 5 9s-5 4-5 9"/><path d="M17 3c0 5-5 5-5 9s5 4 5 9"/></>),
  'plane':      (<><path d="M10 3l1 6 8 4-8 4-1 6 2-2 6-8-6-8z"/></>),
  'music':      (<><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></>),
  'briefcase':  (<><rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2"/></>),
  'heart':      (<><path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2 4 4 0 0 1 7 2c0 5.5-7 10-7 10z"/></>),
  'coffee':     (<><path d="M5 8h12v6a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4z"/><path d="M17 9h2a2 2 0 0 1 0 4h-2"/><path d="M7 4v2"/><path d="M11 4v2"/></>),
  'question':   (<><circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 0 1 5 0c0 1.5-2.5 2-2.5 4"/><circle cx="12" cy="17" r="0.5" fill="currentColor" stroke="none"/></>),
};

// Map category name → icon key
const CAT_ICONS = {
  House: 'home', Living: 'fork', Savings: 'piggy', Unknown: 'question',
  'Car Insurance': 'shield', Gas: 'fuel', Grocery: 'cart', Fun: 'sparkle', Shopping: 'bag',
  Rent: 'home', Utilities: 'zap', Internet: 'wifi',
  'Emergency Fund': 'shield', Retirement: 'hourglass', Travel: 'plane',
  Subscriptions: 'music', Work: 'briefcase', Health: 'heart', Cafes: 'coffee',
};

function CatIcon({ name, size = 20, stroke = 1.75, style }) {
  const key = CAT_ICONS[name] || 'question';
  return <Icon name={key} size={size} stroke={stroke} style={style} />;
}

Object.assign(window, { Icon, CatIcon, CAT_ICONS, ICON_PATHS });
