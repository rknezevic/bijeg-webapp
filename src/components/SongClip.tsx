import { useEffect, useRef, useState } from 'react';

/** Plays a slice of a Deezer 30-second preview for "Koja je ovo pjesma?" questions. */

const CLIP_SECONDS = 15;
const previewCache = new Map<number, string>();

function jsonp<T>(url: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const cb = `dz_${Math.random().toString(36).slice(2)}`;
    const script = document.createElement('script');
    const w = window as unknown as Record<string, unknown>;
    const timer = window.setTimeout(() => {
      cleanup();
      reject(new Error('timeout'));
    }, 8000);
    function cleanup() {
      window.clearTimeout(timer);
      delete w[cb];
      script.remove();
    }
    w[cb] = (data: T) => {
      cleanup();
      resolve(data);
    };
    script.onerror = () => {
      cleanup();
      reject(new Error('network'));
    };
    script.src = `${url}${url.includes('?') ? '&' : '?'}output=jsonp&callback=${cb}`;
    document.body.appendChild(script);
  });
}

async function previewUrl(id: number): Promise<string> {
  const cached = previewCache.get(id);
  if (cached) return cached;
  const data = await jsonp<{ preview?: string }>(`https://api.deezer.com/track/${id}`);
  if (!data.preview) throw new Error('no preview');
  previewCache.set(id, data.preview);
  return data.preview;
}

interface Props {
  deezer: number;
  start: number;
  /** start playing automatically (player and chaser); spectators press play */
  autoPlay: boolean;
}

export function SongClip({ deezer, start, autoPlay }: Props) {
  const audio = useRef<HTMLAudioElement | null>(null);
  const stopTimer = useRef<number>();
  const [state, setState] = useState<'loading' | 'ready' | 'playing' | 'error'>('loading');

  const stop = () => {
    window.clearTimeout(stopTimer.current);
    const a = audio.current;
    if (!a) return;
    // short fade-out
    const step = () => {
      if (!a || a.paused) return;
      a.volume = Math.max(0, a.volume - 0.1);
      if (a.volume <= 0.05) {
        a.pause();
        setState('ready');
      } else window.setTimeout(step, 40);
    };
    step();
  };

  const play = async () => {
    const a = audio.current;
    if (!a) return;
    try {
      a.volume = 0.7;
      a.currentTime = start;
      await a.play();
      setState('playing');
      window.clearTimeout(stopTimer.current);
      stopTimer.current = window.setTimeout(stop, CLIP_SECONDS * 1000);
    } catch {
      setState('ready'); // autoplay blocked: show the button
    }
  };

  useEffect(() => {
    let cancelled = false;
    setState('loading');
    const a = new Audio();
    a.preload = 'auto';
    audio.current = a;
    a.onended = () => setState('ready');
    previewUrl(deezer)
      .then((url) => {
        if (cancelled) return;
        a.src = url;
        a.addEventListener(
          'loadedmetadata',
          () => {
            if (cancelled) return;
            setState('ready');
            if (autoPlay) play();
          },
          { once: true },
        );
        a.load();
      })
      .catch(() => !cancelled && setState('error'));
    return () => {
      cancelled = true;
      window.clearTimeout(stopTimer.current);
      a.pause();
      a.src = '';
      audio.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [deezer, start]);

  if (state === 'error') {
    return <div className="song song--error">Isječak nije dostupan — odaberi po osjećaju.</div>;
  }
  return (
    <div className={`song${state === 'playing' ? ' is-playing' : ''}`}>
      <div className="song__bars" aria-hidden="true">
        {Array.from({ length: 12 }, (_, i) => (
          <span key={i} style={{ animationDelay: `${(i % 6) * 0.09}s` }} />
        ))}
      </div>
      <button
        type="button"
        className="btn btn--gold song__btn"
        onClick={() => (state === 'playing' ? stop() : play())}
        disabled={state === 'loading'}
      >
        {state === 'loading' ? 'Učitavanje…' : state === 'playing' ? '■ Zaustavi' : '▶ Pusti isječak'}
      </button>
    </div>
  );
}
