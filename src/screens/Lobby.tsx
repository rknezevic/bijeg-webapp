import { useState } from 'react';
import { api } from '../lib/api';
import type { Ctx } from './Game';

export function Lobby({ ctx }: { ctx: Ctx }) {
  const { room, players, me, isHost, chaser } = ctx;
  const [copied, setCopied] = useState(false);
  const link = `${window.location.origin}/s/${room.code}`;
  const seated = players.filter((p) => p.role === 'player');
  const choosing = players.filter((p) => !p.role);
  const canStart = !!chaser && seated.length >= 2 && seated.length <= 4;
  const host = players.find((p) => p.user_id === room.host_user);

  const share = async () => {
    try {
      if (navigator.share && /Mobi|Android/i.test(navigator.userAgent)) {
        await navigator.share({ title: 'BIJEG — kviz', text: 'Uđi u moju sobu:', url: link });
      } else {
        await navigator.clipboard.writeText(link);
        setCopied(true);
        window.setTimeout(() => setCopied(false), 2000);
      }
    } catch {
      /* user cancelled */
    }
  };

  return (
    <div className="col">
      <div className="row-between">
        <div>
          <span className="eyebrow">Soba</span>
          <div className="room-code">{room.code}</div>
        </div>
        <button type="button" className="btn btn--pill" onClick={share}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7" />
            <path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7" />
          </svg>
          {copied ? 'Kopirano!' : 'Pozovi prijatelje'}
        </button>
      </div>

      <h1 className="h1">Odaberi ulogu</h1>

      <section className="stack-sm">
        <span className="eyebrow txt-red">Lovac · 1 mjesto</span>
        {chaser ? (
          <div className="seat seat--chaser">
            <span className="avatar avatar--red">{chaser.nickname[0]?.toUpperCase()}</span>
            <span className="seat__name">{chaser.nickname}</span>
            {chaser.id === me?.id ? (
              <button type="button" className="btn btn--small btn--ghost" onClick={() => ctx.act(() => api.chooseRole(room.id, null))}>
                Odustani
              </button>
            ) : (
              <span className="seat__tag">SPREMAN ZA LOV</span>
            )}
          </div>
        ) : (
          <button type="button" className="seat seat--free seat--free-red" onClick={() => ctx.act(() => api.chooseRole(room.id, 'chaser'))}>
            Postani lovac
          </button>
        )}
      </section>

      <section className="stack-sm">
        <span className="eyebrow txt-blue">Igrači · {seated.length} od 4</span>
        {[1, 2, 3, 4].map((seat) => {
          const p = seated.find((x) => x.seat === seat);
          if (p) {
            return (
              <div key={seat} className="seat seat--player">
                <span className="seat__n">{seat}</span>
                <span className="avatar avatar--blue">{p.nickname[0]?.toUpperCase()}</span>
                <span className="seat__name">{p.nickname}</span>
                {p.id === me?.id ? (
                  <button type="button" className="btn btn--small btn--ghost" onClick={() => ctx.act(() => api.chooseRole(room.id, null))}>
                    Ustani
                  </button>
                ) : (
                  <span className="seat__tag">{p.user_id === room.host_user ? 'DOMAĆIN' : 'SPREMAN'}</span>
                )}
              </div>
            );
          }
          return (
            <button key={seat} type="button" className="seat seat--free" onClick={() => ctx.act(() => api.chooseRole(room.id, 'player', seat))}>
              <span className="seat__n">{seat}</span>
              Zauzmi ovo mjesto
            </button>
          );
        })}
      </section>

      {choosing.length > 0 && (
        <section className="stack-sm">
          <span className="eyebrow">Još biraju</span>
          <div className="chips">
            {choosing.map((p) => (
              <span key={p.id} className="chip">
                {p.nickname}
                {p.id === me?.id && ' (ti)'}
              </span>
            ))}
          </div>
        </section>
      )}

      <div className="lobby-footer">
        {isHost ? (
          <>
            <button type="button" className="btn btn--blue btn--lg" disabled={!canStart} onClick={() => ctx.act(() => api.startGame(room.id))}>
              Pokreni igru
            </button>
            <span className="muted small center">
              {canStart ? 'Svi spremni? Kreće!' : 'Potreban je 1 lovac i barem 2 igrača'}
            </span>
          </>
        ) : (
          <span className="muted small center">Čekamo da {host?.nickname ?? 'domaćin'} pokrene igru…</span>
        )}
      </div>
    </div>
  );
}
