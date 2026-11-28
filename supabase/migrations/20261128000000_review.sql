-- Host review of the 1-minute round.
--
-- Every typed answer in the cash builder is logged in state.cash.log:
--   { i, q (question), a (correct answer), g (what was typed, null = skipped), ok, auto (what the checker said) }
-- After the minute, the game waits in h2h_ready as before, but now it also needs the host's approval:
--   review_toggle(room, i)  host flips one answer between correct and wrong (bank is recalculated)
--   review_approve(room)    host confirms the list ("Sve je OK")
-- The game moves on once the host has approved AND the player and the chaser have clicked "Spreman sam".
-- force_ready() (host) still skips everything.

create or replace function public.cash_answer(p_room uuid, p_qid bigint, p_text text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  me public.room_players;
  s public.room_secrets;
  st jsonb;
  c jsonb;
  ok boolean;
  skip boolean := coalesce(trim(p_text), '') = '';
  lg jsonb;
begin
  select * into r from public.rooms where id = p_room for update;
  me := public._me(p_room);
  st := r.state;
  if r.phase <> 'cash' or (st->>'current')::uuid <> me.id then return jsonb_build_object('ignored', true); end if;
  if now() >= r.phase_ends_at then perform public.tick(p_room); return jsonb_build_object('late', true); end if;
  if (st->'cash'->'q'->>'id')::bigint <> p_qid then return jsonb_build_object('stale', true); end if;
  select * into s from public.room_secrets where room_id = p_room;
  ok := not skip and public.check_answer(p_text, s.ans, s.alts);
  c := st->'cash';
  if ok then
    update public.room_players set bank = bank + 500 where id = me.id;
    c := c || jsonb_build_object('correct', (c->>'correct')::int + 1, 'bank', (c->>'bank')::int + 500);
  elsif skip then
    c := c || jsonb_build_object('skipped', (c->>'skipped')::int + 1);
  else
    c := c || jsonb_build_object('wrong', (c->>'wrong')::int + 1);
  end if;
  lg := coalesce(c->'log', '[]'::jsonb);
  lg := lg || jsonb_build_array(jsonb_build_object(
    'i', jsonb_array_length(lg), 'q', c->'q'->>'text', 'a', s.ans,
    'g', nullif(trim(p_text), ''), 'ok', case when skip then null else ok end,
    'auto', case when skip then null else ok end));
  c := c || jsonb_build_object(
    'log', lg,
    'last', jsonb_build_object('seq', coalesce((c->'last'->>'seq')::int, 0) + 1,
                               'given', nullif(trim(p_text), ''), 'answer', s.ans,
                               'ok', case when skip then null else ok end),
    'q', public._open_q(p_room));
  perform public._save(p_room, 'cash', r.phase_ends_at, st || jsonb_build_object('cash', c));
  return jsonb_build_object('ok', ok);
end $$;

-- After the minute: wait for the host's review as well as the ready clicks.
create or replace function public.tick(p_room uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  st jsonb;
  f jsonb;
begin
  if not public.is_member(p_room) then raise exception 'Nisi u ovoj sobi.'; end if;
  select * into r from public.rooms where id = p_room for update;
  if r.phase_ends_at is null or now() < r.phase_ends_at then return r.phase; end if;
  st := r.state;
  case r.phase
    when 'cash' then
      perform public._save(p_room, 'h2h_ready', null,
        jsonb_set(st, '{cash,q}', 'null'::jsonb) || jsonb_build_object('ready', '[]'::jsonb, 'approved', false));
    when 'offer_set' then
      perform public._start_offer_pick(p_room, st);
    when 'offer_pick' then
      perform public._start_h2h(p_room, st, 'mid');
    when 'h2h' then
      perform public._h2h_reveal(p_room, st);
    when 'h2h_reveal' then
      if st->'h2h'->'reveal'->>'outcome' is null then
        perform public._next_h2h_q(p_room, st);
      else
        perform public._start_intro(p_room, st || jsonb_build_object('idx', (st->>'idx')::int + 1));
      end if;
    when 'final_team' then
      perform public._save(p_room, 'final_chaser_intro', null,
        jsonb_set(st, '{final,q}', 'null'::jsonb) || jsonb_build_object('ready', '[]'::jsonb));
    when 'final_chaser' then
      perform public._finish(p_room, st, 'team');
    when 'final_pushback' then
      f := public._feed(st->'final', 'captain', null, null,
                        (select ans from public.room_secrets where room_id = p_room), false);
      perform public._resume_chaser(p_room, st || jsonb_build_object('final', f));
    else
      null;
  end case;
  return (select phase from public.rooms where id = p_room);
end $$;

-- Everyone needed is ready (and, after the minute, the host has approved the answers).
create or replace function public._ready_done(p_room uuid, p_phase text, st jsonb) returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  req uuid[] := public._ready_required(p_room, p_phase, st);
  rd jsonb := coalesce(st->'ready', '[]'::jsonb);
begin
  if exists (select 1 from unnest(req) x where x is not null and not rd ? x::text) then return false; end if;
  if p_phase = 'h2h_ready' and not coalesce((st->>'approved')::boolean, true) then return false; end if;
  return true;
end $$;

create or replace function public.set_ready(p_room uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  me public.room_players;
  st jsonb;
  req uuid[];
  rd jsonb;
begin
  select * into r from public.rooms where id = p_room for update;
  me := public._me(p_room);
  if r.phase not in ('intro', 'h2h_ready', 'final_intro', 'final_chaser_intro') then return; end if;
  st := r.state;
  req := public._ready_required(p_room, r.phase, st);
  if not (me.id = any (req)) then return; end if;
  rd := coalesce(st->'ready', '[]'::jsonb);
  if not rd ? me.id::text then rd := rd || to_jsonb(me.id::text); end if;
  st := st || jsonb_build_object('ready', rd);
  if public._ready_done(p_room, r.phase, st) then
    perform public._after_ready(p_room, r.phase, st - 'approved');
  else
    perform public._save(p_room, r.phase, null, st);
  end if;
end $$;

create or replace function public.force_ready(p_room uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.rooms;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.host_user <> auth.uid() then raise exception 'Samo domaćin može preskočiti čekanje.'; end if;
  if r.phase not in ('intro', 'h2h_ready', 'final_intro', 'final_chaser_intro') then return; end if;
  perform public._after_ready(p_room, r.phase, r.state - 'approved');
end $$;

-- Host flips one answer of the minute between correct and wrong.
create or replace function public.review_toggle(p_room uuid, p_i int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  st jsonb;
  c jsonb;
  lg jsonb;
  e jsonb;
  n_ok int;
  n_bad int;
  old_bank int;
  new_bank int;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.host_user <> auth.uid() then raise exception 'Samo domaćin može mijenjati odgovore.'; end if;
  if r.phase <> 'h2h_ready' then raise exception 'Odgovori se mogu mijenjati samo nakon brzog kruga.'; end if;
  st := r.state;
  c := st->'cash';
  lg := coalesce(c->'log', '[]'::jsonb);
  if p_i < 0 or p_i >= jsonb_array_length(lg) then return; end if;
  e := lg->p_i;
  if e->>'g' is null then return; end if;           -- skipped questions can't be accepted
  lg := jsonb_set(lg, array[p_i::text, 'ok'], to_jsonb(not (e->>'ok')::boolean));

  select count(*) filter (where (x->>'ok')::boolean), count(*) filter (where not (x->>'ok')::boolean)
    into n_ok, n_bad from jsonb_array_elements(lg) x where x->>'g' is not null;
  old_bank := coalesce((c->>'bank')::int, 0);
  new_bank := n_ok * 500;
  update public.room_players set bank = bank + (new_bank - old_bank) where id = (st->>'current')::uuid;
  c := c || jsonb_build_object('log', lg, 'correct', n_ok, 'wrong', n_bad, 'bank', new_bank);
  perform public._save(p_room, 'h2h_ready', null, st || jsonb_build_object('cash', c));
end $$;

-- Host confirms the answers of the minute.
create or replace function public.review_approve(p_room uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  st jsonb;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.host_user <> auth.uid() then raise exception 'Samo domaćin može odobriti odgovore.'; end if;
  if r.phase <> 'h2h_ready' then return; end if;
  st := r.state || jsonb_build_object('approved', true);
  if public._ready_done(p_room, 'h2h_ready', st) then
    perform public._after_ready(p_room, 'h2h_ready', st - 'approved');
  else
    perform public._save(p_room, 'h2h_ready', null, st);
  end if;
end $$;

grant execute on function public.review_toggle(uuid, int), public.review_approve(uuid) to authenticated;
do $$
begin
  revoke execute on function public._ready_done(uuid, text, jsonb) from public;
  begin
    revoke execute on function public._ready_done(uuid, text, jsonb) from anon, authenticated;
  exception when undefined_object then null;
  end;
end $$;
