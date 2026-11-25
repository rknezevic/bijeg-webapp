import { useEffect, useState } from 'react';

interface Props {
  seq: number | undefined;
  ok: boolean | null | undefined;
  given: string | null | undefined;
  answer: string | null | undefined;
  who?: string | null;
}

/**
 * Small banner that pops up after each answer and fades after ~2.5 s.
 * Wrong or skipped answers show the correct answer, so play never stops.
 */
export function AnswerReveal({ seq, ok, given, answer, who }: Props) {
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    if (!seq) return;
    setVisible(true);
    const t = window.setTimeout(() => setVisible(false), ok ? 1200 : 2600);
    return () => window.clearTimeout(t);
  }, [seq, ok]);
  if (!seq || !visible) return <div className="reveal-slot" />;

  const prefix = who ? `${who}: ` : '';
  if (ok) {
    return (
      <div className="reveal reveal--ok" role="status" key={seq}>
        <Icon ok />
        <div className="reveal__body">
          <span className="reveal__small">{prefix}točno</span>
          <strong>{answer}</strong>
        </div>
      </div>
    );
  }
  return (
    <div className="reveal reveal--bad" role="status" key={seq}>
      <Icon ok={false} />
      <div className="reveal__body">
        <span className="reveal__small">
          {prefix}
          {given ? `„${given}” · ` : 'preskočeno · '}točan odgovor
        </span>
        <strong>{answer}</strong>
      </div>
    </div>
  );
}

export function Icon({ ok }: { ok: boolean }) {
  return ok ? (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M20 6 9 17l-5-5" />
    </svg>
  ) : (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" aria-hidden="true">
      <path d="M18 6 6 18M6 6l12 12" />
    </svg>
  );
}
