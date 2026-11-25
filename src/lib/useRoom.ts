import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from './supabase';
import { api } from './api';
import type { Player, Room } from '../types';

/**
 * Live view of one room: the room row, its players, and a clock that is
 * synced to the server. Also nudges the server (tick) when a deadline passes.
 */
export function useRoom(roomId: string) {
  const [room, setRoom] = useState<Room | null>(null);
  const [players, setPlayers] = useState<Player[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(Date.now());
  const offset = useRef(0);
  const lastTick = useRef(0);
  const roomRef = useRef<Room | null>(null);
  roomRef.current = room;

  const refresh = useCallback(async () => {
    const [r, p] = await Promise.all([
      supabase.from('rooms').select('*').eq('id', roomId).single(),
      supabase.from('room_players').select('*').eq('room_id', roomId).order('joined_at'),
    ]);
    if (r.error) {
      setError('Soba nije dostupna.');
      return;
    }
    setRoom((prev) => newer(prev, r.data as Room));
    if (!p.error) setPlayers(p.data as Player[]);
  }, [roomId]);

  // Server clock offset (median of a few samples).
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const samples: number[] = [];
      for (let i = 0; i < 3; i++) {
        const t0 = Date.now();
        try {
          const s = await api.serverNow();
          const t1 = Date.now();
          samples.push(new Date(s).getTime() - (t0 + t1) / 2);
        } catch {
          /* ignore */
        }
      }
      if (!cancelled && samples.length) {
        samples.sort((a, b) => a - b);
        offset.current = samples[Math.floor(samples.length / 2)];
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Initial load + realtime + safety refresh.
  useEffect(() => {
    refresh();
    const channel = supabase
      .channel(`room-${roomId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` }, (payload) => {
        if (payload.new && 'id' in payload.new) setRoom((prev) => newer(prev, payload.new as Room));
      })
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'room_players', filter: `room_id=eq.${roomId}` },
        (payload) => {
          if (payload.eventType === 'DELETE') {
            const old = payload.old as Partial<Player>;
            setPlayers((list) => list.filter((p) => p.id !== old.id));
            return;
          }
          const row = payload.new as Player;
          setPlayers((list) => {
            const i = list.findIndex((p) => p.id === row.id);
            if (i === -1) return [...list, row];
            const copy = list.slice();
            copy[i] = row;
            return copy;
          });
        },
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') refresh();
      });

    const poll = window.setInterval(refresh, 8000);
    const onVisible = () => document.visibilityState === 'visible' && refresh();
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      supabase.removeChannel(channel);
      window.clearInterval(poll);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [roomId, refresh]);

  // Local clock + deadline nudges.
  useEffect(() => {
    const id = window.setInterval(() => {
      const t = Date.now() + offset.current;
      setNow(t);
      const r = roomRef.current;
      if (!r?.phase_ends_at) return;
      const ends = new Date(r.phase_ends_at).getTime();
      if (t >= ends + 150 && Date.now() - lastTick.current > 1200) {
        lastTick.current = Date.now();
        api.tick(r.id).then(refresh).catch(() => undefined);
      }
    }, 200);
    return () => window.clearInterval(id);
  }, [refresh]);

  return { room, players, error, now, refresh };
}

/** Realtime and refetch can arrive out of order — keep the most recent row. */
function newer(prev: Room | null, next: Room): Room {
  if (!prev) return next;
  return new Date(next.updated_at).getTime() >= new Date(prev.updated_at).getTime() ? next : prev;
}
