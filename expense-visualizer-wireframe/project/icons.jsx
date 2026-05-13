/* global React */
// Stroke icon set — lucide-style, currentColor strokes.

const Icon = ({ d, size = 18, sw = 1.6, fill = "none", children, style }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill={fill}
    stroke="currentColor"
    strokeWidth={sw}
    strokeLinecap="round"
    strokeLinejoin="round"
    style={{ display: "block", ...style }}
  >
    {d ? <path d={d} /> : children}
  </svg>
);

const I = {
  Grid: (p) => (
    <Icon {...p}>
      <rect x="3" y="3" width="7" height="7" rx="1.5" />
      <rect x="14" y="3" width="7" height="7" rx="1.5" />
      <rect x="3" y="14" width="7" height="7" rx="1.5" />
      <rect x="14" y="14" width="7" height="7" rx="1.5" />
    </Icon>
  ),
  List: (p) => (
    <Icon {...p}>
      <line x1="3" y1="6" x2="21" y2="6" />
      <line x1="3" y1="12" x2="21" y2="12" />
      <line x1="3" y1="18" x2="21" y2="18" />
    </Icon>
  ),
  Chart: (p) => (
    <Icon {...p}>
      <path d="M3 3v18h18" />
      <path d="M7 14l4-4 3 3 6-7" />
    </Icon>
  ),
  Sparkle: (p) => (
    <Icon {...p}>
      <path d="M12 3l2 5 5 2-5 2-2 5-2-5-5-2 5-2z" />
      <path d="M19 14l1 2 2 1-2 1-1 2-1-2-2-1 2-1z" />
    </Icon>
  ),
  Search: (p) => (
    <Icon {...p}>
      <circle cx="11" cy="11" r="7" />
      <line x1="21" y1="21" x2="16.5" y2="16.5" />
    </Icon>
  ),
  Plus: (p) => (
    <Icon {...p}>
      <line x1="12" y1="5" x2="12" y2="19" />
      <line x1="5" y1="12" x2="19" y2="12" />
    </Icon>
  ),
  X: (p) => (
    <Icon {...p}>
      <line x1="6" y1="6" x2="18" y2="18" />
      <line x1="18" y1="6" x2="6" y2="18" />
    </Icon>
  ),
  Check: (p) => (
    <Icon {...p}>
      <polyline points="4 12 10 18 20 6" />
    </Icon>
  ),
  ChevronDown: (p) => (
    <Icon {...p}>
      <polyline points="6 9 12 15 18 9" />
    </Icon>
  ),
  ChevronRight: (p) => (
    <Icon {...p}>
      <polyline points="9 6 15 12 9 18" />
    </Icon>
  ),
  ChevronLeft: (p) => (
    <Icon {...p}>
      <polyline points="15 6 9 12 15 18" />
    </Icon>
  ),
  Upload: (p) => (
    <Icon {...p}>
      <path d="M12 3v14" />
      <polyline points="7 8 12 3 17 8" />
      <path d="M5 21h14" />
    </Icon>
  ),
  Pencil: (p) => (
    <Icon {...p}>
      <path d="M16 3l5 5L8 21H3v-5z" />
    </Icon>
  ),
  Trash: (p) => (
    <Icon {...p}>
      <polyline points="4 7 20 7" />
      <path d="M6 7v13a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7" />
      <path d="M9 7V4h6v3" />
    </Icon>
  ),
  Refresh: (p) => (
    <Icon {...p}>
      <path d="M21 12a9 9 0 1 1-3-6.7L21 8" />
      <polyline points="21 3 21 8 16 8" />
    </Icon>
  ),
  Filter: (p) => (
    <Icon {...p}>
      <polygon points="3 4 21 4 14 13 14 20 10 20 10 13" />
    </Icon>
  ),
  Send: (p) => (
    <Icon {...p}>
      <line x1="22" y1="2" x2="11" y2="13" />
      <polygon points="22 2 15 22 11 13 2 9" />
    </Icon>
  ),
  Calendar: (p) => (
    <Icon {...p}>
      <rect x="3" y="5" width="18" height="16" rx="2" />
      <line x1="3" y1="10" x2="21" y2="10" />
      <line x1="8" y1="3" x2="8" y2="7" />
      <line x1="16" y1="3" x2="16" y2="7" />
    </Icon>
  ),
  User: (p) => (
    <Icon {...p}>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21a8 8 0 0 1 16 0" />
    </Icon>
  ),
  Eye: (p) => (
    <Icon {...p}>
      <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z" />
      <circle cx="12" cy="12" r="3" />
    </Icon>
  ),
  EyeOff: (p) => (
    <Icon {...p}>
      <path d="M3 3l18 18" />
      <path d="M10.6 6.1A11 11 0 0 1 12 6c6.5 0 10 6 10 6a17 17 0 0 1-3.2 4" />
      <path d="M6.1 6.1A17 17 0 0 0 2 12s3.5 7 10 7c1.5 0 2.9-.3 4.2-.8" />
    </Icon>
  ),
  Warn: (p) => (
    <Icon {...p}>
      <path d="M12 3l10 17H2z" />
      <line x1="12" y1="10" x2="12" y2="14" />
      <line x1="12" y1="17" x2="12" y2="17.5" />
    </Icon>
  ),
  Drag: (p) => (
    <Icon {...p}>
      <circle cx="9" cy="6" r="1" />
      <circle cx="9" cy="12" r="1" />
      <circle cx="9" cy="18" r="1" />
      <circle cx="15" cy="6" r="1" />
      <circle cx="15" cy="12" r="1" />
      <circle cx="15" cy="18" r="1" />
    </Icon>
  ),
  File: (p) => (
    <Icon {...p}>
      <path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z" />
      <polyline points="14 3 14 9 20 9" />
    </Icon>
  ),
  Home: (p) => (
    <Icon {...p}>
      <path d="M3 11l9-8 9 8" />
      <path d="M5 10v10h14V10" />
    </Icon>
  ),
  Sun: (p) => (
    <Icon {...p}>
      <circle cx="12" cy="12" r="4" />
      <line x1="12" y1="2" x2="12" y2="4" />
      <line x1="12" y1="20" x2="12" y2="22" />
      <line x1="2" y1="12" x2="4" y2="12" />
      <line x1="20" y1="12" x2="22" y2="12" />
      <line x1="4.9" y1="4.9" x2="6.3" y2="6.3" />
      <line x1="17.7" y1="17.7" x2="19.1" y2="19.1" />
      <line x1="4.9" y1="19.1" x2="6.3" y2="17.7" />
      <line x1="17.7" y1="6.3" x2="19.1" y2="4.9" />
    </Icon>
  ),
  Moon: (p) => (
    <Icon {...p}>
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
    </Icon>
  ),
  ArrowUp: (p) => (
    <Icon {...p}>
      <line x1="12" y1="19" x2="12" y2="5" />
      <polyline points="5 12 12 5 19 12" />
    </Icon>
  ),
  Save: (p) => (
    <Icon {...p}>
      <path d="M5 21h14a2 2 0 0 0 2-2V7l-4-4H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2z" />
      <polyline points="7 3 7 9 15 9" />
      <polyline points="7 21 7 13 17 13 17 21" />
    </Icon>
  ),
  Bell: (p) => (
    <Icon {...p}>
      <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" />
      <path d="M10 21a2 2 0 0 0 4 0" />
    </Icon>
  ),
  Inbox: (p) => (
    <Icon {...p}>
      <polyline points="22 12 16 12 14 15 10 15 8 12 2 12" />
      <path d="M5 5h14l3 7v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-6z" />
    </Icon>
  ),
  Folder: (p) => (
    <Icon {...p}>
      <path d="M3 7a2 2 0 0 1 2-2h4l2 3h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
    </Icon>
  ),
  Settings: (p) => (
    <Icon {...p}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .4 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.4 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.4l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .4-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.4-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.4H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.4l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.4 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
    </Icon>
  ),
  History: (p) => (
    <Icon {...p}>
      <path d="M3 12a9 9 0 1 0 3-6.7L3 8" />
      <polyline points="3 3 3 8 8 8" />
      <polyline points="12 7 12 12 16 14" />
    </Icon>
  ),
  Wand: (p) => (
    <Icon {...p}>
      <path d="M3 21l12-12" />
      <path d="M14 4l2 2" />
      <path d="M17 7l2 2" />
      <path d="M14 10l2 2" />
      <path d="M20 14l2 2" />
    </Icon>
  ),
  Image: (p) => (
    <Icon {...p}>
      <rect x="3" y="3" width="18" height="18" rx="2" />
      <circle cx="9" cy="9" r="2" />
      <polyline points="21 15 16 10 5 21" />
    </Icon>
  ),
};

window.EVIcons = I;
