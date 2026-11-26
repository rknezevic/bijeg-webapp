-- "Spreman sam" instead of countdowns between rounds, and harder song questions.
--
-- Waiting phases (no timer, the game waits until everyone needed clicks ready):
--   intro              before each player's 1-minute round  -> that player
--   h2h_ready          after the 1-minute round, before the offer/board -> that player + chaser
--   final_intro        before the final                     -> all finalists + chaser
--   final_chaser_intro before the chaser's turn in the final -> chaser
-- The host can always skip the wait with force_ready() (e.g. if someone's phone died).
--
-- Songs: the two wrong options are other songs by the SAME artist when possible.

create or replace function public._ready_required(p_room uuid, p_phase text, st jsonb) returns uuid[]
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  chaser uuid := (select id from public.room_players where room_id = p_room and role = 'chaser' limit 1);
  cur uuid := (st->>'current')::uuid;
  fin uuid[];
begin
  if p_phase = 'intro' then return array[cur]; end if;
  if p_phase = 'h2h_ready' then return array[cur, chaser]; end if;
  if p_phase = 'final_chaser_intro' then return array[chaser]; end if;
  if p_phase = 'final_intro' then
    select coalesce(array_agg(x::uuid), '{}') into fin from jsonb_array_elements_text(st->'final'->'finalists') x;
    return fin || chaser;
  end if;
  return '{}';
end $$;

create or replace function public._after_ready(p_room uuid, p_phase text, st jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  st := st - 'ready';
  if p_phase = 'intro' then
    perform public._save(p_room, 'cash', now() + interval '60 seconds', jsonb_set(st, '{cash,q}', public._open_q(p_room)));
  elsif p_phase = 'h2h_ready' then
    perform public._start_offer_set(p_room, st);
  elsif p_phase = 'final_intro' then
    perform public._save(p_room, 'final_team', now() + interval '120 seconds', jsonb_set(st, '{final,q}', public._open_q(p_room)));
  elsif p_phase = 'final_chaser_intro' then
    perform public._save(p_room, 'final_chaser', now() + interval '120 seconds', jsonb_set(st, '{final,q}', public._open_q(p_room)));
  end if;
end $$;

create or replace function public._start_intro(p_room uuid, st jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  idx int := (st->>'idx')::int;
  cur uuid;
begin
  if idx >= jsonb_array_length(st->'order') then
    perform public._start_final_intro(p_room, st);
    return;
  end if;
  cur := (st->'order'->>idx)::uuid;
  update public.room_players set status = 'playing' where id = cur;
  st := st || jsonb_build_object(
    'current', cur,
    'cash', jsonb_build_object('correct', 0, 'wrong', 0, 'skipped', 0, 'bank', 0, 'last', null, 'q', null),
    'offer', null, 'h2h', null, 'ready', '[]'::jsonb);
  perform public._save(p_room, 'intro', null, st);
end $$;

create or replace function public._start_final_intro(p_room uuid, st jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  fin jsonb;
  home_cnt int;
  pot int := (st->>'pot')::int;
begin
  select coalesce(jsonb_agg(id order by seat), '[]'::jsonb), count(*) into fin, home_cnt
    from public.room_players where room_id = p_room and role = 'player' and status = 'home';
  if home_cnt = 0 then
    select coalesce(jsonb_agg(id order by seat), '[]'::jsonb), coalesce(sum(bank), 0) into fin, pot
      from public.room_players where room_id = p_room and role = 'player';
  end if;
  st := st || jsonb_build_object('ready', '[]'::jsonb, 'final', jsonb_build_object(
    'finalists', fin, 'captain', fin->>0, 'pot', pot, 'head', home_cnt,
    'team', home_cnt, 'chaser', 0, 'q', null, 'feed', '[]'::jsonb, 'last', null,
    'remaining', null, 'pb', null, 'seq', 0));
  perform public._save(p_room, 'final_intro', null, st);
end $$;

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
      perform public._save(p_room, 'h2h_ready', null, st || jsonb_build_object('ready', '[]'::jsonb));
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

-- Rooms that were mid-countdown when this migration ran: let them continue.
update public.rooms set phase_ends_at = null, state = state || '{"ready": []}'::jsonb
 where phase in ('intro', 'final_intro', 'final_chaser_intro');

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
  if not exists (select 1 from unnest(req) x where x is not null and not rd ? x::text) then
    perform public._after_ready(p_room, r.phase, st);
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
  perform public._after_ready(p_room, r.phase, r.state);
end $$;

-- Songs: wrong options from the same artist first, then the same region.
create or replace function public._song_q(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.songs;
  used bigint[];
  label text;
  wrongs text[];
  opts text[];
begin
  select used_songs into used from public.room_secrets where room_id = p_room for update;
  select * into s from public.songs where not (id = any (coalesce(used, '{}')))
   order by times_used, random() limit 1;
  if s.id is null then
    update public.room_secrets set used_songs = '{}' where room_id = p_room;
    select * into s from public.songs order by times_used, random() limit 1;
  end if;
  if s.id is null then return null; end if;

  label := s.artist || ' – ' || s.title;
  select array_agg(l) into wrongs from (
    select artist || ' – ' || title as l from public.songs
     where id <> s.id and region = s.region and lower(title) <> lower(s.title)
     order by (artist = s.artist) desc, random()
     limit 2) x;
  if coalesce(array_length(wrongs, 1), 0) < 2 then return null; end if;

  select array_agg(o order by random()) into opts from unnest(array[label] || wrongs) o;
  update public.songs set times_used = times_used + 1 where id = s.id;
  update public.room_secrets
     set used_songs = array_append(used_songs, s.id), ans = label, alts = null,
         correct_idx = array_position(opts, label) - 1, pick_p = null, pick_c = null
   where room_id = p_room;
  return jsonb_build_object(
    'id', -s.id, 'text', 'Koja je ovo pjesma?', 'cat', 'glazba', 'options', to_jsonb(opts),
    'audio', jsonb_build_object('deezer', s.deezer_id, 'start', floor(random() * 14)::int));
end $$;

grant execute on function public.set_ready(uuid), public.force_ready(uuid) to authenticated;
do $$
declare f text;
begin
  foreach f in array array['public._ready_required(uuid, text, jsonb)', 'public._after_ready(uuid, text, jsonb)'] loop
    execute format('revoke execute on function %s from public', f);
    begin
      execute format('revoke execute on function %s from anon, authenticated', f);
    exception when undefined_object then null;
    end;
  end loop;
end $$;
