-- Head-to-head: as soon as one side (player or chaser) locks in an answer,
-- the other side has only 4 more seconds. Run after 20261125000000_init.sql.

create or replace function public._next_h2h_q(p_room uuid, st jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare h jsonb := st->'h2h';
begin
  h := h || jsonb_build_object('n', (h->>'n')::int + 1, 'q', public._mc_q(p_room),
                               'lockP', false, 'lockC', false, 'rush', false, 'reveal', null);
  perform public._save(p_room, 'h2h', now() + interval '20 seconds', st || jsonb_build_object('h2h', h));
end $$;

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
    -- First answer is in: the other side gets 4 seconds (never more than was left).
    st := jsonb_set(st, '{h2h,rush}', 'true'::jsonb);
    perform public._save(p_room, 'h2h', least(r.phase_ends_at, now() + interval '4 seconds'), st);
  end if;
end $$;
