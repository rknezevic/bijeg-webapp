import { useEffect, useState } from 'react';
import { Logo, Shell } from '../components/ui';
import { navigate } from '../lib/router';
import { api, type RoomInfo } from '../lib/api';
import { Game } from './Game';

/** Resolves a room code: shows the nickname form if needed, then the game. */
export function RoomPage({ code, uid }: { code: string; uid: string }) {
  const [info, setInfo] = useState<RoomInfo | null | undefined>(undefined);
  const [roomId, setRoomId] = useState<string | null>(null);
  const [nick, setNick] = useState(() => localStorage.getItem('bijeg.nick') ?? '');
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    api
      .roomInfo(code)
      .then(async (i) => {
        if (cancelled) return;
        setInfo(i);
        if (i?.member) {
          const ref = await api.joinRoom(code, '');
          if (!cancelled) setRoomId(ref.room_id);
        }
      })
      .catch((e: Error) => setErr(e.message));
    return () => {
      cancelled = true;
    };
  }, [code]);

  if (roomId) return <Game roomId={roomId} uid={uid} />;

  if (info === null) {
    return (
      <Shell>
        <div className="hero">
          <Logo />
        </div>
        <div className="card stack">
          <h1 className="h2">Soba {code} ne postoji</h1>
          <button className="btn btn--blue" onClick={() => navigate('/')}>
            Na početak
          </button>
        </div>
      </Shell>
    );
  }

  if (info === undefined || info.member) {
    return (
      <Shell>
        <p className="muted center">{err ?? 'Učitavanje sobe…'}</p>
      </Shell>
    );
  }

  const join = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      localStorage.setItem('bijeg.nick', nick.trim());
      const ref = await api.joinRoom(code, nick);
      setRoomId(ref.room_id);
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
      <div className="card invite">
        <span className="eyebrow">Pozvan si u sobu</span>
        <span className="invite__code">{info.code}</span>
        <span className="muted small">
          Domaćin: {info.host ?? '—'} · unutra: {info.count}
          {info.phase !== 'lobby' && ' · igra je u tijeku, ulaziš kao gledatelj'}
        </span>
      </div>
      <form className="card stack" onSubmit={join}>
        <label htmlFor="nick" className="label">
          Tvoj nadimak
        </label>
        <input id="nick" className="input" value={nick} onChange={(e) => setNick(e.target.value)} placeholder="npr. Marko" maxLength={16} autoFocus />
        <p className="muted small">Ulogu — lovac ili igrač — biraš u predvorju.</p>
        {err && <p className="error">{err}</p>}
        <button className="btn btn--blue btn--lg" disabled={busy || nick.trim().length < 2}>
          Uđi u sobu
        </button>
      </form>
      <p className="muted small center">Bez registracije · 1 lovac + 2–4 igrača</p>
    </Shell>
  );
}
