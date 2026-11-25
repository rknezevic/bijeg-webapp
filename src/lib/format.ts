import type { Category, Phase } from '../types';

const nf = new Intl.NumberFormat('hr-HR');
export const euro = (n: number | null | undefined) => `${nf.format(n ?? 0)} €`;

export const CATEGORY: Record<Category, string> = {
  hrvatska: 'Hrvatska',
  opce: 'Opće znanje',
  nogomet: 'Nogomet',
  sport: 'Sport',
  geografija: 'Geografija',
  matematika: 'Matematika',
  glazba: 'Prepoznaj pjesmu',
  stihovi: 'Nadopuni stih',
};

/** Full length of each timed phase, used to draw the countdown ring. */
export const PHASE_SECONDS: Partial<Record<Phase, number>> = {
  intro: 5,
  cash: 60,
  offer_set: 25,
  offer_pick: 15,
  h2h: 20,
  h2h_reveal: 4,
  final_intro: 6,
  final_team: 120,
  final_chaser_intro: 6,
  final_chaser: 120,
  final_pushback: 10,
};

export const PHASE_LABEL: Record<Phase, string> = {
  lobby: 'Predvorje',
  intro: 'Sljedeći igrač',
  cash: 'Brzi krug',
  offer_set: 'Ponuda lovca',
  offer_pick: 'Ponuda lovca',
  h2h: 'Dvoboj',
  h2h_reveal: 'Dvoboj',
  final_intro: 'Finale',
  final_team: 'Finale · tim',
  final_chaser_intro: 'Finale · lovac',
  final_chaser: 'Finale · lovac',
  final_pushback: 'Finale · kapetan',
  finished: 'Kraj igre',
};

export function clock(ms: number) {
  const s = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

/** Croatian plural for "korak": 1 korak, 2 koraka, 5 koraka */
export function koraka(n: number) {
  const m10 = n % 10;
  const m100 = n % 100;
  if (m10 === 1 && m100 !== 11) return `${n} korak`;
  return `${n} koraka`;
}
