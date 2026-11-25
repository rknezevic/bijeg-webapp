import { useState } from 'react';
import { Logo, Shell } from '../components/ui';
import { navigate } from '../lib/router';
import { api } from '../lib/api';

export function Home() {
  const [nick, setNick] = useState(() => localStorage.getItem('bijeg.nick') ?? '');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const create = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      localStorage.setItem('bijeg.nick', nick.trim());
      const ref = await api.createRoom(nick);
      navigate(`/s/${ref.code}`);
    } catch (e) {
      setErr((e as Error).message);
      setBusy(false);
    }
  };

  return (
    <Shell>
      <div className="hero">
        <Logo />
        <p className="muted">Kviz u kojem je lovac netko od tvojih prijatelja</p>
      </div>

      <form className="card stack" onSubmit={create}>
        <h1 className="h2">Nova igra</h1>
        <label htmlFor="nick" className="label">
          Tvoj nadimak
        </label>
        <input id="nick" className="input" value={nick} onChange={(e) => setNick(e.target.value)} placeholder="npr. Robi" maxLength={16} />
        {err && <p className="error">{err}</p>}
        <button className="btn btn--blue btn--lg" disabled={busy || nick.trim().length < 2}>
          Napravi sobu
        </button>
        <p className="muted small">Dobit ćeš poveznicu koju šalješ prijateljima. Bez registracije.</p>
      </form>

      <form
        className="card stack"
        onSubmit={(e) => {
          e.preventDefault();
          if (code.trim()) navigate(`/s/${code.trim().toUpperCase()}`);
        }}
      >
        <label htmlFor="code" className="label">
          Imaš kod sobe?
        </label>
        <div className="row">
          <input id="code" className="input input--code" value={code} onChange={(e) => setCode(e.target.value)} placeholder="KX7Q42" maxLength={8} />
          <button className="btn btn--ghost">Uđi</button>
        </div>
      </form>
    </Shell>
  );
}
