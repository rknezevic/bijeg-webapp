// Generates questions/matematika.txt (200 mental-math questions, answers checked by code).
import fs from 'node:fs';
import path from 'node:path';

let seed = 20261125;
const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const int = (a, b) => a + Math.floor(rnd() * (b - a + 1));
const pick = (xs) => xs[Math.floor(rnd() * xs.length)];
const fmt = (n) => (Number.isInteger(n) ? String(n) : String(n).replace('.', ','));

function wrongs(ans, spread = [1, 2, 10]) {
  const out = new Set();
  let guard = 0;
  while (out.size < 2 && guard++ < 50) {
    const d = pick(spread) * pick([-1, 1]);
    const w = ans + d;
    if (w !== ans && w >= 0) out.add(w);
  }
  return [...out];
}

const gens = [
  () => { const a = int(23, 89), b = int(14, 79); return [`Koliko je ${a} + ${b}?`, a + b, wrongs(a + b, [1, 10, 2])]; },
  () => { const a = int(120, 480), b = int(35, 160); return [`Koliko je ${a} + ${b}?`, a + b, wrongs(a + b, [10, 1, 100])]; },
  () => { const a = int(60, 150), b = int(17, 59); return [`Koliko je ${a} − ${b}?`, a - b, wrongs(a - b, [1, 10, 2])]; },
  () => { const a = int(300, 900), b = int(45, 290); return [`Koliko je ${a} − ${b}?`, a - b, wrongs(a - b, [10, 1, 100])]; },
  () => { const a = int(6, 12), b = int(6, 12); return [`Koliko je ${a} × ${b}?`, a * b, wrongs(a * b, [a, b, 2])]; },
  () => { const a = int(12, 25), b = int(3, 9); return [`Koliko je ${a} × ${b}?`, a * b, wrongs(a * b, [b, 10, 2])]; },
  () => { const b = int(3, 12), r = int(4, 15); return [`Koliko je ${b * r} : ${b}?`, r, wrongs(r, [1, 2])]; },
  () => { const a = int(11, 25); return [`Koliko je ${a} na kvadrat?`, a * a, wrongs(a * a, [a, 2 * a, 10])]; },
  () => { const a = int(4, 20); return [`Koliko je drugi korijen iz ${a * a}?`, a, wrongs(a, [1, 2])]; },
  () => { const a = int(2, 6); return [`Koliko je ${a} na treću?`, a ** 3, wrongs(a ** 3, [a, a * a, 3 * a])]; },
  () => { const p = pick([10, 20, 25, 50, 75, 5, 15]), n = pick([40, 60, 80, 120, 200, 240, 360, 400, 500, 800]); const v = (p * n) / 100; return Number.isInteger(v) ? [`Koliko je ${p} % od ${n}?`, v, wrongs(v, [5, 10, v / 2 || 1])] : null; },
  () => { const d = pick([2, 3, 4, 5]), n = d * int(6, 40); return [`Koliko je 1/${d} od ${n}?`, n / d, wrongs(n / d, [1, 2, 5])]; },
  () => { const a = int(2, 9), b = int(2, 9), c = int(2, 9); return [`Koliko je ${a} + ${b} × ${c}?`, a + b * c, [(a + b) * c, a + b * c + pick([1, -1, 2])]]; },
  () => { const a = int(10, 30), b = int(2, 6), c = int(2, 5); if (a - b * c <= 0) return null; return [`Koliko je ${a} − ${b} × ${c}?`, a - b * c, [(a - b) * c, a - b * c + pick([1, 2])]]; },
  () => { const x = int(3, 15), a = int(2, 9), b = int(1, 20); return [`Ako je ${a}x + ${b} = ${a * x + b}, koliko je x?`, x, wrongs(x, [1, 2])]; },
  () => { const x = int(5, 40), b = int(3, 25); return [`Ako je x − ${b} = ${x - b}, koliko je x?`, x, [x - 2 * b, x + 1]]; },
  () => { const h = pick([2, 3, 4, 5, 6, 8, 12, 24]); return [`Koliko minuta ima ${pl(h, 'sat', 'sata', 'sati')}?`, h * 60, wrongs(h * 60, [60, 10, 100])]; },
  () => { const m = pick([2, 3, 4, 5, 10, 15, 30]); return [`Koliko sekundi ima ${pl(m, 'minuta', 'minute', 'minuta')}?`, m * 60, wrongs(m * 60, [60, 10])]; },
  () => { const w = pick([2, 3, 5, 6, 8, 10, 12]); return [`Koliko dana ima ${pl(w, 'tjedan', 'tjedna', 'tjedana')}?`, w * 7, wrongs(w * 7, [7, 1, 2])]; },
  () => { const s = int(3, 25); return [`Koliki je opseg kvadrata stranice ${s} cm (u cm)?`, 4 * s, [s * s === 4 * s ? 4 * s + 4 : s * s, 2 * s]]; },
  () => { const a = int(3, 15), b = int(2, 12); return [`Kolika je površina pravokutnika ${a} cm × ${b} cm (u cm²)?`, a * b, [2 * (a + b) === a * b ? a * b + 2 : 2 * (a + b), a * b + pick([a, b])]]; },
  () => { const a = pick([30, 40, 45, 50, 60, 70, 80]), b = pick([20, 35, 55, 65, 75]); return a + b < 180 ? [`Dva kuta trokuta su ${a}° i ${b}°. Koliki je treći kut (u stupnjevima)?`, 180 - a - b, wrongs(180 - a - b, [10, 5, 90])] : null; },
  () => { const n = pick([4, 5, 6, 8, 10]); return [`Koliki je zbroj unutarnjih kutova mnogokuta s ${pl(n, 'stranicom', 'stranice', 'stranica')} (u stupnjevima)?`, (n - 2) * 180, wrongs((n - 2) * 180, [180, 90])]; },
  () => { const r = pick([['XIV', 14], ['XIX', 19], ['XXIV', 24], ['XL', 40], ['XC', 90], ['LXX', 70], ['CD', 400], ['MCM', 1900], ['MMXX', 2020], ['DCC', 700], ['XLIV', 44], ['LIX', 59], ['CXL', 140], ['MDCCC', 1800], ['XCIX', 99]]); return [`Koji broj predstavlja rimski broj ${r[0]}?`, r[1], wrongs(r[1], [10, 1, 5])]; },
  () => { const km = pick([1, 2, 3, 5, 7, 10, 12]); return [`Koliko metara ima ${km} km?`, km * 1000, [km * 100, km * 10000]]; },
  () => { const kg = pick([2, 3, 4, 5, 8, 15]); return [`Koliko grama ima ${kg} kg?`, kg * 1000, [kg * 100, kg * 10000]]; },
  () => { const l = pick([2, 3, 5, 6, 8]); return [`Koliko decilitara ima ${l} l?`, l * 10, [l * 100, l * 1000]]; },
  () => { const price = pick([20, 40, 50, 80, 100, 120, 200]), off = pick([10, 20, 25, 50]); const v = price * (100 - off) / 100; return [`Majica košta ${price} €. Koliko košta nakon popusta od ${off} %?`, v, wrongs(v, [price * off / 100, 5, 10])]; },
  () => { const n = int(3, 9), p = pick([2, 3, 4, 5, 6]); return [`${n} prijatelja dijeli račun od ${n * p * 5} €. Koliko plaća svaki?`, p * 5, wrongs(p * 5, [5, 1, 10])]; },
  () => { const s = pick([60, 80, 90, 100, 120]), t = pick([2, 3, 4]); return [`Auto vozi ${s} km/h. Koliko kilometara prijeđe za ${t} sata?`, s * t, wrongs(s * t, [s, 10, 20])]; },
  () => { const a = int(2, 12) * 2, b = int(2, 12) * 2; const avg = (a + b) / 2; return Number.isInteger(avg) ? [`Koja je aritmetička sredina brojeva ${a} i ${b}?`, avg, wrongs(avg, [1, 2])] : null; },
  () => { const a = pick([12, 18, 24, 30, 36, 42, 48, 60]), b = pick([8, 16, 20, 27, 45, 54, 72, 90]); const g = gcd(a, b); return g > 1 ? [`Koji je najveći zajednički djelitelj brojeva ${a} i ${b}?`, g, wrongs(g, [1, 2, g])] : null; },
  () => { const a = pick([4, 6, 8, 9, 10, 12, 15]), b = pick([6, 8, 10, 14, 15, 20]); const l = (a * b) / gcd(a, b); return a !== b ? [`Koji je najmanji zajednički višekratnik brojeva ${a} i ${b}?`, l, [a * b === l ? l * 2 : a * b, l + pick([a, b])]] : null; },
  () => { const y = pick([1990, 1991, 1998, 2000, 2004, 2013, 1969, 1989, 1945]), t = pick([2020, 2025, 2030, 2010]); return t > y ? [`Koliko je godina prošlo od ${y}. do ${t}.?`, t - y, wrongs(t - y, [1, 10])] : null; },
  () => { const n = int(2, 9); return [`Koliko je ${n} × 1000 + ${n} × 100?`, n * 1100, [n * 1010, n * 1001]]; },
  () => { const a = int(2, 9), b = int(2, 9); return [`Koliko je ${a * 10} × ${b * 10}?`, a * b * 100, [a * b * 10, a * b * 1000]]; },
  () => { const a = int(101, 999); return [`Koliko je ${a} × 2?`, a * 2, wrongs(a * 2, [10, 2, 100])]; },
  () => { const a = int(2, 30) * 2; return [`Koliko je polovina od ${a * 10}?`, a * 5, wrongs(a * 5, [5, 10, 50])]; },
  () => { const n = pick([12, 15, 18, 20, 24, 30, 36]); return [`Koliko je trećina od ${n * 3}?`, n, wrongs(n, [1, 3, 2])]; },
  () => { const a = pick([0.5, 1.5, 2.5, 0.25, 0.75, 1.2, 3.5]), b = pick([2, 4, 10]); const v = Math.round(a * b * 100) / 100; return Number.isInteger(v) ? [`Koliko je ${fmt(a)} × ${b}?`, v, wrongs(v, [1, 2])] : null; },
  () => { const n = pick([2, 3, 5, 7, 11, 13, 17, 19, 23, 29]); const c = pick([4, 6, 8, 9, 10, 12, 14, 15, 21, 25, 27]); return [`Koji je od ovih brojeva prost: ${n}, ${c} ili ${c + 2 === n ? c + 4 : c + 2 > 30 ? c * 2 : (c + 2) % 2 ? c * 2 : c + 2}?`, n, null]; },
];

function pl(n, one, few, many) { const m10 = n % 10, m100 = n % 100; if (m10 === 1 && m100 !== 11) return `${n} ${one}`; if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return `${n} ${few}`; return `${n} ${many}`; }
function gcd(a, b) { return b ? gcd(b, a % b) : a; }

const seen = new Set();
const lines = ['# Generirano skriptom scripts/gen-math.mjs — odgovori su izračunati.'];
let guard = 0;
while (lines.length < 201 && guard++ < 20000) {
  const g = pick(gens);
  const r = g();
  if (!r) continue;
  let [q, ans, w] = r;
  if (seen.has(q)) continue;
  if (w === null) {
    // prime question: wrong answers are the two composites mentioned
    const nums = q.match(/\d+/g).map(Number).filter((x) => x !== ans);
    w = nums;
    if (nums.some((x) => isPrime(x))) continue;
  }
  w = [...new Set(w.map(Number))].filter((x) => x !== ans);
  if (w.length < 2) continue;
  seen.add(q);
  lines.push(`${q} | ${fmt(ans)} | | ${fmt(w[0])}; ${fmt(w[1])}`);
}
function isPrime(n) { if (n < 2) return false; for (let i = 2; i * i <= n; i++) if (n % i === 0) return false; return true; }

const out = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', 'questions', 'matematika.txt');
fs.writeFileSync(out, lines.join('\n') + '\n');
console.log(`${lines.length - 1} math questions written`);
