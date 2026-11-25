-- Plays a whole game against the RPCs (run after mock_supabase.sql + the migration).
insert into public.questions (category, question, answer, aliases, wrong)
select 'opce', 'Testno pitanje ' || g, 'odgovor' || g, '{}', array['krivo' || g, 'netocno' || g]
from generate_series(1, 120) g;

create or replace function pg_temp.as_user(u text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', u, true); $$;
create or replace function pg_temp.expire(r uuid) returns void language sql as
$$ update public.rooms set phase_ends_at = now() - interval '1 second' where id = r; $$;

do $$
declare
  H text := '00000000-0000-0000-0000-00000000000a';
  M text := '00000000-0000-0000-0000-00000000000b';
  CH text := '00000000-0000-0000-0000-00000000000c';
  L text := '00000000-0000-0000-0000-00000000000d';
  res jsonb; rid uuid; code text; r public.rooms; s public.room_secrets; qid bigint;
  pid_h uuid;
begin
  perform pg_temp.as_user(H);
  res := public.create_room('Robi'); rid := res->>'room_id'; code := res->>'code';
  perform pg_temp.as_user(M); perform public.join_room(lower(code), 'Marko');
  perform pg_temp.as_user(CH); perform public.join_room(code, 'Ivana');
  perform pg_temp.as_user(L); perform public.join_room(code, 'Luka');
  begin perform pg_temp.as_user(L); perform public.join_room(code, 'Luka'); end; -- rejoin is fine

  perform pg_temp.as_user(H); perform public.choose_role(rid, 'player', 1);
  perform pg_temp.as_user(M); perform public.choose_role(rid, 'player', 2);
  perform pg_temp.as_user(L); perform public.choose_role(rid, 'player', 3);
  perform pg_temp.as_user(CH); perform public.choose_role(rid, 'chaser');
  begin
    perform pg_temp.as_user(M); perform public.choose_role(rid, 'chaser');
    raise exception 'expected error';
  exception when others then
    if sqlerrm = 'expected error' then raise; end if;
    raise notice 'ok second chaser refused: %', sqlerrm;
  end;
  begin
    perform pg_temp.as_user(M); perform public.start_game(rid);
    raise exception 'expected error';
  exception when others then
    if sqlerrm = 'expected error' then raise; end if;
    raise notice 'ok non-host start refused: %', sqlerrm;
  end;

  perform pg_temp.as_user(H); perform public.start_game(rid);
  select * into r from public.rooms where id = rid;
  assert r.phase = 'intro', 'intro expected';
  select id into pid_h from public.room_players where room_id = rid and user_id = H::uuid;
  assert (r.state->>'current')::uuid = pid_h;

  -- ===== Player 1: Robi =====
  perform pg_temp.expire(rid); perform public.tick(rid);
  select * into r from public.rooms where id = rid; assert r.phase = 'cash', 'cash expected ' || r.phase;
  for i in 1..3 loop
    select * into r from public.rooms where id = rid; select * into s from public.room_secrets where room_id = rid;
    res := public.cash_answer(rid, (r.state->'cash'->'q'->>'id')::bigint, upper(s.ans) || '.');
    assert (res->>'ok')::boolean, 'correct answer not accepted';
  end loop;
  select * into r from public.rooms where id = rid;
  res := public.cash_answer(rid, (r.state->'cash'->'q'->>'id')::bigint, 'nešto krivo');
  select * into r from public.rooms where id = rid;
  qid := (r.state->'cash'->'q'->>'id')::bigint;
  res := public.cash_answer(rid, qid, '');
  res := public.cash_answer(rid, qid, 'stale');
  assert res ? 'stale', 'stale qid not detected';
  select * into r from public.rooms where id = rid;
  raise notice 'cash: %', r.state->'cash';
  assert (r.state->'cash'->>'bank')::int = 1500;
  assert (r.state->'cash'->'last'->>'ok') is null, 'skip should have ok=null';

  perform pg_temp.as_user(M); res := public.cash_answer(rid, qid, 'x'); assert res ? 'ignored';

  perform pg_temp.expire(rid); perform public.tick(rid);
  select * into r from public.rooms where id = rid; assert r.phase = 'offer_set';
  raise notice 'default offers: %', r.state->'offer';
  perform pg_temp.as_user(CH); perform public.set_offers(rid, 8000, 200);
  select * into r from public.rooms where id = rid; assert r.phase = 'offer_pick';
  perform pg_temp.as_user(H); perform public.pick_offer(rid, 'high');
  select * into r from public.rooms where id = rid; assert r.phase = 'h2h';
  assert (r.state->'h2h'->>'player')::int = 2 and (r.state->'h2h'->>'amount')::int = 8000;
  assert not (r.state->'h2h'->'q' ? 'correct');

  for i in 1..5 loop
    select * into r from public.rooms where id = rid; select * into s from public.room_secrets where room_id = rid;
    qid := (r.state->'h2h'->'q'->>'id')::bigint;
    perform pg_temp.as_user(H); perform public.h2h_answer(rid, qid, s.correct_idx);
    perform public.h2h_answer(rid, qid, (s.correct_idx + 1) % 3); -- second click ignored
    perform pg_temp.as_user(CH); perform public.h2h_answer(rid, qid, (s.correct_idx + 1) % 3);
    select * into r from public.rooms where id = rid;
    assert r.phase = 'h2h_reveal', 'reveal expected';
    perform pg_temp.expire(rid); perform public.tick(rid);
  end loop;
  select * into r from public.rooms where id = rid;
  raise notice 'after Robi: phase=% pot=%', r.phase, r.state->'pot';
  assert (r.state->>'pot')::int = 8000 and r.phase = 'intro';
  assert (select status from public.room_players where id = pid_h) = 'home';

  -- ===== Player 2: Marko — no answers, offers by timeout, caught =====
  perform pg_temp.expire(rid); perform public.tick(rid);   -- cash
  perform pg_temp.expire(rid); perform public.tick(rid);   -- offer_set
  perform pg_temp.expire(rid); perform public.tick(rid);   -- offer_pick
  perform pg_temp.expire(rid); perform public.tick(rid);   -- h2h (mid)
  select * into r from public.rooms where id = rid;
  assert r.phase = 'h2h' and (r.state->'h2h'->>'player')::int = 3, 'mid start expected';
  for i in 1..3 loop
    select * into r from public.rooms where id = rid; select * into s from public.room_secrets where room_id = rid;
    qid := (r.state->'h2h'->'q'->>'id')::bigint;
    perform pg_temp.as_user(CH); perform public.h2h_answer(rid, qid, s.correct_idx);
    select * into r from public.rooms where id = rid;
    assert (r.state->'h2h'->>'rush')::boolean and r.phase_ends_at <= now() + interval '4 seconds', '4 s rush expected';
    perform pg_temp.expire(rid); perform public.tick(rid);  -- Marko never answers -> reveal
    select * into r from public.rooms where id = rid; assert r.phase = 'h2h_reveal';
    perform pg_temp.expire(rid); perform public.tick(rid);
  end loop;
  select * into r from public.rooms where id = rid;
  raise notice 'after Marko: phase=% h2h=%', r.phase, r.state->'h2h'->'reveal';
  assert (select status from public.room_players where room_id = rid and user_id = M::uuid) = 'caught';

  -- ===== Player 3: Luka — low offer, both correct, gets home =====
  perform pg_temp.expire(rid); perform public.tick(rid);   -- cash
  perform pg_temp.as_user(L);
  select * into r from public.rooms where id = rid; select * into s from public.room_secrets where room_id = rid;
  perform public.cash_answer(rid, (r.state->'cash'->'q'->>'id')::bigint, s.ans);
  perform pg_temp.expire(rid); perform public.tick(rid);   -- offer_set
  perform pg_temp.expire(rid); perform public.tick(rid);   -- offer_pick (defaults)
  perform public.pick_offer(rid, 'low');
  select * into r from public.rooms where id = rid;
  assert (r.state->'h2h'->>'player')::int = 4;
  for i in 1..3 loop
    select * into r from public.rooms where id = rid; select * into s from public.room_secrets where room_id = rid;
    qid := (r.state->'h2h'->'q'->>'id')::bigint;
    perform pg_temp.as_user(L); perform public.h2h_answer(rid, qid, s.correct_idx);
    perform pg_temp.as_user(CH); perform public.h2h_answer(rid, qid, s.correct_idx);
    perform pg_temp.expire(rid); perform public.tick(rid);
  end loop;
  select * into r from public.rooms where id = rid;
  raise notice 'before final: phase=% final=%', r.phase, r.state->'final';
  assert r.phase = 'final_intro';
  assert (r.state->'final'->>'head')::int = 2 and jsonb_array_length(r.state->'final'->'finalists') = 2;

  -- ===== Final: team =====
  perform pg_temp.expire(rid); perform public.tick(rid);
  select * into r from public.rooms where id = rid; assert r.phase = 'final_team';
  for i in 1..3 loop
    select * into r from public.rooms where id = rid; select * into s from public.room_secrets where room_id = rid;
    qid := (r.state->'final'->'q'->>'id')::bigint;
    perform pg_temp.as_user(H); perform public.final_answer(rid, qid, s.ans);
    perform pg_temp.as_user(L); res := public.final_answer(rid, qid, s.ans);  -- too late
    assert res ? 'stale', 'second answer should be stale';
  end loop;
  select * into r from public.rooms where id = rid;
  perform pg_temp.as_user(M); res := public.final_answer(rid, (r.state->'final'->'q'->>'id')::bigint, 'x');
  assert res ? 'ignored', 'caught player must not answer';
  perform pg_temp.as_user(L); perform public.final_answer(rid, (r.state->'final'->'q'->>'id')::bigint, 'krivo');
  select * into r from public.rooms where id = rid;
  raise notice 'team: team=% feed=%', r.state->'final'->'team', r.state->'final'->'feed';
  assert (r.state->'final'->>'team')::int = 5;

  perform pg_temp.expire(rid); perform public.tick(rid);  -- chaser intro
  perform pg_temp.expire(rid); perform public.tick(rid);  -- final_chaser
  select * into r from public.rooms where id = rid; assert r.phase = 'final_chaser';

  perform pg_temp.as_user(CH);
  for i in 1..2 loop
    select * into r from public.rooms where id = rid; select * into s from public.room_secrets where room_id = rid;
    perform public.final_answer(rid, (r.state->'final'->'q'->>'id')::bigint, s.ans);
  end loop;
  -- wrong -> pushback; captain right -> chaser back to 1
  select * into r from public.rooms where id = rid;
  qid := (r.state->'final'->'q'->>'id')::bigint;
  perform public.final_answer(rid, qid, 'krivo');
  select * into r from public.rooms where id = rid; select * into s from public.room_secrets where room_id = rid;
  assert r.phase = 'final_pushback', 'pushback expected';
  raise notice 'pushback state: %', r.state->'final'->'pb';
  perform pg_temp.as_user(L); res := public.final_answer(rid, qid, s.ans); assert res ? 'ignored', 'only captain';
  perform pg_temp.as_user(H); perform public.final_answer(rid, qid, s.ans);
  select * into r from public.rooms where id = rid;
  assert r.phase = 'final_chaser' and (r.state->'final'->>'chaser')::int = 1, 'pushback not applied';
  assert r.phase_ends_at > now(), 'clock should resume';
  -- pass -> pushback timeout
  perform pg_temp.as_user(CH);
  perform public.final_answer(rid, (r.state->'final'->'q'->>'id')::bigint, '');
  perform pg_temp.expire(rid); perform public.tick(rid);
  select * into r from public.rooms where id = rid; assert r.phase = 'final_chaser';
  -- chaser catches up: needs 5
  for i in 1..4 loop
    select * into r from public.rooms where id = rid; select * into s from public.room_secrets where room_id = rid;
    perform public.final_answer(rid, (r.state->'final'->'q'->>'id')::bigint, s.ans);
  end loop;
  select * into r from public.rooms where id = rid;
  raise notice 'end: phase=% result=% final=%', r.phase, r.state->'result', r.state->'final'->'feed';
  assert r.phase = 'finished' and r.state->'result'->>'winner' = 'chaser';

  perform pg_temp.as_user(H); perform public.reset_room(rid);
  select * into r from public.rooms where id = rid; assert r.phase = 'lobby';
  raise notice 'questions used: %', (select count(*) from public.questions where times_used > 0);
  raise notice 'ALL GOOD';
end $$;

-- Song questions: force a few and check shape + answer handling.
do $$
declare q jsonb; s public.room_secrets; rid uuid;
begin
  select id into rid from public.rooms limit 1;
  for i in 1..5 loop
    q := public._song_q(rid);
    select * into s from public.room_secrets where room_id = rid;
    assert q->>'cat' = 'glazba' and jsonb_array_length(q->'options') = 3, 'song shape';
    assert (q->'options'->>s.correct_idx) = s.ans, 'song correct index';
    assert (q->'audio'->>'deezer')::bigint > 0, 'deezer id';
  end loop;
  raise notice 'SONGS OK: %', q;
end $$;

do $$
declare rid uuid; q public.questions; n int := 0; mc jsonb;
begin
  select id into rid from public.rooms limit 1;
  for i in 1..30 loop
    q := public._pick_q(rid);
    assert q.category <> 'stihovi', 'lyrics must not appear in open rounds';
  end loop;
  for i in 1..40 loop
    mc := public._mc_q(rid);
    if mc->>'cat' = 'stihovi' then n := n + 1; end if;
  end loop;
  raise notice 'LYRICS OK: % lyric questions on the board out of 40', n;
end $$;
