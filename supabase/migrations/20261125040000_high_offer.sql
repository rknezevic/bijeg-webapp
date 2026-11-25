-- Higher offer: one empty step between the chaser and the player (player 2 steps ahead).
-- Own amount (3 steps ahead) and lower offer (4 steps ahead) stay the same.
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
