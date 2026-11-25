import { useEffect, useState } from 'react';
import { configured, ensureSession } from './lib/supabase';
import { Home } from './screens/Home';
import { RoomPage } from './screens/RoomPage';
import { Shell } from './components/ui';
import { unlockAudio } from './lib/sound';

function usePath() {
  const [path, setPath] = useState(window.location.pathname);
  useEffect(() => {
    const on = () => setPath(window.location.pathname);
    window.addEventListener('popstate', on);
    return () => window.removeEventListener('popstate', on);
  }, []);
  return path;
}

export function App() {
  const path = usePath();
  const [uid, setUid] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    const unlock = () => unlockAudio();
    window.addEventListener('pointerdown', unlock);
    window.addEventListener('keydown', unlock);
    return () => {
      window.removeEventListener('pointerdown', unlock);
      window.removeEventListener('keydown', unlock);
    };
  }, []);

  useEffect(() => {
    if (!configured) return;
    ensureSession().then(setUid).catch((e: Error) => setErr(e.message));
  }, []);

  if (!configured) {
    return (
      <Shell>
        <div className="card">
          <h1 className="h2">Nedostaje konfiguracija</h1>
          <p className="muted">
            Kopiraj <code>.env.example</code> u <code>.env</code> i upiši URL i anon ključ svog Supabase projekta.
          </p>
        </div>
      </Shell>
    );
  }
  if (err) {
    return (
      <Shell>
        <div className="card">
          <p>{err}</p>
        </div>
      </Shell>
    );
  }
  if (!uid) {
    return (
      <Shell>
        <p className="muted center">Spajanje…</p>
      </Shell>
    );
  }

  const m = path.match(/^\/s\/([A-Za-z0-9]{4,8})\/?$/);
  if (m) return <RoomPage code={m[1].toUpperCase()} uid={uid} />;
  return <Home />;
}
