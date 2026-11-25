/** Final-chase progress: the team's steps, with the chaser's progress painted red. */
export function Track({ team, chaser, chaserName }: { team: number; chaser: number; chaserName: string }) {
  const n = Math.max(team, 1);
  return (
    <div className="track">
      <div className="track__labels">
        <span className="txt-red">
          {chaserName} · {chaser}
        </span>
        <span className="txt-blue">Tim · {team}</span>
      </div>
      <div className="track__bar" style={{ gridTemplateColumns: `repeat(${n}, minmax(0, 1fr))` }} aria-label={`Lovac ${chaser} od ${team}`}>
        {Array.from({ length: n }, (_, i) => (
          <span key={i} className={i < chaser - 1 ? 'is-trail' : i === chaser - 1 ? 'is-chaser' : team === 0 ? '' : 'is-team'} />
        ))}
      </div>
    </div>
  );
}
