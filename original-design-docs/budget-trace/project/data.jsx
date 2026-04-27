// Shared data + helpers for Budget Trace wireframes
// Exposes globals: BUDGET, squarify, fmtMoney, catColor, ICONS, makeTransactions

const BUDGET = {
  name: 'Budget',
  income: 5400,
  children: [
    {
      name: 'House', amount: 1800, color: 'var(--c-house)', actual: 1820,
      children: [
        { name: 'Rent', amount: 1500, actual: 1500 },
        { name: 'Utilities', amount: 200, actual: 215 },
        { name: 'Internet', amount: 100, actual: 105 },
      ],
    },
    {
      name: 'Living', amount: 1450, color: 'var(--c-living)', actual: 1380,
      children: [
        { name: 'Car Insurance', amount: 320, color: 'var(--c-car)', actual: 320 },
        { name: 'Gas', amount: 220, color: 'var(--c-gas)', actual: 198 },
        { name: 'Grocery', amount: 540, color: 'var(--c-grocery)', actual: 612 },
        { name: 'Fun', amount: 200, color: 'var(--c-fun)', actual: 142 },
        { name: 'Shopping', amount: 170, color: 'var(--c-shopping)', actual: 108 },
      ],
    },
    {
      name: 'Savings', amount: 1500, color: 'var(--c-savings)', actual: 1500,
      children: [
        { name: 'Emergency Fund', amount: 600, actual: 600 },
        { name: 'Retirement', amount: 700, actual: 700 },
        { name: 'Travel', amount: 200, actual: 200 },
      ],
    },
    {
      name: 'Unknown', amount: 0, color: 'var(--c-unknown)', actual: 87,
      children: [],
      isUnknown: true,
    },
  ],
};

const ICONS = {
  House: '⌂', Living: '◉', Savings: '$', Unknown: '?',
  'Car Insurance': '⚐', Gas: '⛽', Grocery: '🛒', Fun: '★', Shopping: '◆',
  Rent: '⌂', Utilities: '⚡', Internet: '⌬',
  'Emergency Fund': '⛨', Retirement: '⌛', Travel: '✈',
};

function fmtMoney(n) {
  if (n == null) return '$—';
  const sign = n < 0 ? '-' : '';
  const abs = Math.abs(n);
  return sign + '$' + abs.toLocaleString('en-US', { maximumFractionDigits: 0 });
}

function catColor(node) {
  if (node?.color) return node.color;
  return 'var(--paper-2)';
}

// Squarified treemap layout — produces { x,y,w,h, node } rects
function squarify(items, x, y, w, h) {
  const out = [];
  let total = items.reduce((s, it) => s + (it.value || 0), 0);
  if (total <= 0) return out;
  let rect = { x, y, w, h };
  let remaining = items.slice();
  while (remaining.length) {
    const row = [];
    let best = Infinity;
    const short = Math.min(rect.w, rect.h);
    const scale = (rect.w * rect.h) / total;
    let rowSum = 0;
    while (remaining.length) {
      const next = remaining[0];
      const trial = row.concat([next]);
      const trialSum = rowSum + next.value;
      const worst = worstAspect(trial, trialSum, short, scale);
      if (worst > best && row.length) break;
      row.push(next);
      rowSum = trialSum;
      best = worst;
      remaining.shift();
    }
    // place row
    const rowArea = rowSum * scale;
    if (rect.w >= rect.h) {
      // row laid vertically along left edge of rect (width = rowArea/h)
      const rowW = rowArea / rect.h;
      let yy = rect.y;
      for (const it of row) {
        const itH = (it.value * scale) / rowW;
        out.push({ x: rect.x, y: yy, w: rowW, h: itH, node: it.node });
        yy += itH;
      }
      rect = { x: rect.x + rowW, y: rect.y, w: rect.w - rowW, h: rect.h };
    } else {
      const rowH = rowArea / rect.w;
      let xx = rect.x;
      for (const it of row) {
        const itW = (it.value * scale) / rowH;
        out.push({ x: xx, y: rect.y, w: itW, h: rowH, node: it.node });
        xx += itW;
      }
      rect = { x: rect.x, y: rect.y + rowH, w: rect.w, h: rect.h - rowH };
    }
    total -= rowSum;
    best = Infinity;
  }
  return out;
}
function worstAspect(row, rowSum, short, scale) {
  const rowArea = rowSum * scale;
  let mn = Infinity, mx = -Infinity;
  for (const it of row) {
    const a = it.value * scale;
    mn = Math.min(mn, a);
    mx = Math.max(mx, a);
  }
  const w2 = short * short;
  const s2 = rowArea * rowArea;
  return Math.max((w2 * mx) / s2, s2 / (w2 * mn));
}

function makeTransactions() {
  return [
    { date: 'Mar 02', merchant: 'TRADER JOES #142', amount: 84.21, cat: 'Grocery' },
    { date: 'Mar 02', merchant: 'SHELL OIL', amount: 52.10, cat: 'Gas' },
    { date: 'Mar 03', merchant: 'CON EDISON BILL', amount: 215.00, cat: 'Utilities' },
    { date: 'Mar 04', merchant: 'GEICO AUTO', amount: 320.00, cat: 'Car Insurance' },
    { date: 'Mar 05', merchant: 'AMZN MKTP US*Z82', amount: 38.40, cat: null },
    { date: 'Mar 07', merchant: 'WHOLE FOODS MKT', amount: 124.55, cat: 'Grocery' },
    { date: 'Mar 08', merchant: 'NETFLIX.COM', amount: 22.99, cat: 'Fun' },
    { date: 'Mar 09', merchant: 'STARBUCKS #4419', amount: 7.45, cat: null },
    { date: 'Mar 11', merchant: 'BLOCK INC *VENMO', amount: 60.00, cat: null },
    { date: 'Mar 12', merchant: 'SHELL OIL', amount: 48.30, cat: 'Gas' },
    { date: 'Mar 14', merchant: 'TARGET 00012445', amount: 67.12, cat: 'Shopping' },
    { date: 'Mar 15', merchant: 'CHASE MORTGAGE', amount: 1500.00, cat: 'Rent' },
    { date: 'Mar 17', merchant: 'TRADER JOES #142', amount: 71.40, cat: 'Grocery' },
    { date: 'Mar 18', merchant: 'SPOTIFY USA', amount: 11.99, cat: 'Fun' },
    { date: 'Mar 22', merchant: 'UBER *TRIP', amount: 18.50, cat: null },
    { date: 'Mar 24', merchant: 'COSTCO WHSE', amount: 211.83, cat: 'Grocery' },
    { date: 'Mar 27', merchant: 'AMC THEATERS', amount: 36.00, cat: 'Fun' },
    { date: 'Mar 29', merchant: 'XFINITY MOBILE', amount: 105.00, cat: 'Internet' },
  ];
}

Object.assign(window, { BUDGET, ICONS, fmtMoney, catColor, squarify, makeTransactions });
