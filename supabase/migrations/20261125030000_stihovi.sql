-- "Nadopuni stih" questions on the board (head-to-head only).
-- You write them yourselves in questions/stihovi.txt; they are stored as
-- questions with category 'stihovi'. On the board about 20 % of questions are
-- lyric questions (when there are any), 30 % songs, the rest normal questions.
-- Run after 20261125020000_songs.sql.

alter table public.questions drop constraint if exists questions_category_check;
alter table public.questions add constraint questions_category_check
  check (category in ('hrvatska','opce','nogomet','sport','geografija','matematika','stihovi'));

-- p_cat: null = any normal category (never lyrics), 'stihovi' = only lyrics.
create or replace function public._pick_q(p_room uuid, p_cat text default null) returns public.questions
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  q public.questions;
  used bigint[];
begin
  select used_q into used from public.room_secrets where room_id = p_room for update;
  select * into q from public.questions
   where not (id = any (coalesce(used, '{}')))
     and (case when p_cat is null then category <> 'stihovi' else category = p_cat end)
   order by times_used, random() limit 1;
  if q.id is null then
    select * into q from public.questions
     where (case when p_cat is null then category <> 'stihovi' else category = p_cat end)
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
    q := public._pick_q(p_room, 'stihovi');
  end if;
  if q.id is null then
    q := public._pick_q(p_room);
  end if;
  select array_agg(o order by random()) into opts from unnest(array[q.answer] || q.wrong) o;
  update public.room_secrets set correct_idx = array_position(opts, q.answer) - 1 where room_id = p_room;
  return jsonb_build_object('id', q.id, 'text', q.question, 'cat', q.category, 'options', to_jsonb(opts));
end $$;

do $$ begin
  revoke execute on function public._pick_q(uuid, text) from public;
  revoke execute on function public._pick_q(uuid, text) from anon, authenticated;
exception when undefined_object then null;
end $$;
-- The old one-argument version is replaced by the default parameter above.
drop function if exists public._pick_q(uuid);
