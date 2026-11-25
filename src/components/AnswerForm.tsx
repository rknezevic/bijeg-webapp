import { useEffect, useRef, useState } from 'react';

interface Props {
  qid: number | undefined;
  onSubmit: (text: string) => Promise<unknown>;
  skipLabel?: string;
  placeholder?: string;
  accent?: 'blue' | 'gold' | 'red';
  disabled?: boolean;
}

/** Text answer + "Dalje" (skip). Clears and refocuses for every new question. */
export function AnswerForm({ qid, onSubmit, skipLabel = 'Dalje', placeholder = 'Upiši odgovor i pritisni Enter', accent = 'blue', disabled }: Props) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setText('');
    setBusy(false);
    input.current?.focus();
  }, [qid]);

  const send = async (value: string) => {
    if (busy || disabled || qid == null) return;
    setBusy(true);
    try {
      await onSubmit(value);
    } catch {
      setBusy(false);
    }
    // New question arrives through realtime and resets the form.
    window.setTimeout(() => setBusy(false), 1500);
  };

  return (
    <form
      className="answer-form"
      onSubmit={(e) => {
        e.preventDefault();
        if (text.trim()) send(text);
      }}
    >
      <label htmlFor="answer" className="sr-only">
        Tvoj odgovor
      </label>
      <input
        id="answer"
        ref={input}
        className={`input input--${accent}`}
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder={placeholder}
        autoComplete="off"
        autoCorrect="off"
        autoCapitalize="off"
        spellCheck={false}
        enterKeyHint="send"
        disabled={disabled}
        maxLength={80}
      />
      <div className="answer-form__buttons">
        <button type="button" className="btn btn--ghost" onClick={() => send('')} disabled={busy || disabled}>
          {skipLabel}
        </button>
        <button type="submit" className={`btn btn--${accent}`} disabled={busy || disabled || !text.trim()}>
          Odgovori
        </button>
      </div>
    </form>
  );
}
