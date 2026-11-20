// Writes the badge stickers to assets/badges/ and a preview sheet of all of
// them to .impeccable/review/stickers.html. Run from app/:
//   node tool/badges/build.mjs
//
// A sticker is its motif on a face-colour blob, all of it inside a die-cut
// border of card stock: the same shapes painted 12 units wider. Shadow,
// tilt and the tier seal are drawn by the app (badge_sticker.dart), so the
// files stay plain SVG that flutter_svg reads.

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { ROTATION, motifs } from './motifs.mjs';

const app = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// Same order as kTopicTags (lib/src/features/feed/domain/topic_tags.g.dart):
// a topic's face colour is its index in the rotation, as on the cards.
const topics = [
  ['Wohnen/Miete', ['mietzekatze', 'klingelschild', 'schluesselbund']],
  ['Mobilität/Verkehr', ['bimmelbahn', 'lastenrad', 'doppeldeckerbus']],
  ['Arbeit/Einkommen', ['kaffeekasse', 'stempelkarte', 'chefsessel']],
  ['Energie/Heizkosten', ['wollsocke', 'waermflasche', 'windrad']],
  ['Bildung/Ausbildung', ['eselsohr', 'tafelschwamm', 'buecherwurm']],
  ['Rente/Alter', ['lesebrille', 'ohrensessel', 'silberlocke']],
  ['Digitales/Datenschutz', ['passwort123', 'cookieMonster', 'supercomputer']],
  ['Sicherheit', ['nachtlicht', 'schutzengel', 'leuchtturm']],
  ['Migration/Integration', ['woerterbuch', 'langeTafel', 'festzelt']],
  ['Außenpolitik/Verteidigung', ['schneekugel', 'reisepass', 'friedenstaube']],
  ['Demokratie/Mitbestimmung', ['kreuzchen', 'megafon', 'rednerpult']],
  ['Stadtentwicklung/Bauen', ['bauklotz', 'betonmischer', 'riesenkran']],
  ['Gesundheit/Pflege', ['huehnersuppe', 'obstkorb', 'goldeneHantel']],
  ['Familie/Kinder', ['schnuller', 'bobbycar', 'huepfburg']],
  ['Umwelt/Natur', ['regenwurm', 'komposthaufen', 'mammutbaum']],
  ['Selbstständigkeit/Unternehmertum', ['visitenkarte', 'registrierkasse', 'unicorn']],
  ['Gleichstellung/Inklusion', ['wippe', 'hebebuehne', 'regenbogen']],
];
const overall = ['kazoo', 'trillerpfeife', 'troete', 'trompete', 'posaune', 'pauke', 'kirchenorgel'];

// The file name the app derives from a tag: its first part, lower case, ASCII.
export const slug = (tag) => tag.split('/')[0].toLowerCase()
  .replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss');

const palette = (i) => ({
  f: ROTATION[i % 4],
  a: ROTATION[(i + 1) % 4],
  b: ROTATION[(i + 2) % 4],
});

// Shapes with class="glow" are light, not paper: they stay out of the cut.
// A scaled group names its own cut width (data-cut), so the border stays as
// wide as everywhere else.
const cut = (svg) => svg
  .replace(/<[^>]*class="glow"[^>]*\/>/g, '')
  .replace(/(fill|stroke)="(?!none)[^"]*"/g, '')
  .replace(/stroke-width="[^"]*"/g, '')
  .replace(/opacity="[^"]*"/g, '')
  .replace(/data-cut="([^"]*)"/g, 'stroke-width="$1"');

// Motifs that need their own round: a lamp glows on dark.
const BLOB = { nachtlicht: '#101820' };

function sticker(key, p) {
  const art = motifs[key](p);
  const blob = `<circle cx="50" cy="54" r="34" fill="${BLOB[key] ?? p.f}"/>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
<g transform="translate(6 6) scale(.88)">
<g stroke="#FFFCF8" stroke-width="12" stroke-linejoin="round" stroke-linecap="round" fill="#FFFCF8">${cut(blob)}${cut(art)}</g>
${blob}${art}
</g>
</svg>
`.replace(/\n\s*\n/g, '\n');
}

const all = [
  ...overall.map((key, i) => ({ file: `alle-${i + 1}`, key, p: palette(i) })),
  ...topics.flatMap(([tag, keys], i) =>
    keys.map((key, tier) => ({ file: `${slug(tag)}-${tier + 1}`, key, p: palette(i) }))),
];

const out = join(app, 'assets', 'badges');
mkdirSync(out, { recursive: true });
for (const s of all) writeFileSync(join(out, `${s.file}.svg`), sticker(s.key, s.p));

const review = join(app, '..', '.impeccable', 'review');
mkdirSync(review, { recursive: true });
const cell = (s, size) =>
  `<figure><img src="../../app/assets/badges/${s.file}.svg" width="${size}" height="${size}"><figcaption>${s.file}</figcaption></figure>`;
writeFileSync(join(review, 'stickers.html'), `<!doctype html><meta charset="utf-8">
<style>
body{margin:0;font:600 11px system-ui;display:grid;grid-template-columns:1fr 1fr}
.t{padding:16px;display:grid;grid-template-columns:repeat(6,1fr);gap:6px}
.d{background:#101820;color:#F4F1EA}.l{background:#FFF1E3;color:#101820}
figure{margin:0;text-align:center}img{filter:drop-shadow(0 3px 3px #0005)}
</style>
<div class="t d">${all.map((s) => cell(s, 110)).join('')}</div>
<div class="t l">${all.map((s) => cell(s, 56)).join('')}</div>`);

console.log(`${all.length} stickers written to ${out}`);
