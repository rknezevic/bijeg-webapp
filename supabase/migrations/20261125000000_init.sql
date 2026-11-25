-- =====================================================================
-- BIJEG — kviz s lovcem
-- Schema, security and the whole game state machine.
-- Clients never write tables directly: every action is an RPC below.
-- The server clock (now()) decides timers and who answered first.
-- =====================================================================

create extension if not exists unaccent with schema extensions;
create extension if not exists fuzzystrmatch with schema extensions;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table if not exists public.questions (
  id           bigserial primary key,
  category     text not null check (category in ('hrvatska','opce','nogomet','sport','geografija','matematika')),
  question     text not null unique,
  answer       text not null,
  aliases      text[] not null default '{}',   -- other accepted answers ("Plitvice", "Mandžo")
  wrong        text[] not null check (array_length(wrong, 1) = 2), -- distractors for A/B/C
  difficulty   smallint not null default 1,
  times_used   integer not null default 0,
  last_used_at timestamptz
);
create index if not exists questions_usage_idx on public.questions (times_used);

create table if not exists public.rooms (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  host_user     uuid not null,
  phase         text not null default 'lobby',
  phase_ends_at timestamptz,
  state         jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.room_players (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid not null references public.rooms(id) on delete cascade,
  user_id    uuid not null,
  nickname   text not null,
  role       text check (role in ('chaser','player')),
  seat       smallint check (seat between 1 and 4),
  status     text not null default 'lobby', -- lobby | waiting | playing | home | caught | spectator
  bank       integer not null default 0,    -- won in the cash builder
  amount     integer not null default 0,    -- taken into the head-to-head (after the offer)
  joined_at  timestamptz not null default now(),
  unique (room_id, user_id)
);
create unique index if not exists room_players_one_chaser on public.room_players (room_id) where role = 'chaser';
create unique index if not exists room_players_seat on public.room_players (room_id, seat) where role = 'player';
create unique index if not exists room_players_nick on public.room_players (room_id, lower(nickname));

-- Never readable by clients: current answer, A/B/C picks, used questions.
create table if not exists public.room_secrets (
  room_id     uuid primary key references public.rooms(id) on delete cascade,
  used_q      bigint[] not null default '{}',
  ans         text,
  alts        text[],
  correct_idx integer,
  pick_p      integer,
  pick_c      integer
);

-- ---------------------------------------------------------------------
-- Row level security: members can read their room, nobody writes directly
-- ---------------------------------------------------------------------

alter table public.questions    enable row level security;
alter table public.rooms        enable row level security;
alter table public.room_players enable row level security;
alter table public.room_secrets enable row level security;

create or replace function public.is_member(p_room uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.room_players where room_id = p_room and user_id = auth.uid());
$$;

drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms for select to authenticated using (public.is_member(id));
drop policy if exists players_select on public.room_players;
create policy players_select on public.room_players for select to authenticated using (public.is_member(room_id));

-- Realtime
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.rooms;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.room_players;
    exception when duplicate_object then null;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Answer matching: case, č/ć/š/ž/đ, punctuation and small typos ignored
-- ---------------------------------------------------------------------

create or replace function public.norm_answer(t text) returns text
language sql stable set search_path = public, pg_temp as $$
  select trim(regexp_replace(
           regexp_replace(
             replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(t, ''))), 'dj', 'd'),
             '[^a-z0-9 ]+', ' ', 'g'),
           '\s+', ' ', 'g'));
$$;

create or replace function public.check_answer(given text, answer text, aliases text[]) returns boolean
language plpgsql stable set search_path = public, pg_temp as $$
declare
  g text := left(public.norm_answer(given), 250);
  g_digits text;
  c text;
  c_digits text;
  tol int;
begin
  if g = '' then return false; end if;
  g_digits := regexp_replace(g, '[^0-9]', '', 'g');
  foreach c in array (array[answer] || coalesce(aliases, '{}')) loop
    c := left(public.norm_answer(c), 250);
    continue when c = '';
    c_digits := regexp_replace(c, '[^0-9]', '', 'g');
    if c_digits <> '' then
      -- Any number in the answer must match exactly ("45", "45 minuta", "1.000" are fine; "40" is not).
      continue when g_digits <> c_digits;
      if c ~ '^[0-9 ]+$' or regexp_replace(g, '[0-9 ]', '', 'g') = '' then return true; end if;
    end if;
    if replace(g, ' ', '') = replace(c, ' ', '') then return true; end if;
    -- Small typos: 1 letter for normal words, 2 for long ones; never on very short words,
    -- and the first letter must be right (keeps Rajna/Majna, Iran/Irak apart).
    tol := case when length(c) <= 4 then 0 when length(c) <= 11 then 1 else 2 end;
    -- Very short words inside the answer ("vitamin D") must be typed exactly.
    if exists (select 1 from unnest(string_to_array(c, ' ')) t
               where length(t) <= 2 and not t = any (string_to_array(g, ' '))) then
      tol := 0;
    end if;
    if tol > 0 and left(g, 1) = left(c, 1) and extensions.levenshtein(g, c) <= tol then return true; end if;
  end loop;
  return false;
end $$;

-- ---------------------------------------------------------------------
-- Internal helpers (not callable by clients)
-- ---------------------------------------------------------------------

create or replace function public._save(p_room uuid, p_phase text, p_ends timestamptz, p_state jsonb) returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.rooms set phase = p_phase, phase_ends_at = p_ends, state = p_state, updated_at = now() where id = p_room;
$$;

create or replace function public._me(p_room uuid) returns public.room_players
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.room_players;
begin
  select * into me from public.room_players where room_id = p_room and user_id = auth.uid();
  if me.id is null then raise exception 'Nisi u ovoj sobi.'; end if;
  return me;
end $$;

-- Least-used question first, never repeated inside one room.
create or replace function public._pick_q(p_room uuid) returns public.questions
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  q public.questions;
  used bigint[];
begin
  select used_q into used from public.room_secrets where room_id = p_room for update;
  select * into q from public.questions
   where not (id = any (coalesce(used, '{}')))
   order by times_used, random() limit 1;
  if q.id is null then
    update public.room_secrets set used_q = '{}' where room_id = p_room;
    select * into q from public.questions order by times_used, random() limit 1;
  end if;
  if q.id is null then raise exception 'Baza pitanja je prazna.'; end if;
  update public.questions set times_used = times_used + 1, last_used_at = now() where id = q.id;
  update public.room_secrets
     set used_q = array_append(used_q, q.id), ans = q.answer, alts = q.aliases,
         correct_idx = null, pick_p = null, pick_c = null
   where room_id = p_room;
  return q;
end $$;

create or replace function public._open_q(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare q public.questions;
begin
  q := public._pick_q(p_room);
  return jsonb_build_object('id', q.id, 'text', q.question, 'cat', q.category);
end $$;

create or replace function public._mc_q(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  q public.questions;
  opts text[];
begin
  q := public._pick_q(p_room);
  select array_agg(o order by random()) into opts from unnest(array[q.answer] || q.wrong) o;
  update public.room_secrets set correct_idx = array_position(opts, q.answer) - 1 where room_id = p_room;
  return jsonb_build_object('id', q.id, 'text', q.question, 'cat', q.category, 'options', to_jsonb(opts));
end $$;

-- Next player's turn, or the final once everybody has played.
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
    'offer', null, 'h2h', null);
  perform public._save(p_room, 'intro', now() + interval '5 seconds', st);
end $$;

create or replace function public._start_offer_set(p_room uuid, st jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  bank int := coalesce((st->'cash'->>'bank')::int, 0);
  hi int := (round(greatest(bank * 3, bank + 3000) / 500.0) * 500)::int;
  lo int := greatest(0, (round(bank / 4.0 / 100.0) * 100)::int);
begin
  st := st || jsonb_build_object('offer', jsonb_build_object('bank', bank, 'high', hi, 'low', lo, 'set', false, 'choice', null));
  perform public._save(p_room, 'offer_set', now() + interval '25 seconds', st);
end $$;

create or replace function public._start_offer_pick(p_room uuid, st jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  st := jsonb_set(st, '{offer,set}', 'true'::jsonb);
  perform public._save(p_room, 'offer_pick', now() + interval '15 seconds', st);
end $$;

create or replace function public._next_h2h_q(p_room uuid, st jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare h jsonb := st->'h2h';
begin
  h := h || jsonb_build_object('n', (h->>'n')::int + 1, 'q', public._mc_q(p_room),
                               'lockP', false, 'lockC', false, 'reveal', null);
  perform public._save(p_room, 'h2h', now() + interval '20 seconds', st || jsonb_build_object('h2h', h));
end $$;

create or replace function public._start_h2h(p_room uuid, st jsonb, p_choice text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  o jsonb := st->'offer';
  pos int;
  amt int;
begin
  if p_choice = 'high' then pos := 2; amt := (o->>'high')::int;
  elsif p_choice = 'low' then pos := 4; amt := (o->>'low')::int;
  else p_choice := 'mid'; pos := 3; amt := (o->>'bank')::int;
  end if;
  update public.room_players set amount = amt where id = (st->>'current')::uuid;
  st := jsonb_set(st, '{offer,choice}', to_jsonb(p_choice));
  st := st || jsonb_build_object('h2h', jsonb_build_object('chaser', 0, 'player', pos, 'amount', amt, 'n', 0));
  perform public._next_h2h_q(p_room, st);
end $$;

create or replace function public._h2h_reveal(p_room uuid, st jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.room_secrets;
  h jsonb := st->'h2h';
  p_ok boolean;
  c_ok boolean;
  ppos int := (h->>'player')::int;
  cpos int := (h->>'chaser')::int;
  outcome text := null;
begin
  select * into s from public.room_secrets where room_id = p_room;
  p_ok := coalesce(s.pick_p = s.correct_idx, false);
  c_ok := coalesce(s.pick_c = s.correct_idx, false);
  if p_ok then ppos := ppos + 1; end if;
  if c_ok then cpos := cpos + 1; end if;
  if ppos >= 7 then
    outcome := 'home';
    update public.room_players set status = 'home' where id = (st->>'current')::uuid;
    st := st || jsonb_build_object('pot', (st->>'pot')::int + (h->>'amount')::int);
  elsif cpos >= ppos then
    outcome := 'caught';
    update public.room_players set status = 'caught' where id = (st->>'current')::uuid;
  end if;
  h := h || jsonb_build_object('player', ppos, 'chaser', cpos, 'lockP', true, 'lockC', true,
    'reveal', jsonb_build_object('correct', s.correct_idx, 'p', s.pick_p, 'c', s.pick_c,
                                 'pOk', p_ok, 'cOk', c_ok, 'outcome', outcome));
  perform public._save(p_room, 'h2h_reveal',
    now() + case when outcome is null then interval '4 seconds' else interval '6 seconds' end,
    st || jsonb_build_object('h2h', h));
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
    -- Nobody made it home: everyone plays the final for their cash-builder money.
    select coalesce(jsonb_agg(id order by seat), '[]'::jsonb), coalesce(sum(bank), 0) into fin, pot
      from public.room_players where room_id = p_room and role = 'player';
  end if;
  st := st || jsonb_build_object('final', jsonb_build_object(
    'finalists', fin, 'captain', fin->>0, 'pot', pot, 'head', home_cnt,
    'team', home_cnt, 'chaser', 0, 'q', null, 'feed', '[]'::jsonb, 'last', null,
    'remaining', null, 'pb', null, 'seq', 0));
  perform public._save(p_room, 'final_intro', now() + interval '6 seconds', st);
end $$;

create or replace function public._finish(p_room uuid, st jsonb, p_winner text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  f jsonb := st->'final';
  pot int := (f->>'pot')::int;
  n int := greatest(jsonb_array_length(f->'finalists'), 1);
begin
  st := st || jsonb_build_object('result', jsonb_build_object(
    'winner', p_winner, 'pot', pot, 'each', case when p_winner = 'team' then pot / n else 0 end));
  perform public._save(p_room, 'finished', null, st);
end $$;

-- Adds a line to the final-chase feed and returns the updated final object.
create or replace function public._feed(f jsonb, p_by text, p_who text, p_given text, p_answer text, p_ok boolean) returns jsonb
language plpgsql immutable as $$
declare
  e jsonb;
  seq int := coalesce((f->>'seq')::int, 0) + 1;
  feed jsonb := coalesce(f->'feed', '[]'::jsonb);
begin
  e := jsonb_build_object('seq', seq, 'by', p_by, 'who', p_who, 'given', p_given, 'answer', p_answer, 'ok', p_ok);
  feed := jsonb_build_array(e) || feed;
  if jsonb_array_length(feed) > 6 then feed := feed - 6; end if;
  return f || jsonb_build_object('seq', seq, 'feed', feed, 'last', e);
end $$;

-- After a pushback attempt (or its timeout) the chaser's clock runs again.
create or replace function public._resume_chaser(p_room uuid, st jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare f jsonb := st->'final';
begin
  f := f || jsonb_build_object('q', public._open_q(p_room), 'pb', null);
  perform public._save(p_room, 'final_chaser',
    now() + make_interval(secs => greatest((f->>'remaining')::numeric, 0) / 1000.0),
    st || jsonb_build_object('final', f || jsonb_build_object('remaining', null)));
end $$;

-- ---------------------------------------------------------------------
-- RPCs — lobby
-- ---------------------------------------------------------------------

create or replace function public.server_now() returns timestamptz
language sql stable as $$ select clock_timestamp(); $$;

create or replace function public._check_nick(p_nick text) returns text
language plpgsql immutable as $$
declare n text := trim(regexp_replace(coalesce(p_nick, ''), '\s+', ' ', 'g'));
begin
  if length(n) < 2 or length(n) > 16 then raise exception 'Nadimak mora imati 2 do 16 znakova.'; end if;
  return n;
end $$;

create or replace function public.create_room(p_nick text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  n text := public._check_nick(p_nick);
  c text;
  rid uuid;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if auth.uid() is null then raise exception 'Nema sesije.'; end if;
  loop
    select string_agg(substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1), '')
      into c from generate_series(1, 6);
    exit when not exists (select 1 from public.rooms where code = c);
  end loop;
  insert into public.rooms (code, host_user) values (c, auth.uid()) returning id into rid;
  insert into public.room_secrets (room_id) values (rid);
  insert into public.room_players (room_id, user_id, nickname) values (rid, auth.uid(), n);
  return jsonb_build_object('room_id', rid, 'code', c);
end $$;

create or replace function public.join_room(p_code text, p_nick text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  n text;
begin
  if auth.uid() is null then raise exception 'Nema sesije.'; end if;
  select * into r from public.rooms where code = upper(trim(p_code));
  if r.id is null then raise exception 'Soba ne postoji.'; end if;
  if exists (select 1 from public.room_players where room_id = r.id and user_id = auth.uid()) then
    return jsonb_build_object('room_id', r.id, 'code', r.code);
  end if;
  n := public._check_nick(p_nick);
  if exists (select 1 from public.room_players where room_id = r.id and lower(nickname) = lower(n)) then
    raise exception 'Nadimak je već zauzet u ovoj sobi.';
  end if;
  if (select count(*) from public.room_players where room_id = r.id) >= 12 then
    raise exception 'Soba je puna.';
  end if;
  insert into public.room_players (room_id, user_id, nickname, status)
  values (r.id, auth.uid(), n, case when r.phase = 'lobby' then 'lobby' else 'spectator' end);
  return jsonb_build_object('room_id', r.id, 'code', r.code);
end $$;

-- Read a room's code before joining (for the join screen).
create or replace function public.room_info(p_code text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'code', r.code, 'phase', r.phase,
    'host', (select nickname from public.room_players p where p.room_id = r.id and p.user_id = r.host_user),
    'count', (select count(*) from public.room_players p where p.room_id = r.id),
    'member', exists (select 1 from public.room_players p where p.room_id = r.id and p.user_id = auth.uid()))
  from public.rooms r where r.code = upper(trim(p_code));
$$;

create or replace function public.choose_role(p_room uuid, p_role text, p_seat int default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  me public.room_players;
begin
  select * into r from public.rooms where id = p_room for update;
  me := public._me(p_room);
  if r.phase <> 'lobby' then raise exception 'Igra je već počela.'; end if;
  if p_role = 'chaser' then
    if exists (select 1 from public.room_players where room_id = p_room and role = 'chaser' and id <> me.id) then
      raise exception 'Lovac je već odabran.';
    end if;
    update public.room_players set role = 'chaser', seat = null where id = me.id;
  elsif p_role = 'player' then
    if p_seat is null or p_seat not between 1 and 4 then raise exception 'Neispravno mjesto.'; end if;
    if exists (select 1 from public.room_players where room_id = p_room and role = 'player' and seat = p_seat and id <> me.id) then
      raise exception 'To mjesto je zauzeto.';
    end if;
    update public.room_players set role = 'player', seat = p_seat where id = me.id;
  else
    update public.room_players set role = null, seat = null where id = me.id;
  end if;
  update public.rooms set updated_at = now() where id = p_room;
end $$;

create or replace function public.start_game(p_room uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  n_players int;
  n_chasers int;
  ord jsonb;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.host_user <> auth.uid() then raise exception 'Samo domaćin može pokrenuti igru.'; end if;
  if r.phase <> 'lobby' then raise exception 'Igra je već počela.'; end if;
  select count(*) filter (where role = 'player'), count(*) filter (where role = 'chaser')
    into n_players, n_chasers from public.room_players where room_id = p_room;
  if n_chasers <> 1 then raise exception 'Potreban je točno jedan lovac.'; end if;
  if n_players < 2 or n_players > 4 then raise exception 'Potrebno je 2 do 4 igrača.'; end if;
  update public.room_players
     set status = case when role = 'player' then 'waiting' when role = 'chaser' then 'chaser' else 'spectator' end,
         bank = 0, amount = 0
   where room_id = p_room;
  select jsonb_agg(id order by seat) into ord from public.room_players where room_id = p_room and role = 'player';
  perform public._start_intro(p_room, jsonb_build_object('order', ord, 'idx', 0, 'pot', 0));
end $$;

create or replace function public.reset_room(p_room uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.rooms;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.host_user <> auth.uid() then raise exception 'Samo domaćin može pokrenuti novu igru.'; end if;
  update public.room_players set status = 'lobby', bank = 0, amount = 0 where room_id = p_room;
  perform public._save(p_room, 'lobby', null, '{}'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- RPCs — the clock. Any client calls tick() once a deadline has passed;
-- the server only advances if its own clock agrees.
-- ---------------------------------------------------------------------

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
    when 'intro' then
      perform public._save(p_room, 'cash', now() + interval '60 seconds',
        jsonb_set(st, '{cash,q}', public._open_q(p_room)));
    when 'cash' then
      perform public._start_offer_set(p_room, st);
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
    when 'final_intro' then
      perform public._save(p_room, 'final_team', now() + interval '120 seconds',
        jsonb_set(st, '{final,q}', public._open_q(p_room)));
    when 'final_team' then
      perform public._save(p_room, 'final_chaser_intro', now() + interval '6 seconds',
        jsonb_set(st, '{final,q}', 'null'::jsonb));
    when 'final_chaser_intro' then
      perform public._save(p_room, 'final_chaser', now() + interval '120 seconds',
        jsonb_set(st, '{final,q}', public._open_q(p_room)));
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

-- ---------------------------------------------------------------------
-- RPCs — cash builder
-- ---------------------------------------------------------------------

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
  c := c || jsonb_build_object(
    'last', jsonb_build_object('seq', coalesce((c->'last'->>'seq')::int, 0) + 1,
                               'given', nullif(trim(p_text), ''), 'answer', s.ans,
                               'ok', case when skip then null else ok end),
    'q', public._open_q(p_room));
  perform public._save(p_room, 'cash', r.phase_ends_at, st || jsonb_build_object('cash', c));
  return jsonb_build_object('ok', ok);
end $$;

-- ---------------------------------------------------------------------
-- RPCs — offers
-- ---------------------------------------------------------------------

create or replace function public.set_offers(p_room uuid, p_high int, p_low int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  me public.room_players;
  st jsonb;
  bank int;
begin
  select * into r from public.rooms where id = p_room for update;
  me := public._me(p_room);
  if me.role <> 'chaser' or r.phase <> 'offer_set' then raise exception 'Sada ne možeš davati ponude.'; end if;
  st := r.state;
  bank := (st->'offer'->>'bank')::int;
  if p_high <= bank or p_high > 1000000 then raise exception 'Viša ponuda mora biti veća od %.', bank; end if;
  if p_low > bank or p_low < -100000 then raise exception 'Niža ponuda ne smije biti veća od %.', bank; end if;
  if p_low = bank and bank > 0 then raise exception 'Niža ponuda mora biti manja od %.', bank; end if;
  st := jsonb_set(jsonb_set(st, '{offer,high}', to_jsonb(p_high)), '{offer,low}', to_jsonb(p_low));
  perform public._start_offer_pick(p_room, st);
end $$;

create or replace function public.pick_offer(p_room uuid, p_choice text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  me public.room_players;
begin
  select * into r from public.rooms where id = p_room for update;
  me := public._me(p_room);
  if r.phase <> 'offer_pick' or (r.state->>'current')::uuid <> me.id then raise exception 'Sada ne možeš birati ponudu.'; end if;
  if p_choice not in ('high', 'mid', 'low') then raise exception 'Neispravan izbor.'; end if;
  perform public._start_h2h(p_room, r.state, p_choice);
end $$;

-- ---------------------------------------------------------------------
-- RPCs — head-to-head (A/B/C)
-- ---------------------------------------------------------------------

create or replace function public.h2h_answer(p_room uuid, p_qid bigint, p_idx int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  me public.room_players;
  s public.room_secrets;
  st jsonb;
  h jsonb;
begin
  select * into r from public.rooms where id = p_room for update;
  me := public._me(p_room);
  st := r.state;
  h := st->'h2h';
  if r.phase <> 'h2h' or (h->'q'->>'id')::bigint <> p_qid or p_idx not between 0 and 2 then return; end if;
  if now() >= r.phase_ends_at then perform public.tick(p_room); return; end if;
  select * into s from public.room_secrets where room_id = p_room for update;
  if me.id = (st->>'current')::uuid then
    if s.pick_p is not null then return; end if;
    update public.room_secrets set pick_p = p_idx where room_id = p_room;
    h := h || jsonb_build_object('lockP', true);
  elsif me.role = 'chaser' then
    if s.pick_c is not null then return; end if;
    update public.room_secrets set pick_c = p_idx where room_id = p_room;
    h := h || jsonb_build_object('lockC', true);
  else
    return;
  end if;
  st := st || jsonb_build_object('h2h', h);
  if (h->>'lockP')::boolean and (h->>'lockC')::boolean then
    perform public._h2h_reveal(p_room, st);
  else
    perform public._save(p_room, 'h2h', r.phase_ends_at, st);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- RPCs — final chase. One function for team answers, chaser answers and
-- the captain's pushback. Empty text = pass.
-- The first submission for a question wins; later ones are 'stale'.
-- ---------------------------------------------------------------------

create or replace function public.final_answer(p_room uuid, p_qid bigint, p_text text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.rooms;
  me public.room_players;
  s public.room_secrets;
  st jsonb;
  f jsonb;
  ok boolean;
  skip boolean := coalesce(trim(p_text), '') = '';
  given text := nullif(trim(p_text), '');
begin
  select * into r from public.rooms where id = p_room for update;
  me := public._me(p_room);
  st := r.state;
  f := st->'final';
  if r.phase not in ('final_team', 'final_chaser', 'final_pushback') then return jsonb_build_object('ignored', true); end if;
  if now() >= r.phase_ends_at then perform public.tick(p_room); return jsonb_build_object('late', true); end if;
  if (f->'q'->>'id')::bigint is distinct from p_qid then return jsonb_build_object('stale', true); end if;
  select * into s from public.room_secrets where room_id = p_room;
  ok := not skip and public.check_answer(p_text, s.ans, s.alts);

  if r.phase = 'final_team' then
    if not (f->'finalists') ? me.id::text then return jsonb_build_object('ignored', true); end if;
    if ok then f := f || jsonb_build_object('team', (f->>'team')::int + 1); end if;
    f := public._feed(f, 'team', me.nickname, given, s.ans, case when skip then null else ok end);
    f := f || jsonb_build_object('q', public._open_q(p_room));
    perform public._save(p_room, 'final_team', r.phase_ends_at, st || jsonb_build_object('final', f));

  elsif r.phase = 'final_chaser' then
    if me.role <> 'chaser' then return jsonb_build_object('ignored', true); end if;
    if ok then
      f := f || jsonb_build_object('chaser', (f->>'chaser')::int + 1);
      f := public._feed(f, 'chaser', me.nickname, given, s.ans, true);
      if (f->>'chaser')::int >= (f->>'team')::int then
        perform public._finish(p_room, st || jsonb_build_object('final', f), 'chaser');
      else
        f := f || jsonb_build_object('q', public._open_q(p_room));
        perform public._save(p_room, 'final_chaser', r.phase_ends_at, st || jsonb_build_object('final', f));
      end if;
    else
      -- Chaser wrong or passed: clock stops, the captain gets 10 seconds.
      f := f || jsonb_build_object(
        'remaining', (extract(epoch from (r.phase_ends_at - now())) * 1000)::int,
        'pb', jsonb_build_object('given', given, 'who', me.nickname));
      perform public._save(p_room, 'final_pushback', now() + interval '10 seconds', st || jsonb_build_object('final', f));
    end if;

  else -- final_pushback
    if me.id::text <> f->>'captain' then return jsonb_build_object('ignored', true); end if;
    if ok then
      if (f->>'chaser')::int > 0 then
        f := f || jsonb_build_object('chaser', (f->>'chaser')::int - 1);
      else
        f := f || jsonb_build_object('team', (f->>'team')::int + 1);
      end if;
    end if;
    f := public._feed(f, 'captain', me.nickname, given, s.ans, case when skip then null else ok end);
    perform public._resume_chaser(p_room, st || jsonb_build_object('final', f));
  end if;
  return jsonb_build_object('ok', ok);
end $$;

-- ---------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------

revoke all on public.room_secrets from anon, authenticated;
revoke all on public.questions from anon, authenticated;
revoke insert, update, delete on public.rooms, public.room_players from anon, authenticated;

do $$
declare fn record;
begin
  for fn in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like '\_%' escape '\'
  loop
    execute format('revoke execute on function %s from public', fn.sig);
    begin
      execute format('revoke execute on function %s from anon, authenticated', fn.sig);
    exception when undefined_object then null;
    end;
  end loop;
end $$;
