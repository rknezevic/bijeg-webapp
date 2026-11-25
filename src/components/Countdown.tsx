import { clock } from '../lib/format';

interface Props {
  endsAt: string | null;
  now: number;
  total: number; // seconds
  size?: number;
  color?: string;
  /** show seconds only (e.g. "7") instead of m:ss */
  seconds?: boolean;
  /** frozen remaining ms (paused clock) */
  pausedMs?: number | null;
}

export function Countdown({ endsAt, now, total, size = 72, color = 'var(--blue)', seconds, pausedMs }: Props) {
  const remaining = pausedMs ?? (endsAt ? new Date(endsAt).getTime() - now : 0);
  const frac = Math.max(0, Math.min(1, remaining / (total * 1000)));
  const stroke = Math.max(5, size / 10);
  const r = size / 2 - stroke / 2 - 1;
  const c = 2 * Math.PI * r;
  const label = seconds ? String(Math.max(0, Math.ceil(remaining / 1000))) : clock(remaining);
  const urgent = remaining <= 5000 && pausedMs == null;
  return (
    <div className={`countdown${urgent ? ' is-urgent' : ''}`} style={{ width: size, height: size }} role="timer" aria-label={`Preostalo ${label}`}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--surface-2)" strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={urgent ? 'var(--red-bright)' : color}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={`${c * frac} ${c}`}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
          style={{ transition: 'stroke-dasharray 0.2s linear' }}
        />
      </svg>
      <span style={{ fontSize: size * (seconds ? 0.38 : 0.27) }}>{label}</span>
    </div>
  );
}
