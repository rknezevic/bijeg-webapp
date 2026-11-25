import type { ReactNode } from 'react';

export function Shell({ children, wide, className = '' }: { children: ReactNode; wide?: boolean; className?: string }) {
  return <div className={`shell${wide ? ' shell--wide' : ''} ${className}`}>{children}</div>;
}

export function Logo({ small }: { small?: boolean }) {
  return (
    <div className={`logo${small ? ' logo--small' : ''}`}>
      <svg width={small ? 28 : 40} height={small ? 28 : 40} viewBox="0 0 40 40" fill="none" aria-hidden="true">
        <rect x="4" y="4" width="32" height="7" rx="2" fill="#E0242F" />
        <rect x="4" y="16" width="32" height="7" rx="2" fill="#1C2547" />
        <rect x="4" y="28" width="32" height="7" rx="2" fill="#3D8BFF" />
      </svg>
      <span>BIJEG</span>
    </div>
  );
}
