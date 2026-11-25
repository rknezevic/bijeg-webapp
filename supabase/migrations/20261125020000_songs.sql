-- Song recognition on the board (head-to-head).
-- About 30 % of board questions become "Koja je ovo pjesma?": every phone gets a
-- Deezer track id and plays a random slice of its 30-second preview.
-- Wrong options are two other songs from the same region (balkan / svijet).
-- Run after 20261125010000_h2h_rush.sql, then run supabase/seed_songs.sql.

create table if not exists public.songs (
  id         bigserial primary key,
  region     text not null check (region in ('balkan', 'svijet')),
  artist     text not null,
  title      text not null,
  deezer_id  bigint not null,
  times_used integer not null default 0,
  unique (artist, title)
);
alter table public.songs enable row level security;
revoke all on public.songs from anon, authenticated;

alter table public.room_secrets add column if not exists used_songs bigint[] not null default '{}';

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
     where region = s.region and id <> s.id and artist <> s.artist
     order by random() limit 2) x;
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

create or replace function public._mc_q(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  q public.questions;
  opts text[];
  song jsonb;
begin
  if random() < 0.3 then
    song := public._song_q(p_room);
    if song is not null then return song; end if;
  end if;
  q := public._pick_q(p_room);
  select array_agg(o order by random()) into opts from unnest(array[q.answer] || q.wrong) o;
  update public.room_secrets set correct_idx = array_position(opts, q.answer) - 1 where room_id = p_room;
  return jsonb_build_object('id', q.id, 'text', q.question, 'cat', q.category, 'options', to_jsonb(opts));
end $$;

revoke execute on function public._song_q(uuid) from public;
do $$ begin
  revoke execute on function public._song_q(uuid) from anon, authenticated;
exception when undefined_object then null;
end $$;
