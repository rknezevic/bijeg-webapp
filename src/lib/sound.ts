/**
 * All game sounds are synthesised with the Web Audio API — no audio files needed.
 * Browsers only allow sound after the first click/tap, so unlockAudio() is called
 * on the first pointerdown anywhere in the app.
 */

type Wave = OscillatorType;

let ctx: AudioContext | null = null;
let master: GainNode | null = null;
let muted = readMuted();

function readMuted() {
  try {
    return localStorage.getItem('bijeg.muted') === '1';
  } catch {
    return false;
  }
}

export function isMuted() {
  return muted;
}

export function setMuted(value: boolean) {
  muted = value;
  try {
    localStorage.setItem('bijeg.muted', value ? '1' : '0');
  } catch {
    /* ignore */
  }
  if (master) master.gain.value = value ? 0 : 0.9;
}

function ac(): AudioContext | null {
  if (!ctx) {
    const C = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!C) return null;
    ctx = new C();
    master = ctx.createGain();
    master.gain.value = muted ? 0 : 0.9;
    const comp = ctx.createDynamicsCompressor();
    master.connect(comp).connect(ctx.destination);
  }
  if (ctx.state === 'suspended') ctx.resume().catch(() => undefined);
  return ctx;
}

export function unlockAudio() {
  ac();
}

interface ToneOpts {
  type?: Wave;
  gain?: number;
  attack?: number;
  slideTo?: number;
  filter?: number;
  vibrato?: number;
}

function tone(freq: number, at: number, dur: number, o: ToneOpts = {}) {
  const c = ac();
  if (!c || !master || muted) return;
  const t = c.currentTime + at;
  const osc = c.createOscillator();
  const g = c.createGain();
  osc.type = o.type ?? 'sine';
  osc.frequency.setValueAtTime(freq, t);
  if (o.slideTo) osc.frequency.exponentialRampToValueAtTime(o.slideTo, t + dur);
  if (o.vibrato) {
    const lfo = c.createOscillator();
    const lg = c.createGain();
    lfo.frequency.value = 6;
    lg.gain.value = o.vibrato;
    lfo.connect(lg).connect(osc.frequency);
    lfo.start(t);
    lfo.stop(t + dur + 0.05);
  }
  const peak = o.gain ?? 0.2;
  const atk = o.attack ?? 0.005;
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(peak, t + atk);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  let node: AudioNode = osc;
  if (o.filter) {
    const f = c.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = o.filter;
    osc.connect(f);
    node = f;
  }
  node.connect(g).connect(master);
  osc.start(t);
  osc.stop(t + dur + 0.05);
}

function noise(at: number, dur: number, gain: number, freq: number, q = 1, type: BiquadFilterType = 'bandpass') {
  const c = ac();
  if (!c || !master || muted) return;
  const t = c.currentTime + at;
  const len = Math.max(1, Math.floor(c.sampleRate * dur));
  const buf = c.createBuffer(1, len, c.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  const src = c.createBufferSource();
  src.buffer = buf;
  const f = c.createBiquadFilter();
  f.type = type;
  f.frequency.value = freq;
  f.Q.value = q;
  const g = c.createGain();
  g.gain.setValueAtTime(gain, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f).connect(g).connect(master);
  src.start(t);
  src.stop(t + dur + 0.02);
}

const N = (semi: number) => 440 * Math.pow(2, semi / 12); // semitones from A4

export const sfx = {
  /** Someone locked in an A/B/C answer: punchy "dunk-ding". */
  lockIn() {
    tone(110, 0, 0.18, { type: 'square', gain: 0.25, filter: 900 });
    noise(0, 0.08, 0.35, 180, 0.8, 'lowpass');
    tone(N(15), 0.05, 0.35, { type: 'triangle', gain: 0.18 });
    tone(N(22), 0.09, 0.4, { type: 'sine', gain: 0.1 });
  },

  /** One clock tick. `step` counts up so the last ticks get higher and louder. */
  tick(step: number, urgent: boolean) {
    const hi = step % 2 === 0;
    noise(0, 0.035, urgent ? 0.6 : 0.4, hi ? 2600 : 1800, 6);
    tone(hi ? 1500 + step * 40 : 1100 + step * 40, 0, 0.05, { type: 'triangle', gain: urgent ? 0.18 : 0.12 });
    if (hi) tone(55, 0, 0.16, { type: 'sine', gain: urgent ? 0.4 : 0.28 }); // heartbeat thump
  },

  /** Time is up — buzzer. */
  buzzer() {
    tone(150, 0, 0.45, { type: 'sawtooth', gain: 0.2, filter: 1200 });
    tone(155, 0, 0.45, { type: 'square', gain: 0.1, filter: 800 });
  },

  /** Correct answer: bright three-note jingle. */
  correct() {
    [0, 4, 7, 12].forEach((s, i) => tone(N(3 + s), i * 0.07, 0.25, { type: 'triangle', gain: 0.16 }));
  },

  /** Wrong answer: two low "bonk" notes. */
  wrong() {
    tone(N(-14), 0, 0.18, { type: 'square', gain: 0.12, filter: 1400 });
    tone(N(-18), 0.16, 0.3, { type: 'square', gain: 0.12, filter: 1200 });
  },

  /** Chaser moves one step closer: ominous low hit. */
  chaserStep() {
    tone(N(-33), 0, 0.5, { type: 'sawtooth', gain: 0.2, filter: 500, slideTo: N(-36) });
    noise(0, 0.25, 0.3, 120, 0.7, 'lowpass');
  },

  /** Player reached home — triumphant brass fanfare with cymbal swell. */
  home() {
    const brass = (semi: number, at: number, dur: number, g = 0.12) => {
      tone(N(semi), at, dur, { type: 'sawtooth', gain: g, filter: 2400, attack: 0.03, vibrato: dur > 0.5 ? 4 : 0 });
      tone(N(semi) * 1.005, at, dur, { type: 'square', gain: g * 0.5, filter: 1800, attack: 0.03 });
    };
    // da-da-da-DAAA
    brass(-2, 0, 0.14);
    brass(-2, 0.16, 0.14);
    brass(-2, 0.32, 0.14);
    brass(3, 0.48, 0.5);
    brass(1, 1.0, 0.18);
    brass(3, 1.2, 0.18);
    // big final chord
    [3, 7, 10, 15].forEach((s) => brass(s, 1.42, 1.5, 0.09));
    tone(N(-21), 1.42, 1.5, { type: 'sawtooth', gain: 0.16, filter: 400 });
    noise(1.38, 1.6, 0.12, 6000, 0.5, 'highpass');
    noise(0.46, 0.5, 0.08, 7000, 0.5, 'highpass');
  },

  /** Player caught — sad trombone "wah-wah-wah-waaah" + low boom. */
  caught() {
    noise(0, 0.6, 0.5, 90, 0.7, 'lowpass');
    tone(N(-36), 0, 0.8, { type: 'sine', gain: 0.35, slideTo: N(-44) });
    const notes = [-14, -15, -16];
    notes.forEach((s, i) => tone(N(s), 0.45 + i * 0.38, 0.34, { type: 'sawtooth', gain: 0.14, filter: 900, attack: 0.04 }));
    tone(N(-17), 0.45 + 3 * 0.38, 1.3, { type: 'sawtooth', gain: 0.14, filter: 800, attack: 0.04, vibrato: 6, slideTo: N(-19) });
  },

  /** Dramatic sting before each new player / the final. */
  sting() {
    tone(N(-33), 0, 0.9, { type: 'sawtooth', gain: 0.18, filter: 600 });
    tone(N(-21), 0, 0.9, { type: 'sawtooth', gain: 0.1, filter: 900 });
    tone(N(-26), 0.35, 0.9, { type: 'sawtooth', gain: 0.12, filter: 800 });
    noise(0, 0.4, 0.25, 100, 0.7, 'lowpass');
  },
};
