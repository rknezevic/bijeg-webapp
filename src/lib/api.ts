import { supabase } from './supabase';

async function call<T = unknown>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data as T;
}

export interface RoomRef {
  room_id: string;
  code: string;
}

export interface RoomInfo {
  code: string;
  phase: string;
  host: string | null;
  count: number;
  member: boolean;
}

export const api = {
  serverNow: () => call<string>('server_now', {}),
  createRoom: (nick: string) => call<RoomRef>('create_room', { p_nick: nick }),
  roomInfo: (code: string) => call<RoomInfo | null>('room_info', { p_code: code }),
  joinRoom: (code: string, nick: string) => call<RoomRef>('join_room', { p_code: code, p_nick: nick }),
  chooseRole: (room: string, role: 'chaser' | 'player' | null, seat?: number) =>
    call('choose_role', { p_room: room, p_role: role, p_seat: seat ?? null }),
  startGame: (room: string) => call('start_game', { p_room: room }),
  resetRoom: (room: string) => call('reset_room', { p_room: room }),
  setReady: (room: string) => call('set_ready', { p_room: room }),
  forceReady: (room: string) => call('force_ready', { p_room: room }),
  reviewToggle: (room: string, i: number) => call('review_toggle', { p_room: room, p_i: i }),
  reviewApprove: (room: string) => call('review_approve', { p_room: room }),
  tick: (room: string) => call<string>('tick', { p_room: room }),
  cashAnswer: (room: string, qid: number, text: string) =>
    call<{ ok?: boolean }>('cash_answer', { p_room: room, p_qid: qid, p_text: text }),
  setOffers: (room: string, high: number, low: number) =>
    call('set_offers', { p_room: room, p_high: high, p_low: low }),
  pickOffer: (room: string, choice: 'high' | 'mid' | 'low') =>
    call('pick_offer', { p_room: room, p_choice: choice }),
  h2hAnswer: (room: string, qid: number, idx: number) =>
    call('h2h_answer', { p_room: room, p_qid: qid, p_idx: idx }),
  finalAnswer: (room: string, qid: number, text: string) =>
    call<{ ok?: boolean; stale?: boolean }>('final_answer', { p_room: room, p_qid: qid, p_text: text }),
};
