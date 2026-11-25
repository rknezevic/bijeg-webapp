import { euro } from '../lib/format';

interface Props {
  chaser: number; // 0..6
  player: number; // 0..7 (7 = home)
  amount: number;
  playerName: string;
  chaserName: string;
  big?: boolean;
  /** Optional highlight for offer rows (2, 3, 4) before the duel starts */
  offers?: { row: number; label: string; amount: number; selected?: boolean; onPick?: () => void }[];
}

const ROWS = 8;

/**
 * The board: chaser starts at the top, home ("CILJ") is the bottom row.
 * Every step the chaser has covered stays red; the player's remaining path is blue.
 */
export function Ladder({ chaser, player, amount, playerName, chaserName, big, offers }: Props) {
  const rows = Array.from({ length: ROWS }, (_, i) => i);
  return (
    <div className={`ladder${big ? ' ladder--big' : ''}`} role="img" aria-label={`Ploča: lovac na ${chaser + 1}. stepenici, ${playerName} na ${player + 1}.`}>
      {rows.map((i) => {
        const offer = offers?.find((o) => o.row === i);
        if (offer) {
          return (
            <button
              key={i}
              type="button"
              className={`step step--offer${offer.selected ? ' is-selected' : ''}`}
              onClick={offer.onPick}
              disabled={!offer.onPick}
              aria-pressed={offer.selected}
            >
              <span>{offer.label}</span>
              <span className="step__amount">{euro(offer.amount)}</span>
            </button>
          );
        }
        let cls = 'step';
        let left = '';
        let right = '';
        if (i === ROWS - 1) {
          cls += ' step--home';
          left = 'CILJ';
          if (player >= ROWS - 1) {
            cls += ' is-reached';
            left = `${playerName} · CILJ`;
            right = euro(amount);
          }
        } else if (i === chaser && chaser >= player) {
          cls += ' step--caught';
          left = `${chaserName} · ULOV!`;
        } else if (i === chaser) {
          cls += ' step--chaser';
          left = chaserName;
        } else if (i < chaser) {
          cls += ' step--trail';
        } else if (i === player) {
          cls += ' step--player';
          left = playerName;
          right = euro(amount);
        } else if (i > player) {
          cls += ' step--path';
        }
        return (
          <div key={i} className={cls}>
            <span>{left}</span>
            <span className="step__amount">{right}</span>
          </div>
        );
      })}
    </div>
  );
}
