import { useEffect, useState } from 'react';
import { Logo, Shell } from '../components/ui';
import { Ladder } from '../components/Ladder';
import { Countdown } from '../components/Countdown';
import { Track } from '../components/Track';
import { SongClip } from '../components/SongClip';
import { AnswerForm } from '../components/AnswerForm';
import { AnswerReveal, Icon } from '../components/AnswerReveal';
import { useRoom } from '../lib/useRoom';
import { useGameSounds } from '../lib/useGameSounds';
import { isMuted, setMuted, sfx } from '../lib/sound';
import { api } from '../lib/api';
import { CATEGORY, PHASE_LABEL, PHASE_SECONDS, euro, koraka } from '../lib/format';
import type { FeedEntry, Player, QuestionView, Room } from '../types';
import { Lobby } from './Lobby';

export interface Ctx {
  room: Room;
  players: Player[];
  me: Player | undefined;
  now: number;
  isHost: boolean;
  chaser: Player | undefined;
  current: Player | undefined;
  name: (id: string | undefined | null) => string;
  act: (fn: () => Promise<unknown>) => Promise<void>;
}

export function Game({ roomId, uid }: { roomId: string; uid: string }) {
  const { room, players, error, now, refresh, serverOffset } = useRoom(roomId);
  const [toast, setToast] = useState<string | null>(null);
  const [muted, setMutedState] = useState(isMuted());
  useGameSounds(room, serverOffset);

  useEffect(() => {
    if (!toast) return;
    const t = window.setTimeout(() => setToast(null), 3500);
    return () => window.clearTimeout(t);
  }, [toast]);

  if (error) {
    return (
      <Shell>
        <p className="error center">{error}</p>
      </Shell>
    );
  }
  if (!room) {
    return (
      <Shell>
        <p className="muted center">Učitavanje…</p>
      </Shell>
    );
  }

  const me = players.find((p) => p.user_id === uid);
  const ctx: Ctx = {
    room,
    players,
    me,
    now,
    isHost: room.host_user === uid,
    chaser: players.find((p) => p.role === 'chaser'),
    current: players.find((p) => p.id === room.state.current),
    name: (id) => players.find((p) => p.id === id)?.nickname ?? '—',
    act: async (fn) => {
      try {
        await fn();
        refresh();
      } catch (e) {
        setToast((e as Error).message);
      }
    },
  };

  const chaserView =
    me?.role === 'chaser' && ['offer_set', 'h2h', 'h2h_reveal', 'final_chaser', 'final_chaser_intro'].includes(room.phase);

  return (
    <Shell wide={room.phase !== 'lobby'} className={`phase-${room.phase}${chaserView ? ' theme-chaser' : ''}`}>
      <header className="topbar">
        <Logo small />
        <span className="topbar__phase">{PHASE_LABEL[room.phase]}</span>
        <span className="topbar__code">{room.code}</span>
        <button
          type="button"
          className="sound-toggle"
          aria-label={muted ? 'Uključi zvuk' : 'Isključi zvuk'}
          aria-pressed={!muted}
          onClick={() => {
            setMuted(!muted);
            setMutedState(!muted);
            if (muted) sfx.correct();
          }}
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M11 5 6 9H2v6h4l5 4V5z" />
            {muted ? <path d="m23 9-6 6M17 9l6 6" /> : <path d="M15.5 8.5a5 5 0 0 1 0 7M19 5a10 10 0 0 1 0 14" />}
          </svg>
        </button>
      </header>
      <main className="stage" key={room.phase === 'h2h_reveal' ? 'h2h' : room.phase}>
        <PhaseView ctx={ctx} />
      </main>
      {room.phase !== 'lobby' && <Roster ctx={ctx} />}
      {toast && (
        <div className="toast" role="alert">
          {toast}
        </div>
      )}
    </Shell>
  );
}

function PhaseView({ ctx }: { ctx: Ctx }) {
  switch (ctx.room.phase) {
    case 'lobby':
      return <Lobby ctx={ctx} />;
    case 'intro':
      return <Intro ctx={ctx} />;
    case 'cash':
      return <Cash ctx={ctx} />;
    case 'offer_set':
      return <OfferSet ctx={ctx} />;
    case 'offer_pick':
      return <OfferPick ctx={ctx} />;
    case 'h2h':
    case 'h2h_reveal':
      return <HeadToHead ctx={ctx} />;
    case 'final_intro':
      return <FinalIntro ctx={ctx} />;
    case 'final_team':
      return <FinalTeam ctx={ctx} />;
    case 'final_chaser_intro':
      return <FinalChaserIntro ctx={ctx} />;
    case 'final_chaser':
    case 'final_pushback':
      return <FinalChaser ctx={ctx} />;
    case 'finished':
      return <Finished ctx={ctx} />;
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------

function Timer({ ctx, size, seconds, total: override }: { ctx: Ctx; size?: number; seconds?: boolean; total?: number }) {
  const total = override ?? PHASE_SECONDS[ctx.room.phase] ?? 10;
  return <Countdown endsAt={ctx.room.phase_ends_at} now={ctx.now} total={total} size={size} seconds={seconds} />;
}

function QuestionCard({ q, big }: { q: QuestionView | null | undefined; big?: boolean }) {
  if (!q) return null;
  return (
    <div className={`qcard${big ? ' qcard--big' : ''}`} key={q.id}>
      <span className="eyebrow txt-blue">{CATEGORY[q.cat] ?? q.cat}</span>
      <p className="qcard__text">{q.text}</p>
    </div>
  );
}

function Intro({ ctx }: { ctx: Ctx }) {
  const first = (ctx.room.state.idx ?? 0) === 0;
  const mine = ctx.me?.id === ctx.current?.id;
  return (
    <div className="intro">
      <span className="eyebrow">{first ? 'Igra počinje!' : `Igrač ${(ctx.room.state.idx ?? 0) + 1} od ${ctx.room.state.order?.length ?? 0}`}</span>
      <p className="intro__label">Na redu je</p>
      <h1 className="intro__name">{ctx.current?.nickname}</h1>
      <p className="muted">Brzi krug · 60 sekundi · 500 € za svaki točan odgovor</p>
      {mine && <p className="intro__you">Spremi se — ti si na redu!</p>}
      <Timer ctx={ctx} size={88} seconds />
    </div>
  );
}

function Cash({ ctx }: { ctx: Ctx }) {
  const c = ctx.room.state.cash;
  const mine = ctx.me?.id === ctx.current?.id;
  if (!c) return null;
  return (
    <div className="col">
      <div className="row-between">
        <div>
          <span className="eyebrow">Brzi krug</span>
          <h2 className="h2">{ctx.current?.nickname}</h2>
        </div>
        <Timer ctx={ctx} />
      </div>
      <div className="bank">
        <span className="muted">Dosad osvojeno</span>
        <span className="bank__value">{euro(c.bank)}</span>
      </div>
      <div className="score-line muted small">
        <span className="txt-green">✓ {c.correct}</span>
        <span className="txt-red-soft">✗ {c.wrong}</span>
        <span>preskočeno {c.skipped}</span>
      </div>
      <AnswerReveal seq={c.last?.seq} ok={c.last?.ok} given={c.last?.given} answer={c.last?.answer} />
      <QuestionCard q={c.q} big />
      {mine ? (
        <AnswerForm qid={c.q?.id} onSubmit={(t) => ctx.act(() => api.cashAnswer(ctx.room.id, c.q!.id, t))} />
      ) : (
        <p className="watching">{ctx.current?.nickname} odgovara… Ti gledaš uživo.</p>
      )}
    </div>
  );
}

function OfferSet({ ctx }: { ctx: Ctx }) {
  const o = ctx.room.state.offer!;
  const iAmChaser = ctx.me?.role === 'chaser';
  const [high, setHigh] = useState(String(o.high));
  const [low, setLow] = useState(String(o.low));
  return (
    <div className="col">
      <div className="row-between">
        <div>
          <span className="eyebrow">Ponuda lovca</span>
          <h2 className="h2">
            {ctx.current?.nickname}: {euro(o.bank)} u brzom krugu
          </h2>
        </div>
        <Timer ctx={ctx} />
      </div>
      {iAmChaser ? (
        <form
          className="card stack"
          onSubmit={(e) => {
            e.preventDefault();
            ctx.act(() => api.setOffers(ctx.room.id, parseInt(high, 10) || 0, parseInt(low, 10) || 0));
          }}
        >
          <p className="muted">Ponudi više novca za start bliže tebi, ili manje za start bliže cilju.</p>
          <label className="label" htmlFor="hi">
            Viša ponuda (1 prazna stepenica između tebe i igrača)
          </label>
          <input id="hi" className="input input--red" type="number" inputMode="numeric" step={500} value={high} onChange={(e) => setHigh(e.target.value)} />
          <label className="label" htmlFor="lo">
            Niža ponuda (4 koraka ispred tebe)
          </label>
          <input id="lo" className="input input--red" type="number" inputMode="numeric" step={100} value={low} onChange={(e) => setLow(e.target.value)} />
          <button className="btn btn--red btn--lg">Pošalji ponude</button>
          <p className="muted small">Ako ne pošalješ na vrijeme, vrijede predložene ponude.</p>
        </form>
      ) : (
        <p className="watching">{ctx.chaser?.nickname} priprema ponude…</p>
      )}
    </div>
  );
}

function OfferPick({ ctx }: { ctx: Ctx }) {
  const o = ctx.room.state.offer!;
  const mine = ctx.me?.id === ctx.current?.id;
  const pick = (c: 'high' | 'mid' | 'low') => (mine ? () => ctx.act(() => api.pickOffer(ctx.room.id, c)) : undefined);
  return (
    <div className="col">
      <div className="row-between">
        <div>
          <span className="eyebrow">Prije susreta</span>
          <h2 className="h2">
            <span className="txt-red">{ctx.chaser?.nickname}</span> nudi
          </h2>
        </div>
        <Timer ctx={ctx} />
      </div>
      <p className="muted">
        {mine ? 'Odaberi s koje stepenice krećeš.' : `${ctx.current?.nickname} bira s koje stepenice kreće.`} Bliže lovcu znači više novca, ali i veći rizik.
      </p>
      <Ladder
        chaser={0}
        player={3}
        amount={o.bank}
        playerName={ctx.current?.nickname ?? ''}
        chaserName={ctx.chaser?.nickname ?? 'Lovac'}
        offers={[
          { row: 2, label: 'Viša ponuda · 5 do cilja', amount: o.high, onPick: pick('high') },
          { row: 3, label: 'Tvoj iznos · 4 do cilja', amount: o.bank, onPick: pick('mid'), selected: true },
          { row: 4, label: 'Niža ponuda · 3 do cilja', amount: o.low, onPick: pick('low') },
        ]}
      />
      <p className="muted small center">Ako ne odabereš na vrijeme, ostaje tvoj iznos.</p>
    </div>
  );
}

function HeadToHead({ ctx }: { ctx: Ctx }) {
  const h = ctx.room.state.h2h!;
  const q = h.q;
  const isPlayer = ctx.me?.id === ctx.current?.id;
  const isChaser = ctx.me?.role === 'chaser';
  const [pick, setPick] = useState<{ qid: number; idx: number } | null>(null);
  const reveal = ctx.room.phase === 'h2h_reveal' ? h.reveal : null;
  const myPick = pick && q && pick.qid === q.id ? pick.idx : null;
  const canAnswer = !reveal && (isPlayer || isChaser) && myPick === null && !(isPlayer ? h.lockP : isChaser ? h.lockC : true);
  const pName = ctx.current?.nickname ?? '';
  const cName = ctx.chaser?.nickname ?? 'Lovac';
  const gap = h.player - h.chaser;

  const answer = (idx: number) => {
    if (!q || !canAnswer) return;
    setPick({ qid: q.id, idx });
    ctx.act(() => api.h2hAnswer(ctx.room.id, q.id, idx));
  };

  return (
    <div className="duel">
      <div className="duel__board">
        <div className="row-between">
          <div>
            <span className="eyebrow">{isChaser ? 'Ti si lovac' : isPlayer ? 'Dvoboj · ti protiv lovca' : 'Dvoboj'}</span>
            <h2 className="h2">
              {pName} <span className="muted">vs</span> <span className="txt-red">{cName}</span>
            </h2>
          </div>
          <span className="pill">{gap > 0 ? `${koraka(gap)} razmaka` : 'Ulov!'}</span>
        </div>
        <Ladder chaser={h.chaser} player={h.player} amount={h.amount} playerName={isPlayer ? 'Ti' : pName} chaserName={isChaser ? 'Ti' : cName} big />
      </div>

      <div className="duel__question">
        <div className="row-between">
          <span className="eyebrow">Pitanje {h.n}</span>
          {!reveal && <Timer ctx={ctx} size={56} seconds total={h.rush ? 4 : 20} />}
        </div>
        <QuestionCard q={q} />
        {q?.audio && <SongClip key={q.id} deezer={q.audio.deezer} start={q.audio.start} autoPlay={isPlayer || isChaser} />}
        <div className="options">
          {q?.options?.map((opt, i) => {
            let cls = 'option';
            const tags: { text: string; kind: 'p' | 'c' }[] = [];
            if (reveal) {
              if (i === reveal.correct) cls += ' is-correct';
              else if (i === reveal.p || i === reveal.c) cls += ' is-wrong';
              else cls += ' is-dim';
              if (reveal.p === i) tags.push({ text: isPlayer ? 'TI' : pName, kind: 'p' });
              if (reveal.c === i) tags.push({ text: isChaser ? 'TI' : cName, kind: 'c' });
            } else if (myPick === i) {
              cls += ' is-picked';
            }
            return (
              <button key={i} type="button" className={cls} onClick={() => answer(i)} disabled={!canAnswer && myPick !== i} aria-pressed={myPick === i}>
                <span className="option__letter">{'ABC'[i]}</span>
                <span className="option__text">{opt}</span>
                {tags.map((t) => (
                  <span key={t.kind} className={`tag tag--${t.kind}`}>
                    {t.text}
                  </span>
                ))}
              </button>
            );
          })}
        </div>

        {!reveal && h.rush && myPick === null && canAnswer && (
          <div className="rush pop" role="alert">
            {isPlayer ? cName : pName}: odgovor zaključan! Imaš još 4 sekunde!
          </div>
        )}
        {reveal ? (
          <RevealBanner ctx={ctx} />
        ) : (
          <div className="locks">
            <span className={h.lockP ? 'lock is-locked' : 'lock'}>
              {h.lockP ? '✓' : '…'} {pName} {h.lockP ? 'zaključano' : 'razmišlja'}
            </span>
            <span className={h.lockC ? 'lock lock--c is-locked' : 'lock lock--c'}>
              {h.lockC ? '✓' : '…'} {cName} {h.lockC ? 'zaključano' : 'razmišlja'}
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

function RevealBanner({ ctx }: { ctx: Ctx }) {
  const h = ctx.room.state.h2h!;
  const r = h.reveal!;
  const p = ctx.current?.nickname ?? '';
  const c = ctx.chaser?.nickname ?? 'Lovac';
  if (r.outcome === 'home') {
    return (
      <div className="banner banner--home pop">
        <strong>{p} je na cilju!</strong>
        <span>{euro(h.amount)} ide u zajednički fond za finale.</span>
      </div>
    );
  }
  if (r.outcome === 'caught') {
    return (
      <div className="banner banner--caught pop">
        <strong>{c} hvata!</strong>
        <span>{p} ispada i gleda do kraja igre.</span>
      </div>
    );
  }
  return (
    <div className="banner pop">
      <span>
        {r.pOk ? `✓ ${p} točno — korak bliže cilju.` : `✗ ${p} netočno — ostaje na mjestu.`}
      </span>
      <span>{r.cOk ? `✓ ${c} točno — korak bliže.` : `✗ ${c} netočno — ostaje na mjestu.`}</span>
    </div>
  );
}

function FinalIntro({ ctx }: { ctx: Ctx }) {
  const f = ctx.room.state.final!;
  return (
    <div className="intro">
      <span className="eyebrow">Finale</span>
      <h1 className="intro__name">Tim za finale</h1>
      <div className="chips">
        {f.finalists.map((id) => (
          <span key={id} className="chip chip--blue">
            {ctx.name(id)}
            {id === f.captain && ' ★ kapetan'}
          </span>
        ))}
      </div>
      <div className="bank">
        <span className="muted">Igraju za</span>
        <span className="bank__value">{euro(f.pot)}</span>
      </div>
      <p className="muted">
        {f.head > 0 ? `Prednost: ${koraka(f.head)} (jedan za svakog igrača na cilju).` : 'Nitko nije stigao do cilja — finale igraju svi.'} 2 minute, svaki točan odgovor je korak. Tko prvi upiše, taj se računa.
      </p>
      <Timer ctx={ctx} size={88} seconds />
    </div>
  );
}

function Feed({ feed, ctx }: { feed: FeedEntry[]; ctx: Ctx }) {
  if (!feed.length) return null;
  return (
    <div className="feed">
      <span className="eyebrow">Upravo</span>
      {feed.map((e) => (
        <div key={e.seq} className={`feed__row ${e.ok ? 'is-ok' : 'is-bad'}`}>
          <Icon ok={!!e.ok} />
          <span className="feed__text">
            {e.by === 'captain' ? '★ ' : ''}
            {e.who ?? (e.by === 'captain' ? ctx.name(ctx.room.state.final?.captain) : '')}
            {e.given ? ` — „${e.given}”` : e.by === 'captain' && !e.who ? ' — vrijeme isteklo' : ' — preskočeno'}
            {!e.ok && e.answer ? ` · točno: ${e.answer}` : ''}
          </span>
          {e.ok && <strong>{e.by === 'captain' ? '↩' : '+1'}</strong>}
        </div>
      ))}
    </div>
  );
}

function FinalTeam({ ctx }: { ctx: Ctx }) {
  const f = ctx.room.state.final!;
  const inTeam = !!ctx.me && f.finalists.includes(ctx.me.id);
  return (
    <div className="col">
      <div className="final-head">
        <span className="eyebrow">Finale · red je na timu</span>
        <Timer ctx={ctx} size={96} />
      </div>
      <div className="grid-2">
        <div className="stat stat--blue">
          <span className="small">Koraka</span>
          <strong>{f.team}</strong>
          <span className="small muted">uklj. {f.head} prednosti</span>
        </div>
        <div className="stat">
          <span className="small muted">Nagrada</span>
          <strong className="txt-gold">{euro(f.pot)}</strong>
          <span className="small muted">{f.finalists.map((id) => ctx.name(id)).join(' · ')}</span>
        </div>
      </div>
      <AnswerReveal seq={f.last?.seq} ok={f.last?.ok} given={f.last?.given} answer={f.last?.answer} who={f.last?.who} />
      <QuestionCard q={f.q} big />
      {inTeam ? (
        <AnswerForm qid={f.q?.id} placeholder="Upiši brzo — prvi odgovor se računa" onSubmit={(t) => ctx.act(() => api.finalAnswer(ctx.room.id, f.q!.id, t))} />
      ) : (
        <p className="watching">Tim odgovara… Ti gledaš uživo.</p>
      )}
      <Feed feed={f.feed} ctx={ctx} />
    </div>
  );
}

function FinalChaserIntro({ ctx }: { ctx: Ctx }) {
  const f = ctx.room.state.final!;
  return (
    <div className="intro">
      <span className="eyebrow">Finale · red je na lovcu</span>
      <h1 className="intro__name txt-red">{ctx.chaser?.nickname}</h1>
      <p className="intro__label">
        mora stići {koraka(f.team)} u 2 minute
      </p>
      <p className="muted">Kad lovac pogriješi, sat staje i kapetan {ctx.name(f.captain)} ima 10 sekundi da ga vrati korak unatrag.</p>
      <Timer ctx={ctx} size={88} seconds />
    </div>
  );
}

function FinalChaser({ ctx }: { ctx: Ctx }) {
  const f = ctx.room.state.final!;
  const pushback = ctx.room.phase === 'final_pushback';
  const isChaser = ctx.me?.role === 'chaser';
  const isCaptain = ctx.me?.id === f.captain;
  const cName = ctx.chaser?.nickname ?? 'Lovac';

  return (
    <div className="col">
      <div className="final-head">
        <span className="eyebrow">{pushback ? 'Sat je zaustavljen' : 'Finale · red je na lovcu'}</span>
        <Countdown
          endsAt={pushback ? null : ctx.room.phase_ends_at}
          pausedMs={pushback ? f.remaining : null}
          now={ctx.now}
          total={120}
          size={pushback ? 64 : 96}
          color="var(--red-bright)"
        />
      </div>
      <Track team={f.team} chaser={f.chaser} chaserName={cName} />

      {pushback ? (
        <div className="pushback pop" role="alert">
          <span className="txt-red-soft">
            {cName}: {f.pb?.given ? `„${f.pb.given}” — netočno!` : 'preskočeno!'}
          </span>
          <strong className="pushback__title">{isCaptain ? 'Kapetane, tvoj red!' : `${ctx.name(f.captain)} odgovara`}</strong>
          <Timer ctx={ctx} size={96} seconds />
          <span className="txt-blue small">Točan odgovor vraća lovca korak unatrag</span>
        </div>
      ) : (
        <AnswerReveal seq={f.last?.seq} ok={f.last?.ok} given={f.last?.given} answer={f.last?.answer} who={f.last?.who} />
      )}

      <QuestionCard q={f.q} big={!pushback} />

      {pushback && isCaptain && (
        <AnswerForm qid={f.q?.id} accent="gold" skipLabel="Ne znam" onSubmit={(t) => ctx.act(() => api.finalAnswer(ctx.room.id, f.q!.id, t))} />
      )}
      {!pushback && isChaser && (
        <AnswerForm qid={f.q?.id} accent="red" onSubmit={(t) => ctx.act(() => api.finalAnswer(ctx.room.id, f.q!.id, t))} />
      )}
      {!pushback && !isChaser && <p className="watching">{cName} odgovara… Ako pogriješi, kapetan {ctx.name(f.captain)} dobiva 10 sekundi.</p>}
      {pushback && !isCaptain && <p className="watching">Samo kapetan može odgovoriti.</p>}
      <Feed feed={f.feed} ctx={ctx} />
    </div>
  );
}

function Finished({ ctx }: { ctx: Ctx }) {
  const r = ctx.room.state.result;
  const f = ctx.room.state.final;
  if (!r || !f) return null;
  const team = r.winner === 'team';
  return (
    <div className="intro">
      <span className="eyebrow">Kraj igre</span>
      <h1 className={`intro__name ${team ? 'txt-blue' : 'txt-red'}`}>{team ? 'Tim pobjeđuje!' : `${ctx.chaser?.nickname} pobjeđuje!`}</h1>
      {team ? (
        <>
          <div className="bank">
            <span className="muted">Svaki igrač osvaja</span>
            <span className="bank__value">{euro(r.each)}</span>
          </div>
          <div className="chips">
            {f.finalists.map((id) => (
              <span key={id} className="chip chip--blue">
                {ctx.name(id)}
              </span>
            ))}
          </div>
        </>
      ) : (
        <p className="intro__label">Lovac je sustigao tim · {euro(r.pot)} ostaje u banci</p>
      )}
      <p className="muted">
        Tim: {koraka(f.team)} · Lovac: {koraka(f.chaser)}
      </p>
      {ctx.isHost ? (
        <button className="btn btn--blue btn--lg" onClick={() => ctx.act(() => api.resetRoom(ctx.room.id))}>
          Nova igra s istom ekipom
        </button>
      ) : (
        <p className="muted small">Domaćin može pokrenuti novu igru.</p>
      )}
    </div>
  );
}

function Roster({ ctx }: { ctx: Ctx }) {
  const label: Record<Player['status'], string> = {
    lobby: '',
    waiting: 'čeka',
    playing: 'igra',
    home: 'na cilju',
    caught: 'ispao · gleda',
    spectator: 'gleda',
    chaser: 'lovac',
  };
  const list = [...ctx.players].sort((a, b) => (a.role === 'chaser' ? -1 : b.role === 'chaser' ? 1 : (a.seat ?? 9) - (b.seat ?? 9)));
  return (
    <footer className="roster">
      {list.map((p) => (
        <span key={p.id} className={`roster__p is-${p.status}${p.id === ctx.me?.id ? ' is-me' : ''}`}>
          <span className="roster__dot" />
          {p.nickname}
          <span className="roster__st">
            {label[p.status]}
            {p.status === 'home' ? ` · ${euro(p.amount)}` : ''}
          </span>
        </span>
      ))}
    </footer>
  );
}
