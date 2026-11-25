/**
 * Game sounds, synthesised with the Web Audio API (no audio files).
 * Everything runs through a small "studio" chain — saturation, a big reverb and a
 * compressor — so the sounds feel loud and cinematic rather than like beeps.
 * Browsers only allow sound after the first click/tap: App calls unlockAudio() then.
 */

let ctx: AudioContext | null = null;
let bus: GainNode | null = null; // dry input
let verbIn: GainNode | null = null; // reverb send
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
}

function impulse(c: AudioContext, seconds: number, decay: number) {
  const len = Math.floor(c.sampleRate * seconds);
  const buf = c.createBuffer(2, len, c.sampleRate);
  for (let ch = 0; ch < 2; ch++) {
    const d = buf.getChannelData(ch);
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
  }
  return buf;
}

function saturationCurve(amount: number) {
  const n = 1024;
  const curve = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const x = (i * 2) / n - 1;
    curve[i] = ((1 + amount) * x) / (1 + amount * Math.abs(x));
  }
  return curve;
}

function ac(): AudioContext | null {
  if (!ctx) {
    const C = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!C) return null;
    ctx = new C();
    const master = ctx.createGain();
    master.gain.value = 1.1;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -16;
    comp.knee.value = 6;
    comp.ratio.value = 6;
    comp.attack.value = 0.003;
    comp.release.value = 0.2;
    const sat = ctx.createWaveShaper();
    sat.curve = saturationCurve(3);
    sat.oversample = '2x';
    bus = ctx.createGain();
    bus.gain.value = 0.9;
    const verb = ctx.createConvolver();
    verb.buffer = impulse(ctx, 2.6, 2.8);
    verbIn = ctx.createGain();
    verbIn.gain.value = 1;
    const verbOut = ctx.createGain();
    verbOut.gain.value = 0.35;
    bus.connect(sat);
    verbIn.connect(verb).connect(verbOut).connect(sat);
    sat.connect(comp).connect(master).connect(ctx.destination);
  }
  if (ctx.state === 'suspended') ctx.resume().catch(() => undefined);
  return ctx;
}

export function unlockAudio() {
  ac();
}

interface ToneOpts {
  type?: OscillatorType;
  gain?: number;
  attack?: number;
  slideTo?: number;
  filter?: number;
  filterTo?: number;
  vibrato?: number;
  verb?: number; // 0..1 reverb send
  detune?: number;
  dest?: AudioNode; // route into a group instead of the main bus
}

function out(c: AudioContext, node: AudioNode, verb: number, dest?: AudioNode) {
  node.connect(dest ?? bus!);
  if (verb > 0) {
    const s = c.createGain();
    s.gain.value = verb;
    node.connect(s).connect(verbIn!);
  }
}

function tone(freq: number, at: number, dur: number, o: ToneOpts = {}) {
  const c = ac();
  if (!c || !bus || muted) return;
  const t = c.currentTime + at;
  const osc = c.createOscillator();
  const g = c.createGain();
  osc.type = o.type ?? 'sine';
  osc.frequency.setValueAtTime(freq, t);
  if (o.detune) osc.detune.value = o.detune;
  if (o.slideTo) osc.frequency.exponentialRampToValueAtTime(o.slideTo, t + dur);
  if (o.vibrato) {
    const lfo = c.createOscillator();
    const lg = c.createGain();
    lfo.frequency.value = 5.5;
    lg.gain.value = o.vibrato;
    lfo.connect(lg).connect(osc.frequency);
    lfo.start(t);
    lfo.stop(t + dur + 0.1);
  }
  const peak = o.gain ?? 0.2;
  const atk = o.attack ?? 0.004;
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(peak, t + atk);
  g.gain.setValueAtTime(peak, t + Math.max(atk, dur * 0.6));
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  let node: AudioNode = osc;
  if (o.filter) {
    const f = c.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.setValueAtTime(o.filter, t);
    if (o.filterTo) f.frequency.exponentialRampToValueAtTime(o.filterTo, t + dur);
    f.Q.value = 2;
    osc.connect(f);
    node = f;
  }
  node.connect(g);
  out(c, g, o.verb ?? 0.15, o.dest);
  osc.start(t);
  osc.stop(t + dur + 0.1);
}

function noise(at: number, dur: number, gain: number, freq: number, q = 1, type: BiquadFilterType = 'bandpass', verb = 0.1, freqTo?: number, attack = 0.002) {
  const c = ac();
  if (!c || !bus || muted) return;
  const t = c.currentTime + at;
  const len = Math.max(1, Math.floor(c.sampleRate * dur));
  const buf = c.createBuffer(1, len, c.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  const src = c.createBufferSource();
  src.buffer = buf;
  const f = c.createBiquadFilter();
  f.type = type;
  f.frequency.setValueAtTime(freq, t);
  if (freqTo) f.frequency.exponentialRampToValueAtTime(freqTo, t + dur);
  f.Q.value = q;
  const g = c.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(gain, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f).connect(g);
  out(c, g, verb);
  src.start(t);
  src.stop(t + dur + 0.05);
}

/** Deep cinematic impact: sub drop + body + noise crack. */
function impact(at: number, size = 1) {
  tone(90, at, 1.2 * size, { type: 'sine', gain: 0.9, slideTo: 32, verb: 0.3 });
  tone(180, at, 0.25, { type: 'triangle', gain: 0.5, slideTo: 60 });
  noise(at, 0.18, 0.9, 1500, 0.6, 'lowpass', 0.5, 200);
  noise(at, 1.4 * size, 0.35, 6000, 0.4, 'highpass', 0.6, 2500, 0.01);
}

/** Rising tension "whoosh" leading into a hit. */
function riser(at: number, dur: number, gain = 0.4) {
  noise(at, dur, gain, 300, 1.5, 'bandpass', 0.4, 6000, dur * 0.9);
  tone(80, at, dur, { type: 'sawtooth', gain: gain * 0.4, slideTo: 320, filter: 400, filterTo: 3000, attack: dur * 0.9, verb: 0.3 });
}

const N = (semi: number) => 440 * Math.pow(2, semi / 12); // semitones from A4

function brass(semi: number, at: number, dur: number, g = 0.16) {
  [-7, 0, 7].forEach((d) =>
    tone(N(semi), at, dur, { type: 'sawtooth', gain: g / 2, detune: d, filter: 700, filterTo: 3200, attack: 0.04, vibrato: dur > 0.5 ? 3 : 0, verb: 0.35 }),
  );
  tone(N(semi - 12), at, dur, { type: 'square', gain: g * 0.4, filter: 900, attack: 0.03, verb: 0.2 });
}

function timpani(at: number, semi = -33, g = 0.8) {
  tone(N(semi), at, 0.9, { type: 'sine', gain: g, slideTo: N(semi) * 0.92, verb: 0.4 });
  noise(at, 0.12, 0.5, 300, 1, 'lowpass', 0.4);
}

export const sfx = {
  /** Someone locked in an answer on the board: heavy slam + metallic ring. */
  lockIn() {
    impact(0, 0.6);
    tone(N(19), 0.02, 0.9, { type: 'triangle', gain: 0.22, verb: 0.6 });
    tone(N(26), 0.02, 0.7, { type: 'sine', gain: 0.14, verb: 0.6 });
    tone(N(19) * 2.76, 0.02, 0.5, { type: 'sine', gain: 0.06, verb: 0.6 }); // bell partial
  },

  /**
   * One clock tick of the 4-second countdown. Sharp, loud, dry woodblock + metal click,
   * with a sub "heartbeat" on every other tick. `urgent` = last second.
   */
  tick(step: number, urgent: boolean) {
    const hi = step % 2 === 0;
    const pitch = (hi ? 2200 : 1650) * (1 + step * 0.03);
    noise(0, 0.03, urgent ? 1.2 : 1.0, pitch * 1.6, 8, 'bandpass', 0.05);
    noise(0, 0.012, 0.9, 7000, 0.7, 'highpass', 0);
    tone(pitch, 0, 0.06, { type: 'square', gain: urgent ? 0.32 : 0.26, filter: 5000, verb: 0.05 });
    tone(pitch * 1.5, 0, 0.04, { type: 'triangle', gain: 0.18, verb: 0.05 });
    if (hi || urgent) tone(58, 0, 0.22, { type: 'sine', gain: urgent ? 0.9 : 0.75, slideTo: 40, verb: 0 });
  },

  /** Rising drone under the countdown. Returns a function that fades it out early. */
  tension(seconds: number): () => void {
    const c = ac();
    if (!c || !bus || muted) return () => undefined;
    const grp = c.createGain();
    grp.connect(bus);
    tone(N(-33), 0, seconds, { type: 'sawtooth', gain: 0.14, slideTo: N(-21), filter: 300, filterTo: 2400, attack: 0.3, verb: 0, dest: grp });
    tone(N(-32), 0, seconds, { type: 'sawtooth', gain: 0.12, slideTo: N(-20), filter: 300, filterTo: 2000, attack: 0.3, verb: 0, dest: grp });
    return () => {
      const t = c.currentTime;
      grp.gain.setValueAtTime(grp.gain.value, t);
      grp.gain.linearRampToValueAtTime(0, t + 0.15);
    };
  },

  /** Time is up — harsh game-show buzzer. */
  buzzer() {
    [0, 6, 13].forEach((d) => tone(N(-26), 0, 0.7, { type: 'sawtooth', gain: 0.22, detune: d * 10, filter: 2500, verb: 0.2 }));
    tone(N(-38), 0, 0.7, { type: 'square', gain: 0.25, filter: 600 });
  },

  /** Correct answer: bright rising sparkle. */
  correct() {
    [0, 4, 7, 12, 16].forEach((s, i) => tone(N(7 + s), i * 0.055, 0.45, { type: 'triangle', gain: 0.18, verb: 0.5 }));
    noise(0.2, 0.5, 0.12, 9000, 0.5, 'highpass', 0.6);
  },

  /** Wrong answer: dissonant low stab. */
  wrong() {
    tone(N(-21), 0, 0.5, { type: 'sawtooth', gain: 0.22, filter: 1400, filterTo: 300, verb: 0.3 });
    tone(N(-20), 0, 0.5, { type: 'sawtooth', gain: 0.18, filter: 1400, filterTo: 300, verb: 0.3 });
    tone(N(-33), 0, 0.4, { type: 'sine', gain: 0.5, slideTo: 45 });
  },

  /** Chaser takes a step: ominous hit with dark brass. */
  chaserStep() {
    impact(0, 0.8);
    brass(-26, 0.02, 0.9, 0.22);
    brass(-25, 0.02, 0.9, 0.12);
  },

  /** Player made it home — big fanfare with timpani roll and cymbal. */
  home() {
    riser(0, 0.6, 0.35);
    for (let i = 0; i < 6; i++) timpani(0.1 + i * 0.07, -33, 0.35 + i * 0.06);
    impact(0.6, 1);
    brass(-2, 0.6, 0.16);
    brass(-2, 0.78, 0.16);
    brass(-2, 0.96, 0.16);
    brass(3, 1.14, 0.55, 0.2);
    brass(1, 1.72, 0.16);
    brass(3, 1.9, 0.16);
    timpani(2.1, -33, 1);
    [3, 7, 10, 15, 19].forEach((s) => brass(s, 2.1, 2.2, 0.13));
    tone(N(-21), 2.1, 2.2, { type: 'sawtooth', gain: 0.25, filter: 500 });
    noise(2.1, 2.4, 0.4, 5000, 0.4, 'highpass', 0.7, 3000, 0.01);
    [0, 4, 7, 12, 16, 19, 24].forEach((s, i) => tone(N(15 + s), 2.2 + i * 0.05, 0.6, { type: 'triangle', gain: 0.1, verb: 0.7 }));
  },

  /** Player caught — massive impact, dissonant brass, then a falling sad trombone. */
  caught() {
    riser(0, 0.45, 0.4);
    impact(0.45, 1.6);
    impact(0.47, 1.2);
    brass(-26, 0.45, 1.2, 0.26);
    brass(-25, 0.45, 1.2, 0.2);
    brass(-19, 0.45, 1.2, 0.14);
    const start = 1.6;
    [-14, -15, -16].forEach((s, i) =>
      tone(N(s), start + i * 0.42, 0.38, { type: 'sawtooth', gain: 0.2, filter: 1100, attack: 0.05, verb: 0.3 }),
    );
    tone(N(-17), start + 3 * 0.42, 1.6, { type: 'sawtooth', gain: 0.2, filter: 1000, filterTo: 300, attack: 0.05, vibrato: 7, slideTo: N(-20), verb: 0.4 });
  },

  /** Dramatic sting at the start of each round. */
  sting() {
    riser(0, 0.5, 0.3);
    impact(0.5, 1.1);
    brass(-21, 0.5, 1.4, 0.22);
    brass(-14, 0.5, 1.4, 0.16);
    brass(-9, 0.85, 1.1, 0.16);
  },
};
