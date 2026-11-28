export type Phase =
  | 'lobby'
  | 'intro'
  | 'cash'
  | 'h2h_ready'
  | 'offer_set'
  | 'offer_pick'
  | 'h2h'
  | 'h2h_reveal'
  | 'final_intro'
  | 'final_team'
  | 'final_chaser_intro'
  | 'final_chaser'
  | 'final_pushback'
  | 'finished';

export type Category = 'hrvatska' | 'opce' | 'nogomet' | 'sport' | 'geografija' | 'matematika' | 'glazba' | 'stihovi' | 'igrice' | 'filmovi' | 'priroda';

export interface QuestionView {
  id: number;
  text: string;
  cat: Category;
  options?: string[];
  /** song questions: Deezer track + where in the 30 s preview to start */
  audio?: { deezer: number; start: number };
}

export interface CashState {
  q: QuestionView | null;
  correct: number;
  wrong: number;
  skipped: number;
  bank: number;
  last: { seq: number; given: string | null; answer: string; ok: boolean | null } | null;
  /** every answer of the minute, for the host's review */
  log?: CashLogEntry[];
}

export interface CashLogEntry {
  i: number;
  q: string;
  a: string;
  /** what was typed; null = skipped */
  g: string | null;
  ok: boolean | null;
  /** what the automatic check said */
  auto: boolean | null;
}

export interface OfferState {
  bank: number;
  high: number;
  low: number;
  set: boolean;
  choice: 'high' | 'mid' | 'low' | null;
}

export interface H2HState {
  chaser: number;
  player: number;
  amount: number;
  n: number;
  q: QuestionView | null;
  lockP: boolean;
  lockC: boolean;
  /** true once one side has answered: the other has 4 seconds */
  rush?: boolean;
  reveal: {
    correct: number;
    p: number | null;
    c: number | null;
    pOk: boolean;
    cOk: boolean;
    outcome: 'home' | 'caught' | null;
  } | null;
}

export interface FeedEntry {
  seq: number;
  by: 'team' | 'chaser' | 'captain';
  who: string | null;
  given: string | null;
  answer: string | null;
  ok: boolean | null;
}

export interface FinalState {
  finalists: string[];
  captain: string;
  pot: number;
  head: number;
  team: number;
  chaser: number;
  q: QuestionView | null;
  feed: FeedEntry[];
  last: FeedEntry | null;
  remaining: number | null;
  pb: { given: string | null; who: string } | null;
  seq: number;
}

export interface GameState {
  order?: string[];
  idx?: number;
  current?: string;
  pot?: number;
  cash?: CashState;
  offer?: OfferState | null;
  h2h?: H2HState | null;
  final?: FinalState;
  result?: { winner: 'team' | 'chaser'; pot: number; each: number };
  /** players who clicked "Spreman sam" in the current waiting phase */
  ready?: string[];
  /** after the minute: the host has approved the answers */
  approved?: boolean;
}

export interface Room {
  id: string;
  code: string;
  host_user: string;
  phase: Phase;
  phase_ends_at: string | null;
  state: GameState;
  updated_at: string;
}

export interface Player {
  id: string;
  room_id: string;
  user_id: string;
  nickname: string;
  role: 'chaser' | 'player' | null;
  seat: number | null;
  status: 'lobby' | 'waiting' | 'playing' | 'home' | 'caught' | 'spectator' | 'chaser';
  bank: number;
  amount: number;
}
