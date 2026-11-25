import { useEffect, useRef } from 'react';
import { sfx } from './sound';
import type { Room } from '../types';

/**
 * Plays sounds when the room changes:
 *  - lock-in sound when the player or chaser answers on the board,
 *  - an intense ticking clock for the 4 seconds the other side has left,
 *  - correct / wrong / chaser-step on reveal, fanfare when a player gets home,
 *    sad trombone when caught, and stings at the start of each round.
 * Nothing plays on the first render, only on changes.
 */
export function useGameSounds(room: Room | null, offsetMs: () => number) {
  const prev = useRef<Room | null>(null);

  // One-shot sounds on state transitions.
  useEffect(() => {
    const before = prev.current;
    prev.current = room;
    if (!room || !before) return;
    const ph = room.phase;
    const h = room.state.h2h;
    const hb = before.state.h2h;

    if (ph !== before.phase) {
      if (ph === 'intro' || ph === 'final_intro' || ph === 'final_chaser_intro') sfx.sting();
      if (ph === 'h2h_reveal' && h?.reveal) {
        const r = h.reveal;
        if (r.outcome === 'home') sfx.home();
        else if (r.outcome === 'caught') sfx.caught();
        else {
          if (r.pOk) sfx.correct();
          else sfx.wrong();
          if (r.cOk) window.setTimeout(() => sfx.chaserStep(), 350);
        }
      }
      if (ph === 'finished') {
        if (room.state.result?.winner === 'team') sfx.home();
        else sfx.caught();
      }
      if (ph === 'final_pushback') sfx.wrong();
    }

    // Lock-in on the board (same question, a side just locked).
    if (ph === 'h2h' && h && hb && h.q?.id === hb.q?.id) {
      if ((h.lockP && !hb.lockP) || (h.lockC && !hb.lockC)) sfx.lockIn();
    }

    // Cash builder & final: little feedback after each answer.
    const cl = room.state.cash?.last;
    const cb = before.state.cash?.last;
    if (ph === 'cash' && cl && cl.seq !== cb?.seq) {
      if (cl.ok) sfx.correct();
      else sfx.wrong();
    }
    const fl = room.state.final?.last;
    const fb = before.state.final?.last;
    if (fl && fl.seq !== fb?.seq && (ph === 'final_team' || ph === 'final_chaser')) {
      if (fl.ok && fl.by === 'chaser') sfx.chaserStep();
      else if (fl.ok) sfx.correct();
      else sfx.wrong();
    }
  }, [room]);

  // The 4-second ticking clock once one side has answered.
  const h = room?.state.h2h;
  const rushing = room?.phase === 'h2h' && !!h && h.lockP !== h.lockC;
  const endsAt = room?.phase_ends_at;
  useEffect(() => {
    if (!rushing || !endsAt) return;
    const timers: number[] = [];
    const remaining = new Date(endsAt).getTime() - (Date.now() + offsetMs());
    if (remaining <= 0) return;
    const stopTension = sfx.tension(remaining / 1000);
    // Fast tick-tock every 333 ms, racing every 125 ms in the last second.
    const marks: number[] = [];
    for (let t = remaining; t > 1000; t -= 333) marks.push(t);
    for (let t = Math.min(1000, remaining); t > 0; t -= 125) marks.push(t);
    marks.forEach((left, i) => {
      timers.push(window.setTimeout(() => sfx.tick(i, left <= 1000), remaining - left));
    });
    timers.push(window.setTimeout(() => sfx.buzzer(), remaining));
    return () => {
      timers.forEach((t) => window.clearTimeout(t));
      stopTension();
    };
  }, [rushing, endsAt, offsetMs]);
}
