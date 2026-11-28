# BIJEG — kviz s lovcem

A multiplayer quiz game in the style of a TV chase show, in Croatian. One **chaser** plays against **2–4 players**. Friends join through a private link and type a nickname. Nobody needs an account.

**Tech stack:** React + Vite on the frontend and Supabase (Postgres, Realtime, anonymous sign-in) on the backend. All game rules and timers run on the server (Postgres functions), so the server clock decides who answered first and when time runs out.

## Setup (about 10 minutes)

1. **Create a Supabase project** at <https://supabase.com>. The free plan is enough.
2. **Turn on anonymous sign-ins:** *Authentication → Sign In / Providers → Allow anonymous sign-ins*.
3. **Create the database.** In the *SQL Editor*, run these two files in order:
   1. `supabase/migrations/20261125000000_init.sql`: tables, security and game logic.
   2. `supabase/migrations/20261125010000_h2h_rush.sql`: the 4-second rule on the board.
   3. `supabase/migrations/20261125020000_songs.sql`: song recognition on the board.
   4. `supabase/seed.sql`: 2,664 questions.
   5. `supabase/seed_songs.sql`: 778 songs.
   6. `supabase/migrations/20261125030000_stihovi.sql`: "Nadopuni stih" questions on the board.
   7. `supabase/migrations/20261125040000_high_offer.sql`: higher offer leaves one empty step between the chaser and the player.
   8. `supabase/migrations/20261125050000_igrice.sql`: video game questions (run before `seed.sql`).
   9. `supabase/migrations/20261126000000_ready.sql`: "Spreman sam" buttons between rounds; song options from the same artist.
   10. `supabase/migrations/20261126010000_filmovi_priroda.sql`: the categories *Filmovi i serije* and *Priroda i društvo* (run before `seed.sql`). On an existing database, `supabase/seed_filmovi_priroda.sql` does the migration and adds only the new questions.
   11. `supabase/migrations/20261128000000_review.sql`: the host reviews the answers of each 1-minute round before the game goes on.

   If you use the Supabase CLI instead, run `supabase db push` and then run `seed.sql`.
4. **Check Realtime.** Under *Database → Publications → supabase_realtime*, the tables `rooms` and `room_players` must be on. The migration turns them on, but it's worth checking.
5. **Add your keys.** Copy `.env.example` to `.env`, then paste in the *Project URL* and the *anon public key* from *Project Settings → API*.
6. **Run the app:**
   ```bash
   npm install
   npm run dev
   ```
   Open <http://localhost:5173>. To play with friends on the same Wi-Fi, use the "Network" address that Vite prints.

### Hosting (so friends can play from anywhere)

Deploy to **Vercel** or **Netlify**:

1. Import the repo.
2. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` as environment variables.
3. Build command: `npm run build`. Output folder: `dist`.

SPA routing is already set up (`vercel.json`, `public/_redirects`).

## How a game runs

| Phase | What happens |
|---|---|
| Lobby | Everyone joins through `/s/CODE`. Each person picks the chaser seat (only one) or a player seat (1–4). The host starts the game. |
| Intro | "Na redu je …" animation (5 s). |
| Cash builder | 60 s of open questions, 500 € per correct answer. *Dalje* skips. After a wrong answer or a skip, the correct answer shows briefly and the next question appears right away. |
| Review | All answers of the minute are listed. The host (room creator) can click any typed answer to accept it (or reject one the game accepted); the amount is recalculated. The game continues once the host clicks *Odgovori su OK, idemo dalje* and the player and the chaser are ready. *Kreni bez čekanja* still skips everything. |
| Offer | The chaser sets a higher offer (one empty step between the chaser and the player) and a lower offer (start 4 steps ahead). The player picks: higher offer, own amount (3 steps ahead), or lower offer. If time runs out, the player keeps their own amount. |
| Head-to-head | A/B/C questions. The player and the chaser each answer on their own screen. Answers are revealed only once both have locked in. As soon as one side locks in, the other has only 4 seconds left (with a ticking clock). Every step the chaser has covered turns red. A player who reaches the bottom row (CILJ) is home and adds their money to the team pot. A player the chaser catches is out and watches the rest of the game. |
| Final (team) | 2 minutes. Only the first answer typed by any finalist counts. Each player who made it home gives the team 1 step head start. If nobody made it home, every player plays the final for their cash-builder money. |
| Final (chaser) | 2 minutes. When the chaser answers wrong or passes, the clock stops and the captain (the first finalist by seat) gets 10 seconds to answer. A correct answer pushes the chaser back one step. If the chaser is still at 0, the team gets an extra step instead. |
| End | The team splits the pot, or the chaser wins. The host can start a new game with the same players. |

People who join after a game has started come in as spectators.

## Questions

Questions that asked for an exact year now ask for the century (before 1900) or the decade, except a few key dates (Croatian independence, Oluja, EU and NATO entry, the world wars, the Moon landing, the fall of the Berlin Wall, Columbus). `supabase/update_godine.sql` updates an existing database in place.

The questions are plain text files in `questions/`, one question per line:

```
pitanje | točan odgovor | drugi prihvaćeni odgovori (;) | dva netočna odgovora (;)
Tko je zabio pobjednički gol protiv Engleske u polufinalu 2018.? | Mario Mandžukić | Mandžukić; Mandžo | Ivan Perišić; Andrej Kramarić
```

| File | Count |
|---|---|
| `hrvatska.txt` | 240 |
| `opce.txt` (general knowledge + history) | 508 |
| `nogomet.txt` | 403 |
| `sport.txt` | 201 |
| `geografija.txt` | 348 |
| `matematika.txt` (generated by `scripts/gen-math.mjs`, answers computed) | 200 |
| `rijeci.txt` (loanwords: germanisms, turcisms, anglicisms — category Hrvatska) | 98 |
| `igrice_brzi.txt` (video games, typed rounds only) | 103 |
| `igrice_ploca.txt` (video games, board only) | 101 |
| `filmovi_brzi.txt` (films and TV series, easier, typed rounds only) | 142 |
| `filmovi_ploca.txt` (films and TV series, harder, board only) | 126 |
| `priroda_brzi.txt` (nature and society, easier, typed rounds only) | 94 |
| `priroda_ploca.txt` (nature and society, harder, board only) | 100 |

Questions in the `_brzi` files appear only in the cash builder and the final, and questions in the `_ploca` files only on the board. All other questions work in both formats:

- **Open answer** for the cash builder and the final.
- **A/B/C** for the head-to-head, using the correct answer plus the two wrong options.

After you edit a file, rebuild the seed and run it again in the SQL Editor:

```bash
npm run questions   # validates every file and regenerates supabase/seed.sql
```

Running the seed again updates questions in place and keeps their usage counters.

### Choosing questions

Each question has a `times_used` counter. The game always picks from the least-used questions (in random order) and never repeats a question inside one room.

### Answer checking (`check_answer` in the migration)

The game accepts an answer when it matches the correct answer or one of the extra accepted answers, ignoring:

- **Letter case and accents:** č/ć/š/ž/đ, so "dj" is the same as "đ". "Mandzukic" counts as "Mandžukić", and "Djokovic" counts as "Đoković".
- **Punctuation**
- **Small typos:** 1 wrong letter, or 2 in long answers, as long as the first letter is right.

Some answers must still be exact:

- **Numbers** must match exactly. "45" and "45 minuta" both count; "40" doesn't.
- **Very short words** must be typed exactly, so "Iran" ≠ "Irak" and "vitamin C" ≠ "vitamin D".
- **Nicknames and short forms** are accepted only when they're listed in the file as accepted answers ("Mandžo", "Plitvice").

## Song recognition

About 30 % of board (head-to-head) questions are "Koja je ovo pjesma?". The player's and the chaser's phones automatically play a 15-second slice from a random point in the song's 30-second Deezer preview. Spectators press play themselves. The three options are the correct song plus two other songs from the same region (Balkan or international).

Songs live in `questions/pjesme.txt` (`regija | izvođač | naslov | Deezer ID`). The ID is the number in `deezer.com/track/<ID>`. Run `npm run questions` to regenerate `supabase/seed_songs.sql`, then run that file in the SQL Editor again.

## "Nadopuni stih" (fill in the lyric)

Write your own lyric questions in `questions/stihovi.txt` (the format is explained at the top of the file). They appear only on the board, as about 20 % of questions once there are some. Run `npm run questions`, then run `supabase/seed.sql` again in the SQL Editor.

## Sounds

All sounds are generated in the browser with the Web Audio API (`src/lib/sound.ts`), so there are no audio files. They play after the first click or tap, which is a browser rule. The speaker button in the top bar mutes them.

| Moment | Sound |
|---|---|
| Lock-in on the board | "dunk-ding" |
| The 4 seconds after one side answers | Ticking clock with a heartbeat, faster in the last second, then a buzzer |
| Correct answer in the cash builder | Quiet coin "cha-ching" |
| Wrong answer in the cash builder | Low "bonk" |
| Player's answer revealed on the board | Short jingle / low "bonk" (the chaser's answer is silent) |
| Answers in the final chase | No sound |
| Player reaches home, or the team wins | Brass fanfare |
| Player caught, or the chaser wins | Boom + sad trombone |
| New player and the final | Dramatic sting |

## Changing timers or rules

All durations are in the migration. Search for `interval '60 seconds'` (cash builder), `'20 seconds'` (head-to-head), `'120 seconds'` (final) and `'10 seconds'` (pushback). If you change them, also update `PHASE_SECONDS` in `src/lib/format.ts` so the countdown rings match.

## Tests

`supabase/test/run.sh` runs the migration on a local Postgres 16 with small stand-ins for Supabase internals. It then:

1. Plays a full simulated game: roles, the cash builder, offers, a player getting home, a player getting caught, the team final, a pushback and the chaser's win.
2. Checks that no wrong A/B/C option would be accepted as a typed answer.
