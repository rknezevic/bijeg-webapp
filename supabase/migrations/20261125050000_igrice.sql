-- Video game questions + per-question "usage":
--   all   = can appear anywhere (all existing questions)
--   open  = only typed rounds (cash builder and final)
--   board = only the head-to-head board (A/B/C)
-- Works whether or not 20261125030000_stihovi.sql was run. Run it BEFORE seed.sql.

alter table public.questions add column if not exists usage text not null default 'all';
alter table public.questions drop constraint if exists questions_usage_check;
alter table public.questions add constraint questions_usage_check check (usage in ('all', 'open', 'board'));

alter table public.questions drop constraint if exists questions_category_check;
alter table public.questions add constraint questions_category_check
  check (category in ('hrvatska','opce','nogomet','sport','geografija','matematika','stihovi','igrice'));

drop function if exists public._pick_q(uuid);
drop function if exists public._pick_q(uuid, text);

-- p_cat: null = any normal category (never lyrics), or one category.
-- p_mode: 'open' (typed rounds) or 'board' (A/B/C).
create or replace function public._pick_q(p_room uuid, p_cat text default null, p_mode text default null) returns public.questions
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  q public.questions;
  used bigint[];
begin
  select used_q into used from public.room_secrets where room_id = p_room for update;
  select * into q from public.questions
   where not (id = any (coalesce(used, '{}')))
     and (case when p_cat is null then category <> 'stihovi' else category = p_cat end)
     and (p_mode is null or usage in ('all', p_mode))
   order by times_used, random() limit 1;
  if q.id is null then
    select * into q from public.questions
     where (case when p_cat is null then category <> 'stihovi' else category = p_cat end)
       and (p_mode is null or usage in ('all', p_mode))
     order by times_used, random() limit 1;
  end if;
  if q.id is null then
    if p_cat is not null then return null; end if;
    raise exception 'Baza pitanja je prazna.';
  end if;
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
  q := public._pick_q(p_room, null, 'open');
  return jsonb_build_object('id', q.id, 'text', q.question, 'cat', q.category);
end $$;

create or replace function public._mc_q(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  q public.questions;
  opts text[];
  song jsonb;
  r double precision := random();
begin
  if r < 0.3 then
    song := public._song_q(p_room);
    if song is not null then return song; end if;
  elsif r < 0.5 then
    q := public._pick_q(p_room, 'stihovi', 'board');
  end if;
  if q.id is null then
    q := public._pick_q(p_room, null, 'board');
  end if;
  select array_agg(o order by random()) into opts from unnest(array[q.answer] || q.wrong) o;
  update public.room_secrets set correct_idx = array_position(opts, q.answer) - 1 where room_id = p_room;
  return jsonb_build_object('id', q.id, 'text', q.question, 'cat', q.category, 'options', to_jsonb(opts));
end $$;

revoke execute on function public._pick_q(uuid, text, text) from public;
do $$ begin
  revoke execute on function public._pick_q(uuid, text, text) from anon, authenticated;
exception when undefined_object then null;
end $$;
