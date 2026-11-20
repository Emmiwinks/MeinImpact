// The sticker motifs. Each draws in a 100 × 100 box around a face-colour
// blob (circle at 50/54, r 34) that build.mjs adds, and may reach past it:
// stickers pop out of their round. Flat shapes only, in ink, card stock and
// the topic colours, with 3-unit ink outlines, like the topic art.
//
// A motif gets the palette `p`: f is the topic's face colour, a the next one
// in the rotation and b the one after (so a motif never paints itself in the
// colour it sits on).

import { KEYS, PACIFIER } from './references.mjs';

export const K = '#101820';
export const W = '#F4F1EA';
export const CORAL = '#FF5A5F';
export const TEAL = '#2EC4B6';
export const AMBER = '#FFBF3C';
export const VIOLET = '#8C84FF';
export const BROWN = '#C98A55';
export const ROTATION = [CORAL, TEAL, AMBER, VIOLET];

const o = (w = 3) =>
  `stroke="${K}" stroke-width="${w}" stroke-linejoin="round" stroke-linecap="round"`;
const line = (d, w = 3) => `<path d="${d}" fill="none" ${o(w)}/>`;
// A tube: an ink stroke with a narrower colour stroke on top.
const tube = (d, color, w = 4) =>
  `<path d="${d}" fill="none" stroke="${K}" stroke-width="${w + 5}" stroke-linecap="round" stroke-linejoin="round"/>` +
  `<path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
const sparkle = (x, y, r, color = W) =>
  `<path d="M${x} ${y - r} Q${x} ${y} ${x + r} ${y} Q${x} ${y} ${x} ${y + r} Q${x} ${y} ${x - r} ${y} Q${x} ${y} ${x} ${y - r} Z" fill="${color}" ${o(1.6)}/>`;
const eyes = (x1, x2, y, r = 2.6) =>
  `<ellipse cx="${x1}" cy="${y}" rx="${r}" ry="${r * 1.35}" fill="${K}"/>` +
  `<ellipse cx="${x2}" cy="${y}" rx="${r}" ry="${r * 1.35}" fill="${K}"/>`;

export const motifs = {
  // ── Alle Themen: instruments, from a squeak to a roar ──────────────────
  kazoo: (p) => `
    <g transform="rotate(-14 50 55)">
      <path d="M20 50 L70 45 Q80 44 80 52 L80 59 Q80 67 70 66 L20 61 Q14 60.5 14 55.5 Q14 50.5 20 50 Z" fill="${p.a}" ${o()}/>
      <path d="M22 54 L74 50" stroke="${W}" stroke-width="3" stroke-linecap="round" opacity=".7"/>
      <rect x="41" y="36" width="16" height="12" rx="4" fill="${K}"/>
      <ellipse cx="49" cy="36" rx="10" ry="4" fill="${W}" ${o()}/>
      ${line('M86 46 q5 7 0 14 M93 41 q8 12 0 24', 3.2)}
    </g>`,
  // One piece: the mouthpiece runs straight into the round chamber.
  trillerpfeife: (p) => `
    ${line('M20 40 Q8 26 22 16 Q36 8 44 20', 2.6)}
    <path d="M12 40 H58 A21 21 0 1 1 37 61 V58 H18 Q12 58 12 52 Z" fill="${W}" ${o()}/>
    <circle cx="58" cy="61" r="8" fill="${p.a}" ${o(2.4)}/>
    <rect x="40" y="44" width="10" height="6" rx="1.5" fill="${K}"/>
    <circle cx="20" cy="40" r="4.5" fill="${W}" ${o(2.4)}/>
    ${line('M84 30 l7 -7 M88 42 l10 -2 M84 18 l2 -9', 3)}`,
  troete: (p) => `
    <g transform="rotate(-12 50 55)">
      <path d="M12 52 L12 60 L72 78 L72 34 Z" fill="${W}" ${o()}/>
      <path d="M26 48.6 L26 64.2 L36 67.2 L36 45.6 Z M48 42 L48 70.8 L58 73.8 L58 39 Z" fill="${p.a}"/>
      <path d="M12 52 L12 60 L72 78 L72 34 Z" fill="none" ${o()}/>
      <ellipse cx="72" cy="56" rx="9" ry="22" fill="${p.b}" ${o()}/>
      <ellipse cx="72" cy="56" rx="4" ry="13" fill="${K}"/>
      <rect x="4" y="52" width="10" height="8" rx="2" fill="${K}"/>
    </g>
    ${line('M88 26 l6 -6 M92 40 h8 M88 52 l7 4', 3.2)}`,
  // One piece: a single tube from mouthpiece to bell, the bell straight on
  // its end.
  trompete: (p) => `
    <g transform="rotate(-8 50 55)">
      ${tube('M12 58 H34 V48 Q34 42 40 42 H58 Q64 42 64 48 V58 H70', p.a)}
      ${tube('M34 58 H64', p.a)}
      <path d="M68 52 L92 40 V76 L68 64 Z" fill="${p.a}" ${o()}/>
      <ellipse cx="92" cy="58" rx="4.5" ry="18" fill="${K}"/>
      <rect x="40" y="30" width="6" height="14" rx="2" fill="${W}" ${o(2.4)}/>
      <rect x="49" y="30" width="6" height="14" rx="2" fill="${W}" ${o(2.4)}/>
      <rect x="58" y="30" width="6" height="14" rx="2" fill="${W}" ${o(2.4)}/>
      <rect x="6" y="54" width="8" height="8" rx="2" fill="${K}"/>
    </g>
    ${sparkle(82, 22, 6, W)}`,
  // One piece: one tube from the mouthpiece round the slide's bend into the
  // bell, the bell straight on its end.
  posaune: (p) => `
    <g transform="rotate(-8 50 55)">
      ${tube('M14 62 H24 A9 9 0 0 1 24 44 H66', p.a)}
      ${tube('M24 62 H58 A4 4 0 0 0 58 54 H40', p.a)}
      <path d="M64 38 L90 26 V62 L64 50 Z" fill="${p.a}" ${o()}/>
      <ellipse cx="90" cy="44" rx="4.5" ry="18" fill="${K}"/>
      <rect x="44" y="40" width="6" height="26" rx="2" fill="${W}" ${o(2.5)}/>
      <rect x="8" y="58" width="8" height="8" rx="2" fill="${K}"/>
    </g>`,
  // The mallets lie with their heads on the drumhead.
  pauke: (p) => `
    ${line('M30 76 L22 92 M70 76 L78 92 M50 84 V94', 3)}
    <path d="M16 46 H84 Q82 84 50 86 Q18 84 16 46 Z" fill="${p.a}" ${o()}/>
    <path d="M24 56 V72 M38 52 V80 M62 52 V80 M76 56 V72" stroke="${K}" stroke-width="2" stroke-linecap="round" opacity=".5"/>
    <ellipse cx="50" cy="46" rx="34" ry="10" fill="${W}" ${o()}/>
    ${tube('M12 14 L33 41', BROWN, 3)}${tube('M88 14 L67 41', BROWN, 3)}
    <circle cx="35" cy="43" r="6.5" fill="${p.b}" ${o(2.6)}/>
    <circle cx="65" cy="43" r="6.5" fill="${p.b}" ${o(2.6)}/>
    ${line('M42 30 l2 -6 M58 30 l-2 -6 M50 28 v-7', 2.6)}`,
  kirchenorgel: (p) => {
    const pipes = [[16, 46], [26, 34], [36, 24], [46, 14], [56, 24], [66, 34], [76, 46]];
    return `
    ${pipes.map(([x, y], i) => `
      <rect x="${x}" y="${y}" width="9" height="${70 - y}" rx="4.5" fill="${i % 2 ? W : p.a}" ${o(2.6)}/>
      <path d="M${x + 2} ${y + 14} l2.5 4 l2.5 -4 Z" fill="${K}"/>`).join('')}
    <rect x="12" y="66" width="76" height="22" rx="6" fill="${p.b}" ${o()}/>
    <path d="M20 76 H80" stroke="${W}" stroke-width="3" stroke-linecap="round"/>
    <path d="M24 80 v4 M32 80 v4 M40 80 v4 M60 80 v4 M68 80 v4 M76 80 v4" stroke="${K}" stroke-width="2.4" stroke-linecap="round"/>
    <circle cx="88" cy="20" r="4" fill="${K}"/>${line('M91.5 20 V6 l6 2', 2.4)}`;
  },

  // ── Wohnen ──────────────────────────────────────────────────────────────
  mietzekatze: (p) => `
    ${tube('M66 82 Q84 80 80 62 Q78 56 72 58', W, 3)}
    <path d="M32 88 Q30 62 50 60 Q70 62 68 88 Z" fill="${W}" ${o()}/>
    <path d="M34 34 L33 16 L46 26 Z M66 34 L67 16 L54 26 Z" fill="${W}" ${o()}/>
    <circle cx="50" cy="42" r="18" fill="${W}" ${o()}/>
    <path d="M36 22 L40 29 M64 22 L60 29" stroke="${p.a}" stroke-width="3" stroke-linecap="round"/>
    ${eyes(43, 57, 41)}
    <path d="M47.5 48 h5 l-2.5 3 z" fill="${p.a}" ${o(1.5)}/>
    <path d="M32 48 h8 M32 52 l8 -1.5 M68 48 h-8 M68 52 l-8 -1.5" stroke="${K}" stroke-width="1.8" stroke-linecap="round"/>
    <path d="M38 60 Q50 66 62 60" fill="none" stroke="${p.a}" stroke-width="4" stroke-linecap="round"/>
    <g transform="translate(50 68) rotate(18)">
      <circle r="5" fill="${AMBER}" ${o(2.2)}/><circle r="1.6" fill="${K}"/>
      <path d="M0 5 V14 M0 10 h3.5 M0 13 h3" stroke="${K}" stroke-width="2.2" stroke-linecap="round"/>
    </g>`,
  klingelschild: (p) => `
    <rect x="24" y="12" width="52" height="80" rx="10" fill="${W}" ${o()}/>
    <circle cx="36" cy="22" r="1.8" fill="${K}"/><circle cx="43" cy="22" r="1.8" fill="${K}"/><circle cx="50" cy="22" r="1.8" fill="${K}"/><circle cx="57" cy="22" r="1.8" fill="${K}"/><circle cx="64" cy="22" r="1.8" fill="${K}"/>
    ${[34, 52, 70].map((y, i) => `
      <rect x="31" y="${y}" width="24" height="10" rx="3" fill="${[p.a, AMBER, p.b][i]}" ${o(2.4)}/>
      <circle cx="65" cy="${y + 5}" r="6" fill="${W}" ${o(2.6)}/>
      <circle cx="65" cy="${y + 5}" r="2.2" fill="${K}"/>`).join('')}
    ${line('M82 30 q6 4 4 12 M88 24 q10 8 6 22', 3)}`,
  // The ring runs through each key's hole, drawn over the keys.
  // After the user's reference (keys, SVG Repo): an open ring and two keys
  // hanging from it through their holes, as one shape.
  schluesselbund: (p) => `
    <g transform="translate(25 13) scale(.6)" data-cut="20">
      <path d="${KEYS}" fill="${AMBER}" stroke="${K}" stroke-width="4.5" stroke-linejoin="round"/>
    </g>`,

  // ── Mobilität ───────────────────────────────────────────────────────────
  bimmelbahn: (p) => `
    ${line('M50 30 L42 20 L58 14')}${line('M34 14 h32')}
    <rect x="18" y="30" width="64" height="44" rx="12" fill="${p.a}" ${o()}/>
    <rect x="18" y="58" width="64" height="8" fill="${W}" ${o()}/>
    <rect x="25" y="37" width="14" height="15" rx="3" fill="${W}" ${o(2.5)}/>
    <rect x="43" y="37" width="14" height="15" rx="3" fill="${W}" ${o(2.5)}/>
    <rect x="61" y="37" width="14" height="15" rx="3" fill="${W}" ${o(2.5)}/>
    <circle cx="32" cy="78" r="7" fill="${K}"/><circle cx="68" cy="78" r="7" fill="${K}"/>
    <circle cx="32" cy="78" r="2.5" fill="${W}"/><circle cx="68" cy="78" r="2.5" fill="${W}"/>
    ${line('M14 86 H86')}
    <g transform="translate(14 30)">
      <path d="M-6 6 Q-6 -4 0 -4 Q6 -4 6 6 Z" fill="${AMBER}" ${o(2.4)}/>
      <circle cy="7.5" r="2" fill="${K}"/>
      ${line('M-10 -8 l-3 -3 M-12 0 h-4', 2.2)}
    </g>`,
  // The box rides in front; the handlebar sits right behind it.
  lastenrad: (p) => `
    <circle cx="24" cy="76" r="11" fill="${W}" ${o(3.5)}/><circle cx="24" cy="76" r="2.5" fill="${K}"/>
    <circle cx="78" cy="74" r="13" fill="${W}" ${o(3.5)}/><circle cx="78" cy="74" r="2.5" fill="${K}"/>
    ${tube('M24 76 L46 56 V36 M46 58 H64 L78 74 M64 58 L60 42 M58 74 L64 58 M58 74 H78', p.b, 3)}
    ${line('M40 34 H52', 4.5)}
    ${line('M54 42 H66', 5)}
    <rect x="6" y="44" width="34" height="22" rx="4" fill="${p.a}" ${o()}/>
    <path d="M14 44 Q12 30 20 26 Q24 34 22 44 Z M26 44 Q30 32 38 32 Q36 40 30 44 Z" fill="${TEAL === p.f ? AMBER : TEAL}" ${o(2.4)}/>`,
  doppeldeckerbus: (p) => `
    <rect x="18" y="14" width="64" height="66" rx="10" fill="${p.a}" ${o()}/>
    <rect x="18" y="44" width="64" height="5" fill="${W}" ${o(2.5)}/>
    ${[24, 40, 56].map((x) => `<rect x="${x + 1}" y="20" width="13" height="16" rx="3" fill="${W}" ${o(2.4)}/><rect x="${x + 1}" y="54" width="13" height="14" rx="3" fill="${W}" ${o(2.4)}/>`).join('')}
    <rect x="72" y="54" width="7" height="22" rx="2" fill="${K}"/>
    <circle cx="32" cy="82" r="7" fill="${K}"/><circle cx="68" cy="82" r="7" fill="${K}"/>
    <circle cx="32" cy="82" r="2.5" fill="${W}"/><circle cx="68" cy="82" r="2.5" fill="${W}"/>
    <rect x="30" y="7" width="40" height="7" rx="3" fill="${AMBER === p.a ? W : AMBER}" ${o(2.4)}/>
    ${line('M12 90 H88')}`,

  // ── Arbeit ──────────────────────────────────────────────────────────────
  // A coffee mug full of coins.
  kaffeekasse: (p) => `
    ${[[34, 34], [46, 28], [58, 32], [40, 22]].map(([x, y]) => `
      <ellipse cx="${x}" cy="${y}" rx="9" ry="9" fill="${AMBER}" ${o(2.6)}/>
      <path d="M${x - 3} ${y} h6" stroke="${K}" stroke-width="2.2" stroke-linecap="round" opacity=".6"/>`).join('')}
    <path d="M72 46 h6 Q88 46 88 58 Q88 70 76 70 h-4" fill="none" stroke="${K}" stroke-width="10" stroke-linecap="round"/>
    <path d="M72 46 h6 Q88 46 88 58 Q88 70 76 70 h-4" fill="none" stroke="${p.a}" stroke-width="5" stroke-linecap="round"/>
    <path d="M20 38 H76 V78 Q76 90 64 90 H32 Q20 90 20 78 Z" fill="${p.a}" ${o()}/>
    <path d="M20 46 H76" stroke="${K}" stroke-width="3"/>
    <path d="M42 58 Q48 54 54 58 Q60 62 54 70 Q48 74 42 70 Q36 62 42 58 Z" fill="${BROWN}" ${o(2.4)}/>
    ${line('M45 59 Q50 64 51 70', 2)}
    <circle cx="80" cy="18" r="8" fill="${AMBER}" ${o(2.6)}/>
    ${sparkle(66, 10, 4, W)}`,
  stempelkarte: (p) => `
    <g transform="rotate(-8 50 52)">
      <rect x="22" y="10" width="56" height="80" rx="6" fill="${W}" ${o()}/>
      <rect x="22" y="10" width="56" height="14" rx="6" fill="${p.a}" ${o()}/>
      ${[32, 44, 56, 68].map((y) => `<path d="M30 ${y} H54" stroke="${K}" stroke-width="2.4" stroke-linecap="round" opacity=".55"/><circle cx="66" cy="${y}" r="3.4" fill="${K}"/>`).join('')}
      <path d="M30 80 H50" stroke="${K}" stroke-width="2.4" stroke-linecap="round" opacity=".55"/>
    </g>
    <circle cx="74" cy="76" r="14" fill="none" stroke="${p.b}" stroke-width="4"/>
    ${line('M67 76 l5 5 l9 -11', 4)}`,
  chefsessel: (p) => `
    <rect x="28" y="8" width="44" height="46" rx="16" fill="${p.a}" ${o()}/>
    <path d="M36 18 V44 M50 16 V46 M64 18 V44" stroke="${K}" stroke-width="2.2" stroke-linecap="round" opacity=".45"/>
    ${tube('M26 52 V42 H30 M74 52 V42 H70', W, 4)}
    <rect x="22" y="50" width="56" height="14" rx="7" fill="${p.a}" ${o()}/>
    <rect x="46" y="62" width="8" height="14" fill="${K}"/>
    ${line('M50 76 L28 84 M50 76 L72 84 M50 76 V88', 3.5)}
    <circle cx="26" cy="86" r="4" fill="${W}" ${o(2.4)}/><circle cx="74" cy="86" r="4" fill="${W}" ${o(2.4)}/><circle cx="50" cy="90" r="4" fill="${W}" ${o(2.4)}/>
    ${sparkle(84, 16, 6, AMBER)}`,

  // ── Energie ─────────────────────────────────────────────────────────────
  // Upright leg, the foot to the right; heel and toe in the same colour,
  // following the sock's own outline.
  wollsocke: (p) => {
    const sock = 'M30 12 H60 V52 Q60 58 66 60 L82 64 Q92 67 91 77 Q90 88 78 87 L40 84 Q28 83 29 70 Z';
    return `
    <path d="${sock}" fill="${W}"/>
    <path d="M30 24 H60 M30 36 H60" stroke="${p.a}" stroke-width="7"/>
    <path d="M29 70 Q28 83 40 84 L44 84 Q40 74 46 66 Q38 62 30 64 Z" fill="${p.a}"/>
    <path d="M78 64 L82 64 Q92 67 91 77 Q90 88 78 87 L74 87 Q80 76 78 64 Z" fill="${p.a}"/>
    <path d="${sock}" fill="none" ${o()}/>
    <rect x="26" y="6" width="38" height="11" rx="5" fill="${p.b}" ${o(2.6)}/>`;
  },
  waermflasche: (p) => `
    <rect x="42" y="8" width="16" height="12" rx="3" fill="${K}"/>
    <rect x="44" y="18" width="12" height="10" fill="${p.a}" ${o(2.6)}/>
    <path d="M24 34 Q24 26 32 26 H68 Q76 26 76 34 V80 Q76 90 66 90 H34 Q24 90 24 80 Z" fill="${p.a}" ${o()}/>
    <path d="M32 36 H68 M32 82 H68" stroke="${K}" stroke-width="2.4" stroke-linecap="round" opacity=".45"/>
    <path d="M50 70 C36 60 38 46 46 48 Q50 50 50 54 Q50 50 54 48 C62 46 64 60 50 70 Z" fill="${W}" ${o(2.6)}/>
    ${line('M84 50 q4 -5 0 -10 q-4 -5 0 -10 M16 56 q4 -5 0 -10 q-4 -5 0 -10', 2.6)}`,
  windrad: (p) => `
    <path d="M47 40 L44 92 H56 L53 40 Z" fill="${W}" ${o()}/>
    ${[0, 120, 240].map((r) => `<path d="M50 34 Q46 14 50 4 Q56 14 52 34 Z" transform="rotate(${r} 50 36)" fill="${W}" ${o(2.6)}/>`).join('')}
    <circle cx="50" cy="36" r="6" fill="${p.a}" ${o(2.6)}/>
    ${line('M30 92 H70', 3.5)}
    <path d="M14 66 q4 -8 12 -4 q4 -6 10 0 q6 0 4 6 H14 Z" fill="${W}" ${o(2.4)}/>
    ${line('M72 60 q6 -4 12 0 M74 68 q6 -4 12 0', 2.6)}`,

  // ── Bildung ─────────────────────────────────────────────────────────────
  eselsohr: (p) => `
    <g transform="rotate(-6 50 50)">
      <rect x="24" y="12" width="54" height="76" rx="4" fill="${p.a}" ${o()}/>
      <rect x="20" y="16" width="54" height="76" rx="4" fill="${W}" ${o()}/>
      <path d="M74 16 V40 L52 16 Z" fill="${p.f === AMBER ? TEAL : AMBER}" ${o()}/>
      ${[30, 40, 50, 60, 70, 80].map((y) => `<path d="M28 ${y} H${y < 40 ? 48 : 66}" stroke="${K}" stroke-width="2.4" stroke-linecap="round" opacity=".5"/>`).join('')}
    </g>
    <path d="M78 64 L86 56 L92 62 L84 70 Z" fill="${p.b}" ${o(2.4)}/>
    <path d="M84 70 L76 72 L78 64 Z" fill="${W}" ${o(2.4)}/>`,
  tafelschwamm: (p) => `
    <rect x="12" y="12" width="64" height="48" rx="5" fill="${K}"/>
    <rect x="12" y="12" width="64" height="48" rx="5" fill="none" stroke="${BROWN}" stroke-width="5"/>
    <path d="M22 30 q5 -8 10 0 t10 0 M22 44 h22 M52 26 l8 10 M60 26 l-8 10" fill="none" stroke="${W}" stroke-width="2.6" stroke-linecap="round"/>
    <rect x="42" y="56" width="46" height="28" rx="7" fill="${AMBER === p.f ? p.a : AMBER}" ${o()}/>
    <rect x="42" y="74" width="46" height="10" rx="4" fill="${p.a === AMBER ? p.b : p.a}" ${o()}/>
    <circle cx="52" cy="64" r="2" fill="${K}" opacity=".5"/><circle cx="62" cy="68" r="2.4" fill="${K}" opacity=".5"/><circle cx="74" cy="63" r="2" fill="${K}" opacity=".5"/><circle cx="80" cy="69" r="1.6" fill="${K}" opacity=".5"/>
    ${sparkle(28, 76, 4)}${sparkle(18, 86, 3)}`,
  // A straight stack of books; the worm stands up out of the top one.
  buecherwurm: (p) => {
    const worm = TEAL === p.f ? AMBER : TEAL;
    return `
    <rect x="16" y="74" width="68" height="14" rx="3" fill="${p.a}" ${o()}/>
    <rect x="20" y="60" width="60" height="14" rx="3" fill="${p.b}" ${o()}/>
    <rect x="18" y="46" width="64" height="14" rx="3" fill="${W}" ${o()}/>
    <path d="M24 81 H76 M28 67 H72" stroke="${W}" stroke-width="2.4" stroke-linecap="round" opacity=".8"/>
    <rect x="42" y="22" width="16" height="30" rx="8" fill="${worm}" ${o()}/>
    <path d="M42 36 H58 M42 44 H58" stroke="${K}" stroke-width="2" opacity=".45"/>
    <circle cx="50" cy="20" r="12" fill="${worm}" ${o()}/>
    <circle cx="45" cy="19" r="5" fill="${W}" ${o(2.2)}/><circle cx="56" cy="19" r="5" fill="${W}" ${o(2.2)}/>
    ${line('M50 19 h1', 2.2)}
    <circle cx="45" cy="19" r="1.8" fill="${K}"/><circle cx="56" cy="19" r="1.8" fill="${K}"/>
    ${line('M46 26 q4 3 8 0', 2)}
    <path d="M30 52 Q40 56 50 52" fill="none" stroke="${K}" stroke-width="2.4" stroke-linecap="round"/>`;
  },

  // ── Rente ───────────────────────────────────────────────────────────────
  lesebrille: (p) => `
    ${line('M10 44 Q8 36 16 34 M90 44 Q92 36 84 34', 3.4)}
    <circle cx="30" cy="52" r="18" fill="${W}" stroke="${K}" stroke-width="5"/>
    <circle cx="70" cy="52" r="18" fill="${W}" stroke="${K}" stroke-width="5"/>
    <circle cx="30" cy="52" r="18" fill="none" stroke="${p.a}" stroke-width="2"/>
    <circle cx="70" cy="52" r="18" fill="none" stroke="${p.a}" stroke-width="2"/>
    ${line('M44 46 Q50 40 56 46', 4.5)}
    <path d="M20 46 Q24 40 30 40" fill="none" stroke="${p.b}" stroke-width="3" stroke-linecap="round"/>
    <path d="M60 46 Q64 40 70 40" fill="none" stroke="${p.b}" stroke-width="3" stroke-linecap="round"/>
    ${line('M14 34 L10 44 M86 34 L90 44', 3.4)}`,
  ohrensessel: (p) => `
    <path d="M26 20 Q26 10 36 10 H64 Q74 10 74 20 V60 H26 Z" fill="${p.a}" ${o()}/>
    <path d="M16 32 Q14 22 26 24 V64 H16 Z M84 32 Q86 22 74 24 V64 H84 Z" fill="${p.a}" ${o()}/>
    <rect x="12" y="50" width="76" height="24" rx="10" fill="${p.a}" ${o()}/>
    <rect x="24" y="52" width="52" height="12" rx="5" fill="${W}" ${o(2.6)}/>
    <path d="M38 14 h24 l-4 10 h-16 Z" fill="${W}" ${o(2.2)}/>
    ${line('M20 74 L18 86 M80 74 L82 86', 4)}
    <path d="M36 30 l2 2 M50 28 l2 2 M64 30 l2 2 M43 40 l2 2 M57 40 l2 2" stroke="${K}" stroke-width="2.4" stroke-linecap="round" opacity=".5"/>`,
  // One silver curl, falling from the top and rolling in.
  silberlocke: (p) => `
    ${tube('M68 10 Q40 14 32 40 Q26 66 48 72 Q66 76 68 58 Q68 44 54 44 Q44 44 44 54 Q44 62 52 62', '#D7DCE3', 11)}
    <path d="M58 16 Q42 22 38 40" fill="none" stroke="${W}" stroke-width="3" stroke-linecap="round"/>
    ${sparkle(80, 30, 8, W)}${sparkle(20, 76, 5, p.b)}`,

  // ── Digitales ───────────────────────────────────────────────────────────
  passwort123: (p) => `
    <path d="M34 46 V32 Q34 14 50 14 Q66 14 66 32 V46" fill="none" stroke="${K}" stroke-width="11" stroke-linecap="round"/>
    <path d="M34 46 V32 Q34 14 50 14 Q66 14 66 32 V46" fill="none" stroke="${W}" stroke-width="5" stroke-linecap="round"/>
    <rect x="20" y="42" width="60" height="46" rx="10" fill="${p.a}" ${o()}/>
    <rect x="28" y="54" width="44" height="18" rx="6" fill="${W}" ${o(2.6)}/>
    <circle cx="38" cy="63" r="3.4" fill="${K}"/><circle cx="50" cy="63" r="3.4" fill="${K}"/><circle cx="62" cy="63" r="3.4" fill="${K}"/>
    <rect x="46" y="76" width="8" height="8" rx="2" fill="${K}"/>`,
  cookieMonster: (p) => `
    <path d="M50 14 A38 38 0 1 0 88 52 A9 9 0 0 1 76 40 A9 9 0 0 1 64 28 A9 9 0 0 1 58 15 Q54 14 50 14 Z" fill="${BROWN}" ${o()}/>
    <circle cx="30" cy="60" r="4" fill="${K}"/><circle cx="48" cy="74" r="4.4" fill="${K}"/><circle cx="66" cy="66" r="3.6" fill="${K}"/><circle cx="26" cy="40" r="3" fill="${K}"/><circle cx="56" cy="50" r="2.6" fill="${K}"/>
    <circle cx="36" cy="22" r="10" fill="${W}" ${o()}/><circle cx="54" cy="26" r="8" fill="${W}" ${o()}/>
    <circle cx="38" cy="25" r="4" fill="${K}"/><circle cx="52" cy="28" r="3.4" fill="${K}"/>
    <circle cx="82" cy="22" r="3.4" fill="${BROWN}" ${o(2)}/><circle cx="90" cy="32" r="2.6" fill="${BROWN}" ${o(2)}/>`,
  supercomputer: (p) => `
    <rect x="20" y="8" width="42" height="82" rx="6" fill="${K}"/>
    ${[16, 34, 52, 70].map((y, i) => `
      <rect x="25" y="${y}" width="32" height="13" rx="3" fill="${p.a}" ${o(2)}/>
      <circle cx="31" cy="${y + 6.5}" r="2.2" fill="${[TEAL, CORAL, AMBER, W][i] === p.a ? W : [TEAL, CORAL, AMBER, W][i]}"/>
      <path d="M38 ${y + 6.5} H52" stroke="${K}" stroke-width="2.2" stroke-linecap="round"/>`).join('')}
    <rect x="62" y="30" width="22" height="60" rx="5" fill="${p.b}" ${o()}/>
    <path d="M67 40 H79 M67 48 H79 M67 56 H79" stroke="${K}" stroke-width="2.4" stroke-linecap="round"/>
    <path d="M78 6 L70 20 H78 L72 32 L88 14 H80 L86 6 Z" fill="${W}" ${o(2.4)}/>`,

  // ── Sicherheit ──────────────────────────────────────────────────────────
  // A kids' night light: a penguin lamp in one warm colour, glowing on a
  // dark round (see BLOB in build.mjs).
  nachtlicht: (p) => {
    const penguin = 'M50 16 Q66 16 68 36 Q70 44 72 50 L80 62 Q82 67 77 66 L72 62 Q72 78 64 84 L66 88 H56 L54 86 H46 L44 88 H34 L36 84 Q28 78 28 62 L23 66 Q18 67 20 62 L28 50 Q30 44 32 36 Q34 16 50 16 Z';
    return `
    <circle class="glow" cx="50" cy="56" r="32" fill="${AMBER}" opacity=".16"/>
    <path class="glow" d="${penguin}" fill="none" stroke="${AMBER}" stroke-width="14" stroke-linejoin="round" opacity=".28"/>
    <path class="glow" d="${penguin}" fill="none" stroke="${AMBER}" stroke-width="7" stroke-linejoin="round" opacity=".4"/>
    <path d="${penguin}" fill="#FFF1C2" ${o()}/>
    <path d="M38 34 q4 3 8 0 M54 34 q4 3 8 0 M46 41 L50 46 L54 41" fill="none" stroke="${K}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" opacity=".55"/>
    ${sparkle(84, 22, 5, W)}${sparkle(16, 30, 3.5, W)}`;
  },
  schutzengel: (p) => `
    <path d="M44 46 Q20 30 8 44 Q14 54 24 54 Q14 62 22 70 Q34 70 44 58 Z" fill="${W}" ${o()}/>
    <path d="M56 46 Q80 30 92 44 Q86 54 76 54 Q86 62 78 70 Q66 70 56 58 Z" fill="${W}" ${o()}/>
    <path d="M38 88 L50 44 L62 88 Z" fill="${p.a}" ${o()}/>
    <circle cx="50" cy="36" r="12" fill="${W}" ${o()}/>
    ${eyes(46, 54, 36, 1.8).replace(/ry="[^"]*"/g, 'ry="1"')}
    ${line('M46 41 q4 3 8 0', 2)}
    <ellipse cx="50" cy="16" rx="13" ry="4.5" fill="none" stroke="${K}" stroke-width="7"/>
    <ellipse cx="50" cy="16" rx="13" ry="4.5" fill="none" stroke="${AMBER}" stroke-width="3"/>`,
  leuchtturm: (p) => `
    <path d="M18 34 L4 22 M18 40 L2 42 M82 34 L96 22 M82 40 L98 42" stroke="${AMBER}" stroke-width="5" stroke-linecap="round"/>
    <path d="M38 40 L32 86 H68 L62 40 Z" fill="${W}" ${o()}/>
    <path d="M36.7 50 H63.3 L64.6 60 H35.4 Z M34.1 70 H65.9 L67.2 80 H32.8 Z" fill="${p.a}"/>
    <path d="M38 40 L32 86 H68 L62 40 Z" fill="none" ${o()}/>
    <rect x="36" y="24" width="28" height="16" rx="3" fill="${AMBER}" ${o()}/>
    <path d="M44 24 V40 M56 24 V40" stroke="${K}" stroke-width="2.4"/>
    <path d="M34 24 L50 10 L66 24 Z" fill="${p.a}" ${o()}/>
    <path d="M18 92 Q24 82 36 86 H64 Q78 82 84 92 Z" fill="${K}"/>`,

  // ── Migration ───────────────────────────────────────────────────────────
  woerterbuch: (p) => `
    <rect x="18" y="38" width="58" height="52" rx="5" fill="${p.a}" ${o()}/>
    <rect x="24" y="44" width="58" height="44" rx="3" fill="${W}" ${o()}/>
    ${[48, 58, 68, 78].map((y, i) => `<rect x="80" y="${y}" width="8" height="8" rx="2" fill="${[CORAL, TEAL, AMBER, VIOLET][i]}" ${o(2)}/>`).join('')}
    <path d="M32 60 H70 M32 70 H62 M32 80 H66" stroke="${K}" stroke-width="2.4" stroke-linecap="round" opacity=".5"/>
    <path d="M12 12 H44 Q50 12 50 18 V28 Q50 34 44 34 H26 L18 40 V34 Q12 34 12 28 V18 Q12 12 18 12 Z" fill="${W}" ${o(2.6)}/>
    <path d="M56 8 H84 Q90 8 90 14 V24 Q90 30 84 30 H82 V36 L76 30 H56 Q50 30 50 24 V14 Q50 8 56 8 Z" fill="${p.b}" ${o(2.6)}/>
    <circle cx="24" cy="23" r="2" fill="${K}"/><circle cx="31" cy="23" r="2" fill="${K}"/><circle cx="38" cy="23" r="2" fill="${K}"/>
    ${line('M60 19 h22', 2.4)}`,
  langeTafel: (p) => `
    <path d="M6 54 H94 L88 64 H12 Z" fill="${W}" ${o()}/>
    <path d="M12 64 L18 86 M88 64 L82 86 M34 64 L36 86 M66 64 L64 86" stroke="${K}" stroke-width="4" stroke-linecap="round"/>
    <path d="M12 64 Q20 70 28 64 Q36 70 44 64 Q52 70 60 64 Q68 70 76 64 Q84 70 88 64" fill="none" stroke="${p.a}" stroke-width="3"/>
    ${[[20, p.a], [50, p.b], [80, AMBER === p.f ? TEAL : AMBER]].map(([x, c]) => `
      <ellipse cx="${x}" cy="50" rx="11" ry="4" fill="${W}" ${o(2.4)}/>
      <path d="M${x - 7} 48 Q${x} 36 ${x + 7} 48 Z" fill="${c}" ${o(2.2)}/>`).join('')}
    <rect x="31" y="36" width="8" height="14" rx="2" fill="${W}" ${o(2.2)}/>
    <rect x="61" y="36" width="8" height="14" rx="2" fill="${W}" ${o(2.2)}/>
    ${line('M48 30 q2 -4 0 -8 M54 30 q2 -4 0 -8', 2.2)}`,
  festzelt: (p) => `
    <path d="M8 84 L18 44 L50 22 L82 44 L92 84 Z" fill="${W}" ${o()}/>
    <path d="M18 44 L26 84 H36 L30 44 M42 30 L44 84 H56 L58 30 M70 44 L64 84 H74 L82 44" fill="${p.a}"/>
    <path d="M8 84 L18 44 L50 22 L82 44 L92 84 Z" fill="none" ${o()}/>
    <path d="M18 44 Q26 52 34 44 Q42 52 50 44 Q58 52 66 44 Q74 52 82 44" fill="none" ${o(2.6)}/>
    <path d="M42 84 V64 Q50 56 58 64 V84 Z" fill="${K}"/>
    ${line('M50 22 V8', 3)}
    <path d="M50 8 L66 12 L50 17 Z" fill="${p.b}" ${o(2.2)}/>`,

  // ── Außenpolitik ────────────────────────────────────────────────────────
  // A snow globe as from a trip: a little house and a fir tree in the snow,
  // flakes in the glass.
  schneekugel: (p) => `
    <circle cx="50" cy="44" r="32" fill="#E4F5F2" ${o()}/>
    <path d="M22 60 Q36 50 50 56 Q64 50 78 60 A32 32 0 0 1 22 60 Z" fill="${W}"/>
    <path d="M60 58 L68 34 L76 58 Z" fill="${TEAL}" ${o(2.4)}/>
    <rect x="30" y="44" width="20" height="16" fill="${W}" ${o(2.4)}/>
    <path d="M27 46 L40 34 L53 46 Z" fill="${CORAL}" ${o(2.4)}/>
    <rect x="37" y="51" width="6" height="9" fill="${K}"/>
    ${[[30, 24], [62, 20], [72, 34], [26, 38], [44, 18], [56, 30]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="2" fill="${W}" ${o(1.4)}/>`).join('')}
    <path d="M30 26 A26 26 0 0 1 42 16" fill="none" stroke="${W}" stroke-width="4" stroke-linecap="round"/>
    <circle cx="50" cy="44" r="32" fill="none" ${o()}/>
    <path d="M28 74 L22 92 H78 L72 74 Z" fill="${p.a}" ${o()}/>
    <path d="M28 84 H72" stroke="${W}" stroke-width="3" stroke-linecap="round"/>`,
  reisepass: (p) => `
    <g transform="rotate(-10 50 52)">
      <rect x="22" y="12" width="52" height="74" rx="6" fill="${p.a}" ${o()}/>
      <circle cx="48" cy="42" r="13" fill="none" stroke="${W}" stroke-width="3"/>
      <path d="M35 42 H61 M48 29 Q40 42 48 55 Q56 42 48 29" fill="none" stroke="${W}" stroke-width="2.6"/>
      <rect x="34" y="64" width="28" height="5" rx="2.5" fill="${W}"/>
    </g>
    <g transform="rotate(14 74 70)">
      <rect x="62" y="56" width="26" height="22" rx="4" fill="${W}" ${o(2.6)}/>
      <rect x="66" y="60" width="18" height="14" rx="3" fill="none" stroke="${p.b}" stroke-width="2.6" stroke-dasharray="3 2"/>
      ${line('M70 70 l4 -6 l4 4 l3 -3', 2.2)}
    </g>
    ${sparkle(18, 22, 5, W)}`,
  friedenstaube: (p) => `
    <path d="M18 54 Q16 34 38 36 L60 28 Q70 22 78 28 L90 30 L80 36 Q78 58 54 66 L42 80 L38 66 Q24 66 18 54 Z" fill="${W}" ${o()}/>
    <path d="M38 40 Q46 18 66 10 Q62 28 52 42" fill="${W}" ${o()}/>
    <path d="M18 54 L4 60 L8 50 Z" fill="${W}" ${o(2.6)}/>
    <circle cx="74" cy="31" r="2.2" fill="${K}"/>
    ${line('M86 34 Q90 46 82 56', 2.4)}
    <path d="M85 42 q8 -2 10 4 q-8 2 -10 -4 Z M84 50 q-8 0 -8 6 q8 0 8 -6 Z" fill="${TEAL === p.f ? AMBER : TEAL}" ${o(1.8)}/>`,

  // ── Demokratie ──────────────────────────────────────────────────────────
  kreuzchen: (p) => `
    <g transform="rotate(-6 50 50)">
      <rect x="18" y="12" width="56" height="76" rx="5" fill="${W}" ${o()}/>
      ${[26, 46, 66].map((y) => `<rect x="26" y="${y}" width="12" height="12" rx="2" fill="${W}" ${o(2.4)}/><path d="M44 ${y + 6} H66" stroke="${K}" stroke-width="2.4" stroke-linecap="round" opacity=".5"/>`).join('')}
      <path d="M24 44 L42 62 M42 44 L24 62" stroke="${p.a}" stroke-width="5" stroke-linecap="round"/>
    </g>
    <g transform="rotate(38 78 64)">
      <rect x="72" y="26" width="12" height="52" rx="3" fill="${p.b}" ${o(2.6)}/>
      <path d="M72 78 L78 90 L84 78 Z" fill="${W}" ${o(2.4)}/>
    </g>`,
  megafon: (p) => `
    <g transform="rotate(-14 50 50)">
      <path d="M26 40 L70 20 V80 L26 60 Z" fill="${p.a}" ${o()}/>
      <ellipse cx="70" cy="50" rx="8" ry="30" fill="${W}" ${o()}/>
      <ellipse cx="70" cy="50" rx="3.5" ry="18" fill="${K}"/>
      <rect x="12" y="40" width="16" height="20" rx="4" fill="${W}" ${o()}/>
      <path d="M36 62 L32 82 H42 L46 66" fill="${p.b}" ${o(2.6)}/>
    </g>
    ${line('M86 22 l6 -6 M90 38 h8 M86 54 l7 5', 3.2)}`,
  rednerpult: (p) => `
    ${line('M42 30 Q40 18 30 14 M58 30 Q60 18 70 14', 3)}
    <rect x="25" y="9" width="8" height="10" rx="4" fill="${K}"/>
    <rect x="67" y="9" width="8" height="10" rx="4" fill="${K}"/>
    <path d="M20 30 H80 L72 42 H28 Z" fill="${W}" ${o()}/>
    <path d="M28 42 H72 L66 90 H34 Z" fill="${p.a}" ${o()}/>
    <circle cx="50" cy="62" r="9" fill="${W}" ${o(2.6)}/>
    ${sparkle(50, 62, 4.5, p.b)}
    ${line('M26 92 H74', 3.5)}`,

  // ── Stadtentwicklung/Bauen ──────────────────────────────────────────────
  bauklotz: (p) => `
    <rect x="12" y="58" width="30" height="30" rx="4" fill="${p.a}" ${o()}/>
    <rect x="46" y="58" width="30" height="30" rx="4" fill="${AMBER}" ${o()}/>
    <rect x="28" y="30" width="32" height="28" rx="4" fill="${W}" ${o()}/>
    <path d="M28 30 L44 8 L60 30 Z" fill="${p.b}" ${o()}/>
    <circle cx="27" cy="73" r="6" fill="${W}" ${o(2.4)}/>
    <path d="M55 66 h12 v14 h-12 Z" fill="none" ${o(2.4)}/>
    <path d="M44 38 V50" stroke="${K}" stroke-width="3" stroke-linecap="round"/>
    <rect x="78" y="70" width="12" height="18" rx="6" fill="${TEAL}" ${o(2.6)}/>`,
  betonmischer: (p) => `
    <rect x="62" y="40" width="28" height="34" rx="6" fill="${p.a}" ${o()}/>
    <rect x="68" y="46" width="16" height="12" rx="3" fill="${W}" ${o(2.4)}/>
    <rect x="10" y="64" width="80" height="12" rx="3" fill="${K}"/>
    <g transform="rotate(-14 36 48)">
      <ellipse cx="36" cy="48" rx="26" ry="18" fill="${W}" ${o()}/>
      <path d="M18 36 L30 64 M30 31 L44 66 M44 31 L54 60" stroke="${AMBER}" stroke-width="6"/>
      <ellipse cx="36" cy="48" rx="26" ry="18" fill="none" ${o()}/>
      <ellipse cx="10" cy="48" rx="4" ry="9" fill="${K}"/>
    </g>
    <circle cx="26" cy="80" r="8" fill="${K}"/><circle cx="74" cy="80" r="8" fill="${K}"/>
    <circle cx="26" cy="80" r="3" fill="${W}"/><circle cx="74" cy="80" r="3" fill="${W}"/>`,
  riesenkran: (p) => `
    ${tube('M10 22 H92', AMBER, 4.5)}
    ${line('M50 4 L28 22 M50 4 L86 22', 2.2)}
    <rect x="8" y="24" width="16" height="12" rx="2" fill="${K}"/>
    <rect x="43" y="22" width="14" height="70" fill="${AMBER}" ${o()}/>
    <path d="M43 32 L57 42 L43 52 L57 62 L43 72 L57 82" fill="none" ${o(2.4)}/>
    <rect x="40" y="24" width="20" height="12" rx="3" fill="${W}" ${o(2.6)}/>
    ${line('M80 25 V54', 2)}
    <path d="M80 54 v5 a4 4 0 1 1 -4 4" fill="none" ${o(3)}/>
    <rect x="70" y="66" width="20" height="13" rx="2" fill="${p.a}" ${o(2.6)}/>
    ${line('M34 92 H66', 4)}`,

  // ── Gesundheit ──────────────────────────────────────────────────────────
  huehnersuppe: (p) => `
    ${line('M36 30 q-4 -6 0 -12 q4 -6 0 -12 M50 30 q-4 -6 0 -12 q4 -6 0 -12 M64 30 q-4 -6 0 -12 q4 -6 0 -12', 2.6)}
    <ellipse cx="50" cy="48" rx="38" ry="10" fill="${AMBER}" ${o()}/>
    <path d="M30 46 q6 4 12 0 t12 0 M48 50 q4 3 8 0" fill="none" stroke="${W}" stroke-width="2.6" stroke-linecap="round"/>
    <circle cx="66" cy="47" r="3.4" fill="${CORAL === p.f ? VIOLET : CORAL}" ${o(1.6)}/><circle cx="34" cy="50" r="3" fill="${TEAL}" ${o(1.6)}/>
    <path d="M12 48 Q14 84 50 86 Q86 84 88 48 Q86 58 50 58 Q14 58 12 48 Z" fill="${p.a}" ${o()}/>
    <path d="M30 70 Q50 76 70 70" fill="none" stroke="${W}" stroke-width="3" stroke-linecap="round"/>
    <g transform="rotate(30 80 40)">${tube('M80 10 V40', W, 4)}<ellipse cx="80" cy="44" rx="6" ry="8" fill="${W}" ${o(2.6)}/></g>`,
  obstkorb: (p) => `
    <circle cx="34" cy="40" r="13" fill="${TEAL}" ${o()}/>
    ${line('M34 27 V20', 3)}<path d="M35 22 q8 -6 12 0 q-8 4 -12 0 Z" fill="${TEAL === p.f ? AMBER : W}" ${o(1.8)}/>
    <path d="M48 46 Q50 24 72 18 Q80 18 78 24 Q62 30 62 46 Z" fill="${AMBER}" ${o()}/>
    ${[[64, 38], [72, 38], [68, 30]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="6" fill="${VIOLET}" ${o(2.2)}/>`).join('')}
    <path d="M12 48 H88 L80 88 H20 Z" fill="${BROWN}" ${o()}/>
    <path d="M16 60 H84 M18 72 H82" stroke="${K}" stroke-width="2.4" opacity=".45"/>
    <path d="M30 48 L34 88 M50 48 V88 M70 48 L66 88" stroke="${K}" stroke-width="2.4" opacity=".45"/>
    <rect x="8" y="44" width="84" height="8" rx="4" fill="${BROWN}" ${o()}/>`,
  goldeneHantel: (p) => `
    <g transform="rotate(-20 50 54)">
      ${tube('M22 54 H78', W, 5)}
      <rect x="14" y="34" width="12" height="40" rx="4" fill="${AMBER}" ${o()}/>
      <rect x="6" y="40" width="10" height="28" rx="3" fill="${AMBER}" ${o()}/>
      <rect x="74" y="34" width="12" height="40" rx="4" fill="${AMBER}" ${o()}/>
      <rect x="84" y="40" width="10" height="28" rx="3" fill="${AMBER}" ${o()}/>
      <path d="M17 40 V54 M77 40 V54" stroke="${W}" stroke-width="2.6" stroke-linecap="round"/>
    </g>
    ${sparkle(30, 18, 8, W)}${sparkle(76, 84, 6, AMBER)}${sparkle(56, 22, 4, W)}`,

  // ── Familie ─────────────────────────────────────────────────────────────
  // After the user's reference (pacifier, SVG Repo): the teat at the top
  // right, the shield across, the ring at the bottom left, with the
  // reference's own outline in ink.
  schnuller: (p) => `
    <g transform="translate(13 15) scale(.15)" data-cut="80">
      <g transform="translate(1 1)">
        <path d="${PACIFIER.teat}" fill="#FFD9B3"/>
        <path d="${PACIFIER.ring}" fill="${p.b}"/>
        <path d="${PACIFIER.shield}" fill="${W}"/>
      </g>
      <path d="${PACIFIER.outline}" fill="${K}"/>
    </g>`,
  bobbycar: (p) => `
    <path d="M10 66 Q10 50 26 48 L40 46 Q46 34 60 36 Q70 38 72 48 L84 50 Q92 52 92 62 V70 H10 Z" fill="${CORAL === p.f ? AMBER : CORAL}" ${o()}/>
    <path d="M44 46 Q50 40 58 42 Q64 44 64 48 Z" fill="${K}"/>
    ${line('M68 46 L74 30 M70 30 H80', 3.6)}
    <circle cx="26" cy="72" r="11" fill="${W}" ${o(3.4)}/><circle cx="26" cy="72" r="4" fill="${K}"/>
    <circle cx="76" cy="72" r="11" fill="${W}" ${o(3.4)}/><circle cx="76" cy="72" r="4" fill="${K}"/>
    <circle cx="88" cy="58" r="3.4" fill="${AMBER === p.f ? W : AMBER}" ${o(2)}/>
    <path d="M20 58 H36" stroke="${W}" stroke-width="3" stroke-linecap="round"/>`,
  // One colour for the whole castle; only the tower tops are violet.
  huepfburg: (p) => `
    ${[14, 72].map((x) => `
      ${line(`M${x + 7} 15 V4`, 2.4)}<path d="M${x + 7} 4 l10 3 l-10 3 Z" fill="${W}" ${o(1.8)}/>
      <rect x="${x}" y="24" width="14" height="60" rx="7" fill="${AMBER}" ${o()}/>
      <circle cx="${x + 7}" cy="22" r="8" fill="${VIOLET}" ${o()}/>`).join('')}
    <path d="M26 42 Q34 34 42 42 Q50 34 58 42 Q66 34 74 42 V84 H26 Z" fill="${AMBER}" ${o()}/>
    <path d="M42 84 V66 Q50 56 58 66 V84 Z" fill="${K}"/>
    <path d="M30 52 H70" stroke="${K}" stroke-width="2.4" stroke-linecap="round" opacity=".4"/>
    <rect x="8" y="82" width="84" height="10" rx="5" fill="${AMBER}" ${o()}/>`,

  // ── Umwelt ──────────────────────────────────────────────────────────────
  regenwurm: (p) => `
    <path d="M6 86 Q20 66 40 70 Q60 64 74 72 Q88 70 94 86 Z" fill="${BROWN}" ${o()}/>
    ${tube('M30 76 Q28 54 44 46 Q60 38 62 22', '#FF8FA3', 10)}
    <circle cx="62" cy="18" r="9" fill="#FF8FA3" ${o()}/>
    <path d="M38 62 q4 2 8 0 M46 50 q4 2 8 0" stroke="${K}" stroke-width="2" stroke-linecap="round" opacity=".5"/>
    ${eyes(59, 66, 16, 1.6)}
    ${line('M59 22 q3 2 6 0', 1.8)}
    <path d="M76 70 Q74 54 84 50 Q88 62 76 70 Z" fill="${TEAL}" ${o(2.4)}/>
    <circle cx="20" cy="80" r="2" fill="${K}" opacity=".4"/><circle cx="82" cy="80" r="2" fill="${K}" opacity=".4"/>`,
  komposthaufen: (p) => `
    ${line('M30 30 q-4 -6 0 -12 M50 26 q-4 -6 0 -12 M70 30 q-4 -6 0 -12', 2.4)}
    <path d="M6 88 Q14 52 36 46 Q50 34 64 46 Q86 52 94 88 Z" fill="${BROWN}" ${o()}/>
    <path d="M26 64 Q32 56 40 62 Q34 68 26 64 Z" fill="${AMBER === p.f ? TEAL : AMBER}" ${o(2.2)}/>
    <path d="M56 58 l8 -6 l6 8 l-8 4 Z" fill="${W}" ${o(2.2)}/>
    <circle cx="44" cy="76" r="5" fill="${CORAL}" ${o(2.2)}/>
    <path d="M70 76 q6 -4 12 2" fill="none" stroke="${TEAL}" stroke-width="4" stroke-linecap="round"/>
    ${line('M50 46 V36', 2.6)}
    <path d="M50 38 Q42 32 40 24 Q48 26 50 36 Q52 26 60 24 Q58 32 50 38 Z" fill="${TEAL}" ${o(2.2)}/>`,
  mammutbaum: (p) => `
    <path d="M44 92 L46 50 H54 L56 92 Z" fill="${BROWN}" ${o()}/>
    <path d="M50 4 L66 30 H58 L72 52 H62 L78 76 H22 L38 52 H28 L42 30 H34 Z" fill="${TEAL}" ${o()}/>
    <path d="M44 34 L50 24 M40 58 L48 46 M34 70 L42 62" stroke="${W}" stroke-width="2.6" stroke-linecap="round" opacity=".7"/>
    <path d="M70 92 V82 L76 76 L82 82 V92 Z" fill="${W}" ${o(2.4)}/>
    ${line('M30 92 H90', 3.4)}
    ${sparkle(84, 20, 6, W)}`,

  // ── Selbstständigkeit ───────────────────────────────────────────────────
  visitenkarte: (p) => `
    <g transform="rotate(10 56 46)">
      <rect x="26" y="20" width="62" height="38" rx="5" fill="${p.b}" ${o()}/>
    </g>
    <g transform="rotate(-8 46 60)">
      <rect x="12" y="38" width="66" height="42" rx="5" fill="${W}" ${o()}/>
      <circle cx="30" cy="56" r="9" fill="${p.a}" ${o(2.6)}/>
      ${sparkle(30, 56, 4, W)}
      <path d="M46 52 H68 M46 60 H62 M22 72 H52" stroke="${K}" stroke-width="2.6" stroke-linecap="round"/>
    </g>
    ${sparkle(84, 74, 6, AMBER)}`,
  registrierkasse: (p) => `
    <rect x="30" y="8" width="40" height="16" rx="4" fill="${W}" ${o()}/>
    <path d="M36 16 H64" stroke="${p.b}" stroke-width="4" stroke-linecap="round"/>
    <path d="M18 26 H82 L88 70 H12 Z" fill="${p.a}" ${o()}/>
    ${[0, 1, 2].map((r) => [0, 1, 2, 3].map((c) => `<rect x="${26 + c * 13}" y="${32 + r * 11}" width="9" height="7" rx="2" fill="${W}" ${o(2)}/>`).join('')).join('')}
    <rect x="8" y="70" width="84" height="18" rx="4" fill="${W}" ${o()}/>
    <circle cx="50" cy="79" r="3" fill="${K}"/>
    <path d="M78 34 L86 28" stroke="${K}" stroke-width="3" stroke-linecap="round"/><circle cx="88" cy="26" r="4" fill="${AMBER}" ${o(2)}/>`,
  unicorn: (p) => `
    <path d="M30 90 Q26 60 42 42 Q52 32 64 34 L82 50 Q86 57 79 61 L67 59 Q60 68 64 90 Z" fill="${W}" ${o()}/>
    <path d="M57 35 L67 8 L66 37 Z" fill="${AMBER}" ${o(2.6)}/>
    ${line('M61 26 l5 1.5 M59 31 l6 1.5 M63 20 l3.5 1', 2)}
    <path d="M52 37 L48 25 L58 33 Z" fill="${W}" ${o(2.6)}/>
    <circle cx="44" cy="40" r="7" fill="${CORAL}" ${o(2.6)}/>
    <circle cx="36" cy="50" r="7" fill="${TEAL}" ${o(2.6)}/>
    <circle cx="31" cy="61" r="7" fill="${AMBER}" ${o(2.6)}/>
    <circle cx="29" cy="73" r="7" fill="${p.a}" ${o(2.6)}/>
    <ellipse cx="66" cy="46" rx="2.6" ry="3.4" fill="${K}"/>
    <circle cx="78" cy="55" r="1.6" fill="${K}"/>`,

  // ── Gleichstellung/Inklusion ────────────────────────────────────────────
  wippe: (p) => `
    <path d="M38 88 L50 62 L62 88 Z" fill="${p.a}" ${o()}/>
    <rect x="8" y="56" width="84" height="8" rx="4" fill="${W}" ${o()}/>
    <circle cx="50" cy="60" r="3" fill="${K}"/>
    <rect x="14" y="36" width="20" height="20" rx="10" fill="${p.b}" ${o()}/>
    <rect x="66" y="36" width="20" height="20" rx="10" fill="${AMBER === p.b ? TEAL : AMBER}" ${o()}/>
    ${line('M30 92 H70', 3.5)}
    ${sparkle(50, 30, 7, W)}`,
  hebebuehne: (p) => `
    <rect x="16" y="24" width="68" height="12" rx="3" fill="${p.a}" ${o()}/>
    ${line('M20 24 V14 H80 V24', 3)}
    <path d="M24 36 L76 60 M76 36 L24 60 M24 60 L76 84 M76 60 L24 84" stroke="${K}" stroke-width="6" stroke-linecap="round"/>
    <path d="M24 36 L76 60 M76 36 L24 60 M24 60 L76 84 M76 60 L24 84" stroke="${W}" stroke-width="2.4" stroke-linecap="round"/>
    <rect x="12" y="82" width="76" height="10" rx="3" fill="${p.b}" ${o()}/>
    <path d="M44 12 l6 -8 l6 8 Z" fill="${W}" ${o(2.2)}/>`,
  regenbogen: (p) => {
    const arcs = [VIOLET, TEAL, AMBER, CORAL].filter((c) => c !== p.f).concat([W]);
    return `
    ${arcs.map((c, i) => {
      const r = 36 - i * 7;
      return `<path d="M${50 - r} 70 A${r} ${r} 0 0 1 ${50 + r} 70" fill="none" stroke="${K}" stroke-width="9"/><path d="M${50 - r} 70 A${r} ${r} 0 0 1 ${50 + r} 70" fill="none" stroke="${c}" stroke-width="5"/>`;
    }).join('')}
    <path d="M4 76 Q4 64 16 66 Q20 56 30 62 Q36 64 34 76 Z" fill="${W}" ${o(2.6)}/>
    <path d="M66 76 Q64 64 76 66 Q80 56 90 62 Q98 64 96 76 Z" fill="${W}" ${o(2.6)}/>`;
  },
};
