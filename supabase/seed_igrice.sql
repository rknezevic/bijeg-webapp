-- Video igre: migracija + samo pitanja o igrama (204). Sigurno za ponovno pokretanje.

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


-- Pitanja
insert into public.questions (category, question, answer, aliases, wrong, usage) values
('igrice', 'Kako se zove Nintendov vodoinstalater s crvenom kapom?', 'Mario', array['Super Mario']::text[], array['Luigi', 'Wario']::text[], 'open'),
('igrice', 'Kako se zove Mariov brat u zelenom?', 'Luigi', '{}'::text[], array['Wario', 'Toad']::text[], 'open'),
('igrice', 'Kako se zove princeza koju Mario najčešće spašava?', 'Peach', array['princeza Peach', 'Breskva']::text[], array['Daisy', 'Zelda']::text[], 'open'),
('igrice', 'Kako se zove Mariov glavni neprijatelj, kralj kornjača?', 'Bowser', array['King Koopa', 'Kralj Koopa']::text[], array['Wario', 'Ganon']::text[], 'open'),
('igrice', 'Kako se zove Segin plavi jež?', 'Sonic', array['Sonic the Hedgehog']::text[], array['Knuckles', 'Tails']::text[], 'open'),
('igrice', 'Kako se zove Sonicov prijatelj, lisac s dva repa?', 'Tails', array['Miles Prower']::text[], array['Knuckles', 'Shadow']::text[], 'open'),
('igrice', 'Kako se zove junak serijala The Legend of Zelda?', 'Link', '{}'::text[], array['Zelda', 'Ganondorf']::text[], 'open'),
('igrice', 'Kako se zove žuti lik koji jede točkice i bježi od duhova?', 'Pac-Man', array['Pacman', 'Pac Man']::text[], array['Q*bert', 'Frogger']::text[], 'open'),
('igrice', 'Kako se zove igra s padajućim blokovima koju je izmislio Aleksej Pažitnov?', 'Tetris', '{}'::text[], array['Columns', 'Dr. Mario']::text[], 'open'),
('igrice', 'Kako se zove žuti električni Pokémon, Ashov najbolji prijatelj?', 'Pikachu', array['Pikaču']::text[], array['Raichu', 'Jigglypuff']::text[], 'open'),
('igrice', 'Kako se zove igra s kockastim svijetom, rudarenjem i Creeperima?', 'Minecraft', '{}'::text[], array['Roblox', 'Terraria']::text[], 'open'),
('igrice', 'Kako se zove zeleno čudovište u Minecraftu koje eksplodira?', 'Creeper', '{}'::text[], array['Enderman', 'Zombie']::text[], 'open'),
('igrice', 'Koja je švedska tvrtka napravila Minecraft?', 'Mojang', array['Mojang Studios']::text[], array['Rockstar', 'DICE']::text[], 'open'),
('igrice', 'Koja je tvrtka 2014. kupila Mojang?', 'Microsoft', '{}'::text[], array['Sony', 'Google']::text[], 'open'),
('igrice', 'Kojem serijalu pripadaju igre Vice City i San Andreas?', 'Grand Theft Auto', array['GTA']::text[], array['Saints Row', 'Mafia']::text[], 'open'),
('igrice', 'Koja tvrtka izdaje Grand Theft Auto?', 'Rockstar Games', array['Rockstar']::text[], array['Ubisoft', 'Electronic Arts']::text[], 'open'),
('igrice', 'Kako se zove glavni lik GTA: San Andreas?', 'Carl Johnson', array['CJ', 'C.J.']::text[], array['Tommy Vercetti', 'Niko Bellic']::text[], 'open'),
('igrice', 'Kako se zove glavni lik GTA IV?', 'Niko Bellic', array['Niko']::text[], array['Claude', 'Tommy Vercetti']::text[], 'open'),
('igrice', 'Kako se zove glavni lik GTA: Vice City?', 'Tommy Vercetti', array['Tommy']::text[], array['Carl Johnson', 'Trevor Philips']::text[], 'open'),
('igrice', 'U kojem se izmišljenom gradu odvija GTA V?', 'Los Santos', '{}'::text[], array['Liberty City', 'Vice City']::text[], 'open'),
('igrice', 'Koji je od tri lika u GTA V bivši vojni pilot?', 'Trevor Philips', array['Trevor']::text[], array['Michael De Santa', 'Franklin Clinton']::text[], 'open'),
('igrice', 'Kako se zove Rockstarov kaubojski serijal?', 'Red Dead Redemption', array['RDR']::text[], array['Call of Juarez', 'Gun']::text[], 'open'),
('igrice', 'Kako se zove glavni lik Red Dead Redemption 2?', 'Arthur Morgan', array['Arthur']::text[], array['John Marston', 'Dutch van der Linde']::text[], 'open'),
('igrice', 'Kako se od 2023. zove EA-ov nogometni serijal koji je prije bio FIFA?', 'EA Sports FC', array['EA FC', 'FC']::text[], array['eFootball', 'PES']::text[], 'open'),
('igrice', 'Kako se zvao Konamijev nogometni serijal, konkurent FIFA-i?', 'Pro Evolution Soccer', array['PES', 'eFootball']::text[], array['FIFA', 'Football Manager']::text[], 'open'),
('igrice', 'Kako se zove battle royale igra Epic Gamesa s poznatim plesovima?', 'Fortnite', '{}'::text[], array['PUBG', 'Apex Legends']::text[], 'open'),
('igrice', 'Koja je tvrtka napravila Fortnite?', 'Epic Games', array['Epic']::text[], array['Valve', 'Riot Games']::text[], 'open'),
('igrice', 'Kako se zove Valveov serijal s Gordonom Freemanom?', 'Half-Life', array['Half Life']::text[], array['Portal', 'Doom']::text[], 'open'),
('igrice', 'Kako se zove glavni lik serijala Half-Life?', 'Gordon Freeman', array['Freeman']::text[], array['Alyx Vance', 'G-Man']::text[], 'open'),
('igrice', 'Kako se zove Valveova platforma za kupnju igara na računalu?', 'Steam', '{}'::text[], array['Origin', 'Epic Games Store']::text[], 'open'),
('igrice', 'Kako se zove Riotova MOBA igra s championima?', 'League of Legends', array['LoL']::text[], array['Dota 2', 'Smite']::text[], 'open'),
('igrice', 'Kako se zove Valveova MOBA igra?', 'Dota 2', array['Dota']::text[], array['League of Legends', 'Smite']::text[], 'open'),
('igrice', 'Kako se zove Valveova pucačina teroristi protiv protuterorista?', 'Counter-Strike', array['CS', 'CS:GO', 'CS2']::text[], array['Valorant', 'Rainbow Six']::text[], 'open'),
('igrice', 'Kako se zove Blizzardov MMORPG s Hordom i Alijansom?', 'World of Warcraft', array['WoW', 'Warcraft']::text[], array['EverQuest', 'Guild Wars']::text[], 'open'),
('igrice', 'Kako se zove Blizzardova strategija sa Zergovima i Protossima?', 'StarCraft', '{}'::text[], array['Warcraft', 'Command & Conquer']::text[], 'open'),
('igrice', 'U kojem serijalu glavnu ulogu ima Lara Croft?', 'Tomb Raider', '{}'::text[], array['Uncharted', 'Prince of Persia']::text[], 'open'),
('igrice', 'U kojem serijalu glavnu ulogu ima Nathan Drake?', 'Uncharted', '{}'::text[], array['Tomb Raider', 'The Last of Us']::text[], 'open'),
('igrice', 'Kako se zove djevojka koju Joel prati u The Last of Us?', 'Ellie', '{}'::text[], array['Tess', 'Abby']::text[], 'open'),
('igrice', 'U kojem serijalu glavnu ulogu ima Master Chief?', 'Halo', '{}'::text[], array['Gears of War', 'Destiny']::text[], 'open'),
('igrice', 'U kojem serijalu glavnu ulogu ima Kratos?', 'God of War', '{}'::text[], array['Devil May Cry', 'Dark Souls']::text[], 'open'),
('igrice', 'Kako se zove Kratosov sin u God of War iz 2018.?', 'Atreus', array['Loki']::text[], array['Baldur', 'Mimir']::text[], 'open'),
('igrice', 'U kojem serijalu glavnu ulogu ima Geralt iz Rivije?', 'The Witcher', array['Witcher', 'Vještac']::text[], array['Dragon Age', 'Skyrim']::text[], 'open'),
('igrice', 'Koja je poljska tvrtka napravila The Witcher i Cyberpunk 2077?', 'CD Projekt Red', array['CD Projekt', 'CDPR']::text[], array['Ubisoft', 'Bethesda']::text[], 'open'),
('igrice', 'U kojem se izmišljenom gradu odvija Cyberpunk 2077?', 'Night City', '{}'::text[], array['Neo Tokyo', 'Rapture']::text[], 'open'),
('igrice', 'Kojeg je lika u Cyberpunku 2077 glumio Keanu Reeves?', 'Johnny Silverhand', array['Silverhand']::text[], array['Jackie Welles', 'Adam Smasher']::text[], 'open'),
('igrice', 'Kako se zove peti dio serijala The Elder Scrolls iz 2011.?', 'Skyrim', array['The Elder Scrolls V: Skyrim']::text[], array['Oblivion', 'Morrowind']::text[], 'open'),
('igrice', 'Kako se zove Bethesdin postapokaliptični serijal s Vault Boyem?', 'Fallout', '{}'::text[], array['Wasteland', 'Metro']::text[], 'open'),
('igrice', 'Kako se zove podvodni grad u BioShocku?', 'Rapture', '{}'::text[], array['Columbia', 'City 17']::text[], 'open'),
('igrice', 'Kako se zove Ubisoftov serijal o asasinima?', 'Assassin''s Creed', array['AC']::text[], array['Prince of Persia', 'Hitman']::text[], 'open'),
('igrice', 'Kako se zove glavni lik Assassin''s Creed II?', 'Ezio Auditore', array['Ezio']::text[], array['Altaïr', 'Connor']::text[], 'open'),
('igrice', 'Kako se zove ćelavi plaćeni ubojica s bar kodom na zatiljku?', 'Agent 47', array['47']::text[], array['Sam Fisher', 'Solid Snake']::text[], 'open'),
('igrice', 'Kako se zove glavni junak serijala Metal Gear Solid?', 'Solid Snake', array['Snake']::text[], array['Sam Fisher', 'Agent 47']::text[], 'open'),
('igrice', 'Koji je Japanac tvorac serijala Metal Gear?', 'Hideo Kojima', array['Kojima']::text[], array['Shigeru Miyamoto', 'Satoru Iwata']::text[], 'open'),
('igrice', 'Koji je Japanac tvorac Maria i Zelde?', 'Shigeru Miyamoto', array['Miyamoto']::text[], array['Hideo Kojima', 'Satoru Iwata']::text[], 'open'),
('igrice', 'Kako se zove glavni lik Final Fantasy VII s ogromnim mačem?', 'Cloud Strife', array['Cloud']::text[], array['Sephiroth', 'Squall']::text[], 'open'),
('igrice', 'Kako se zove negativac Final Fantasy VII s dugom srebrnom kosom?', 'Sephiroth', '{}'::text[], array['Kefka', 'Cloud']::text[], 'open'),
('igrice', 'Kako se zove glavni lik Street Fightera u bijelom kimonu?', 'Ryu', '{}'::text[], array['Ken', 'Chun-Li']::text[], 'open'),
('igrice', 'Kako se zove završni potez kojim se ubija protivnik u Mortal Kombatu?', 'Fatality', '{}'::text[], array['Combo Breaker', 'K.O.']::text[], 'open'),
('igrice', 'Kako se zove ninja u žutom iz Mortal Kombata s kopljem na užetu?', 'Scorpion', '{}'::text[], array['Sub-Zero', 'Reptile']::text[], 'open'),
('igrice', 'Kako se zove ledeni ninja iz Mortal Kombata?', 'Sub-Zero', array['Subzero', 'Sub Zero']::text[], array['Scorpion', 'Raiden']::text[], 'open'),
('igrice', 'Koga ptice napadaju u igri Angry Birds?', 'svinje', array['svinje', 'prasce', 'svinjice']::text[], array['mačke', 'vukove']::text[], 'open'),
('igrice', 'Koja je finska tvrtka napravila Angry Birds?', 'Rovio', '{}'::text[], array['Supercell', 'Remedy']::text[], 'open'),
('igrice', 'Koja je finska tvrtka napravila Clash of Clans?', 'Supercell', '{}'::text[], array['Rovio', 'King']::text[], 'open'),
('igrice', 'Koja je tvrtka napravila Candy Crush Saga?', 'King', '{}'::text[], array['Supercell', 'Zynga']::text[], 'open'),
('igrice', 'Kako se zove izdajica u igri Among Us?', 'Impostor', array['Imposter']::text[], array['Crewmate', 'Traitor']::text[], 'open'),
('igrice', 'Kako se zove battle royale u kojem se kao oružje koristi i tava?', 'PUBG', array['PlayerUnknown''s Battlegrounds']::text[], array['Fortnite', 'H1Z1']::text[], 'open'),
('igrice', 'Kako se zove horor igra s animatroničkim medvjedom Freddyjem?', 'Five Nights at Freddy''s', array['FNAF', 'Five Nights at Freddys']::text[], array['Poppy Playtime', 'Bendy and the Ink Machine']::text[], 'open'),
('igrice', 'Kako se zove Nintendova hibridna konzola iz 2017.?', 'Nintendo Switch', array['Switch']::text[], array['Wii U', 'GameCube']::text[], 'open'),
('igrice', 'Kako se zove Nintendova konzola iz 2006. s kontrolerom na pokret?', 'Wii', array['Nintendo Wii']::text[], array['Wii U', 'GameCube']::text[], 'open'),
('igrice', 'Koja je tvrtka proizvela Game Boy?', 'Nintendo', '{}'::text[], array['Sega', 'Sony']::text[], 'open'),
('igrice', 'Kako se zove Microsoftova igraća konzola?', 'Xbox', '{}'::text[], array['PlayStation', 'Dreamcast']::text[], 'open'),
('igrice', 'Kako se zvala posljednja Segina igraća konzola?', 'Dreamcast', '{}'::text[], array['Saturn', 'Mega Drive']::text[], 'open'),
('igrice', 'Koja je tvrtka 1972. izdala igru Pong?', 'Atari', '{}'::text[], array['Magnavox', 'Nintendo']::text[], 'open'),
('igrice', 'Iz koje zemlje dolazi igra Space Invaders?', 'Japan', '{}'::text[], array['SAD', 'Velika Britanija']::text[], 'open'),
('igrice', 'Koja je životinja Donkey Kong?', 'gorila', array['majmun']::text[], array['orangutan', 'čimpanza']::text[], 'open'),
('igrice', 'Iz kojeg se Pokémona izravno razvija Charizard?', 'Charmeleon', '{}'::text[], array['Charmander', 'Dragonite']::text[], 'open'),
('igrice', 'Koliko je Pokémona bilo u prvoj generaciji?', '151', '{}'::text[], array['150', '251']::text[], 'open'),
('igrice', 'Koja je životinja Crash Bandicoot?', 'bandikut', array['tobolčar']::text[], array['lisica', 'rakun']::text[], 'open'),
('igrice', 'Koja je životinja Spyro?', 'zmaj', '{}'::text[], array['dinosaur', 'gušter']::text[], 'open'),
('igrice', 'Kako se zove Nintendov ružičasti lik koji usisava neprijatelje?', 'Kirby', '{}'::text[], array['Jigglypuff', 'Yoshi']::text[], 'open'),
('igrice', 'Koja je životinja Yoshi?', 'dinosaur', array['dinosaurus']::text[], array['zmaj', 'gušter']::text[], 'open'),
('igrice', 'Kako se zove Activisionov ratni serijal s načinom igre Zombies?', 'Call of Duty', array['CoD']::text[], array['Battlefield', 'Medal of Honor']::text[], 'open'),
('igrice', 'Kako se zove EA-ov ratni serijal, veliki konkurent Call of Dutyju?', 'Battlefield', '{}'::text[], array['Medal of Honor', 'Call of Duty']::text[], 'open'),
('igrice', 'Kako se zove simulator života u kojem likovi imaju zeleni dijamant iznad glave?', 'The Sims', array['Sims']::text[], array['SimCity', 'Second Life']::text[], 'open'),
('igrice', 'Kako se zove Maxisova igra izgradnje grada?', 'SimCity', array['Sim City']::text[], array['Cities: Skylines', 'Anno']::text[], 'open'),
('igrice', 'U igri Rocket League igra se nogomet s čime?', 'automobilima', array['auti', 'autima', 'automobili']::text[], array['dronovima', 'konjima']::text[], 'open'),
('igrice', 'Koja je tvrtka napravila Overwatch?', 'Blizzard', array['Blizzard Entertainment']::text[], array['Valve', 'Riot Games']::text[], 'open'),
('igrice', 'Koja je tvrtka napravila Valorant?', 'Riot Games', array['Riot']::text[], array['Valve', 'Blizzard']::text[], 'open'),
('igrice', 'Koji je japanski studio napravio Elden Ring i Dark Souls?', 'FromSoftware', array['From Software']::text[], array['Capcom', 'Konami']::text[], 'open'),
('igrice', 'Koja je japanska tvrtka napravila Resident Evil?', 'Capcom', '{}'::text[], array['Konami', 'Square Enix']::text[], 'open'),
('igrice', 'Koja je japanska tvrtka napravila Silent Hill?', 'Konami', '{}'::text[], array['Capcom', 'Sega']::text[], 'open'),
('igrice', 'Kako se zove pucačina id Softwarea iz 1993. o borbi protiv demona?', 'Doom', '{}'::text[], array['Quake', 'Wolfenstein']::text[], 'open'),
('igrice', 'Koja je najprodavanija videoigra svih vremena?', 'Minecraft', '{}'::text[], array['Tetris', 'GTA V']::text[], 'open'),
('igrice', 'Kako se zove umjetna inteligencija koja vodi testove u Portalu?', 'GLaDOS', array['Glados']::text[], array['Wheatley', 'SHODAN']::text[], 'open'),
('igrice', 'Kako se zove tiha junakinja Portala?', 'Chell', '{}'::text[], array['Alyx', 'Samus']::text[], 'open'),
('igrice', 'Kako se zove Nintendova igra iz 1985. koja je proslavila Maria?', 'Super Mario Bros.', array['Super Mario Bros', 'Super Mario Brothers']::text[], array['Super Mario World', 'Super Mario 64']::text[], 'open'),
('igrice', 'Što Mario pojede da naraste?', 'gljivu', array['gljiva', 'Super Mushroom']::text[], array['cvijet', 'zvijezdu']::text[], 'open'),
('igrice', 'Na kojoj je konzoli izašao Super Mario 64?', 'Nintendo 64', array['N64']::text[], array['GameCube', 'SNES']::text[], 'open'),
('igrice', 'Kako se zvala Sonyjeva prijenosna konzola iz 2004.?', 'PSP', array['PlayStation Portable']::text[], array['PS Vita', 'Game Boy Advance']::text[], 'open'),
('igrice', 'Koja tvrtka proizvodi PlayStation?', 'Sony', '{}'::text[], array['Microsoft', 'Nintendo']::text[], 'open'),
('igrice', 'Koji studio razvija Football Manager?', 'Sports Interactive', array['SI']::text[], array['EA Sports', 'Konami']::text[], 'open'),
('igrice', 'Kako se zove konj u The Legend of Zelda?', 'Epona', '{}'::text[], array['Roach', 'Agro']::text[], 'open'),
('igrice', 'Kako se zove Ashov učitelj, profesor koji daje prvog Pokémona?', 'Profesor Oak', array['Oak', 'Samuel Oak']::text[], array['Elm', 'Birch']::text[], 'open'),
('igrice', 'Kako se zvala Segina maskota prije Sonica?', 'Alex Kidd', '{}'::text[], array['Opa-Opa', 'Tails']::text[], 'board'),
('igrice', 'Koja tvrtka izdaje serijal Call of Duty?', 'Activision', '{}'::text[], array['Electronic Arts', 'Ubisoft']::text[], 'board'),
('igrice', 'Kako se zove grad u kojem se odvija Half-Life 2?', 'City 17', '{}'::text[], array['Raccoon City', 'Rapture']::text[], 'board'),
('igrice', 'U kojem se gradu odvija Resident Evil 2?', 'Raccoon City', '{}'::text[], array['Silent Hill', 'City 17']::text[], 'board'),
('igrice', 'Kako se zove kraljevstvo u serijalu The Legend of Zelda?', 'Hyrule', '{}'::text[], array['Termina', 'Koholint']::text[], 'board'),
('igrice', 'Kako se zove Linkov glavni neprijatelj?', 'Ganon', array['Ganondorf']::text[], array['Bowser', 'Vaati']::text[], 'board'),
('igrice', 'Kako se zove Sonicov zli doktor?', 'Dr. Eggman', array['Eggman', 'Robotnik', 'Dr. Robotnik']::text[], array['Dr. Wily', 'Dr. Neo Cortex']::text[], 'board'),
('igrice', 'Čiji je neprijatelj Dr. Wily?', 'Mega Man', array['Megaman']::text[], array['Sonic', 'Crash Bandicoot']::text[], 'board'),
('igrice', 'Čiji je neprijatelj Dr. Neo Cortex?', 'Crash Bandicoot', array['Crash']::text[], array['Spyro', 'Sonic']::text[], 'board'),
('igrice', 'Koji je studio napravio prve igre Crash Bandicoot?', 'Naughty Dog', '{}'::text[], array['Insomniac Games', 'Sucker Punch']::text[], 'board'),
('igrice', 'Koji je studio napravio prve igre Spyro?', 'Insomniac Games', array['Insomniac']::text[], array['Naughty Dog', 'Rare']::text[], 'board'),
('igrice', 'Koji je studio napravio The Last of Us?', 'Naughty Dog', '{}'::text[], array['Insomniac Games', 'Guerrilla Games']::text[], 'board'),
('igrice', 'Koje je godine izašao GTA V?', '2013', '{}'::text[], array['2011', '2015']::text[], 'board'),
('igrice', 'Koje je godine izašla puna verzija Minecrafta?', '2011', '{}'::text[], array['2009', '2013']::text[], 'board'),
('igrice', 'Koje je godine izašao Fortnite Battle Royale?', '2017', '{}'::text[], array['2015', '2019']::text[], 'board'),
('igrice', 'Koje je godine izašao prvi Super Mario Bros.?', '1985', '{}'::text[], array['1983', '1990']::text[], 'board'),
('igrice', 'Koje su godine u Japanu izašle prve Pokémon igre?', '1996', '{}'::text[], array['1998', '1993']::text[], 'board'),
('igrice', 'Koje je godine izašao Pong?', '1972', '{}'::text[], array['1968', '1980']::text[], 'board'),
('igrice', 'Koje je godine izašao PlayStation 5?', '2020', '{}'::text[], array['2019', '2021']::text[], 'board'),
('igrice', 'Koje je godine izašao Nintendo Switch?', '2017', '{}'::text[], array['2016', '2018']::text[], 'board'),
('igrice', 'Koje je godine izašao prvi Xbox?', '2001', '{}'::text[], array['1999', '2003']::text[], 'board'),
('igrice', 'Kako se zove glavni lik serijala Doom?', 'Doomguy', array['Doom Slayer', 'Doom guy']::text[], array['Master Chief', 'B.J. Blazkowicz']::text[], 'board'),
('igrice', 'U kojem je serijalu glavni junak B.J. Blazkowicz?', 'Wolfenstein', '{}'::text[], array['Doom', 'Quake']::text[], 'board'),
('igrice', 'Koji se dio Fallouta iz 2008. odvija oko Washingtona?', 'Fallout 3', '{}'::text[], array['Fallout: New Vegas', 'Fallout 4']::text[], 'board'),
('igrice', 'U kojem se gradu odvija Fallout: New Vegas?', 'Las Vegas', array['New Vegas']::text[], array['Los Angeles', 'Reno']::text[], 'board'),
('igrice', 'Koja vila u Ocarini of Time stalno viče „Hey! Listen!”?', 'Navi', '{}'::text[], array['Midna', 'Fi']::text[], 'board'),
('igrice', 'Iz koje je igre rečenica „The cake is a lie”?', 'Portal', '{}'::text[], array['Half-Life 2', 'BioShock']::text[], 'board'),
('igrice', 'Iz koje je igre fraza „Would you kindly”?', 'BioShock', array['Bioshock']::text[], array['Fallout 3', 'Dishonored']::text[], 'board'),
('igrice', 'Koji serijal počinje rečenicom „War. War never changes.”?', 'Fallout', '{}'::text[], array['Call of Duty', 'Battlefield']::text[], 'board'),
('igrice', 'Iz koje je igre rečenica „It''s dangerous to go alone! Take this.”?', 'The Legend of Zelda', array['Zelda']::text[], array['Final Fantasy', 'Metroid']::text[], 'board'),
('igrice', 'U kojoj igri spiker viče „Finish him!”?', 'Mortal Kombat', '{}'::text[], array['Street Fighter', 'Tekken']::text[], 'board'),
('igrice', 'U kojoj igri lik izvodi udarac „Hadouken”?', 'Street Fighter', '{}'::text[], array['Mortal Kombat', 'Tekken']::text[], 'board'),
('igrice', 'U kojem je serijalu junakinja Samus Aran?', 'Metroid', '{}'::text[], array['The Legend of Zelda', 'Kid Icarus']::text[], 'board'),
('igrice', 'U kojem je serijalu glavni lik Marcus Fenix?', 'Gears of War', '{}'::text[], array['Halo', 'Mass Effect']::text[], 'board'),
('igrice', 'U kojem je serijalu glavni lik Commander Shepard?', 'Mass Effect', '{}'::text[], array['Halo', 'Star Wars: KOTOR']::text[], 'board'),
('igrice', 'U kojoj je igri glavna junakinja lovkinja Aloy?', 'Horizon Zero Dawn', array['Horizon']::text[], array['Tomb Raider', 'Far Cry Primal']::text[], 'board'),
('igrice', 'Iz koje je mitologije Kratos prije nego što je otišao na sjever?', 'grčke', array['grčka', 'grčka mitologija']::text[], array['egipatske', 'rimske']::text[], 'board'),
('igrice', 'Koliko mačeva nosi Geralt iz Rivije?', '2', array['dva']::text[], array['1', '3']::text[], 'board'),
('igrice', 'Kako se zove Geraltov konj?', 'Roach', array['Plotka']::text[], array['Agro', 'Epona']::text[], 'board'),
('igrice', 'Kakva je životinja Bowser?', 'kornjača', array['koopa']::text[], array['zmaj', 'krokodil']::text[], 'board'),
('igrice', 'Koje je zanimanje Mario?', 'vodoinstalater', '{}'::text[], array['stolar', 'električar']::text[], 'board'),
('igrice', 'U kojoj se igri Mario prvi put pojavio?', 'Donkey Kong', '{}'::text[], array['Mario Bros.', 'Super Mario Bros.']::text[], 'board'),
('igrice', 'Pod kojim se imenom Mario pojavio u prvom Donkey Kongu?', 'Jumpman', '{}'::text[], array['Plumberman', 'Mario Jr.']::text[], 'board'),
('igrice', 'Iz koje je zemlje tvrtka Ubisoft?', 'Francuska', '{}'::text[], array['Kanada', 'Belgija']::text[], 'board'),
('igrice', 'Iz koje je zemlje tvrtka CD Projekt?', 'Poljska', '{}'::text[], array['Češka', 'Ukrajina']::text[], 'board'),
('igrice', 'Iz koje je zemlje Mojang?', 'Švedska', '{}'::text[], array['Norveška', 'Finska']::text[], 'board'),
('igrice', 'Iz koje su zemlje tvrtke Rovio i Supercell?', 'Finska', '{}'::text[], array['Švedska', 'Danska']::text[], 'board'),
('igrice', 'U kojem je gradu sjedište Nintenda?', 'Kyoto', array['Kjoto']::text[], array['Tokio', 'Osaka']::text[], 'board'),
('igrice', 'Koji je hrvatski studio napravio Serious Sam?', 'Croteam', '{}'::text[], array['Nanobit', 'Gamepires']::text[], 'board'),
('igrice', 'Koji hrvatski studio radi mobilne igre poput My Story?', 'Nanobit', '{}'::text[], array['Croteam', 'Pine Studio']::text[], 'board'),
('igrice', 'Kako se zove glavni lik serijala Serious Sam?', 'Sam Stone', array['Serious Sam', 'Sam „Serious” Stone']::text[], array['Sam Fisher', 'Duke Nukem']::text[], 'board'),
('igrice', 'Koju je filozofsku puzzle igru Croteam objavio 2014.?', 'The Talos Principle', array['Talos Principle']::text[], array['The Witness', 'Portal 2']::text[], 'board'),
('igrice', 'Koliko igrača započinje meč u klasičnom Fortnite Battle Royaleu?', '100', array['sto']::text[], array['64', '150']::text[], 'board'),
('igrice', 'Koliko igrača ima jedna ekipa u Counter-Strikeu?', '5', array['pet']::text[], array['6', '4']::text[], 'board'),
('igrice', 'Koliko igrača ima jedna ekipa u League of Legends?', '5', array['pet']::text[], array['6', '3']::text[], 'board'),
('igrice', 'Kako se zove najveće natjecanje u League of Legends?', 'Worlds', array['Svjetsko prvenstvo', 'World Championship']::text[], array['The International', 'Major']::text[], 'board'),
('igrice', 'Kako se zove najveći turnir u Dota 2?', 'The International', array['TI']::text[], array['Worlds', 'Major']::text[], 'board'),
('igrice', 'Koja je Pokémon igra s proširenom stvarnošću postala hit 2016.?', 'Pokémon Go', array['Pokemon Go']::text[], array['Pokémon Sleep', 'Pokémon Unite']::text[], 'board'),
('igrice', 'Koji je vodeni početni Pokémon prve generacije?', 'Squirtle', '{}'::text[], array['Totodile', 'Psyduck']::text[], 'board'),
('igrice', 'Koji je travnati početni Pokémon prve generacije?', 'Bulbasaur', '{}'::text[], array['Chikorita', 'Oddish']::text[], 'board'),
('igrice', 'Koji je legendarni Pokémon prve generacije genetski klon?', 'Mewtwo', '{}'::text[], array['Mew', 'Lugia']::text[], 'board'),
('igrice', 'U kojoj je državi nastao Tetris?', 'Sovjetski Savez', array['SSSR', 'Rusija']::text[], array['SAD', 'Japan']::text[], 'board'),
('igrice', 'Iz koje je zemlje tvrtka koja je napravila PUBG?', 'Južna Koreja', array['Koreja']::text[], array['Kina', 'Japan']::text[], 'board'),
('igrice', 'Iz koje je zemlje tvrtka koja je napravila Genshin Impact?', 'Kina', '{}'::text[], array['Japan', 'Južna Koreja']::text[], 'board'),
('igrice', 'Na kojoj je konzoli 2001. izašao Halo: Combat Evolved?', 'Xbox', '{}'::text[], array['PlayStation 2', 'GameCube']::text[], 'board'),
('igrice', 'Koje je godine izašao Elden Ring?', '2022', '{}'::text[], array['2020', '2021']::text[], 'board'),
('igrice', 'Koje je godine izašao The Witcher 3: Wild Hunt?', '2015', '{}'::text[], array['2013', '2017']::text[], 'board'),
('igrice', 'Koje je godine izašao Red Dead Redemption 2?', '2018', '{}'::text[], array['2016', '2019']::text[], 'board'),
('igrice', 'Koje je godine izašao Skyrim?', '2011', '{}'::text[], array['2009', '2013']::text[], 'board'),
('igrice', 'Koje je godine izašao Cyberpunk 2077?', '2020', '{}'::text[], array['2019', '2021']::text[], 'board'),
('igrice', 'Koje je godine izašao Half-Life 2?', '2004', '{}'::text[], array['2002', '2006']::text[], 'board'),
('igrice', 'Koje je godine izašao World of Warcraft?', '2004', '{}'::text[], array['2001', '2007']::text[], 'board'),
('igrice', 'Koje je godine izašao The Last of Us?', '2013', '{}'::text[], array['2011', '2015']::text[], 'board'),
('igrice', 'Koji je studio napravio Baldur''s Gate 3?', 'Larian Studios', array['Larian']::text[], array['BioWare', 'Obsidian']::text[], 'board'),
('igrice', 'Koje je godine izašao The Legend of Zelda: Breath of the Wild?', '2017', '{}'::text[], array['2015', '2019']::text[], 'board'),
('igrice', 'Koji glumac igra glavnu ulogu u igri Death Stranding?', 'Norman Reedus', array['Reedus']::text[], array['Keanu Reeves', 'Kevin Spacey']::text[], 'board'),
('igrice', 'U kojoj je igri glumio Keanu Reeves?', 'Cyberpunk 2077', array['Cyberpunk']::text[], array['Death Stranding', 'Call of Duty: Advanced Warfare']::text[], 'board'),
('igrice', 'U kojoj je igri glumio Kevin Spacey?', 'Call of Duty: Advanced Warfare', array['Advanced Warfare']::text[], array['Cyberpunk 2077', 'Detroit: Become Human']::text[], 'board'),
('igrice', 'Kako se zove umjetna inteligencija koja prati Master Chiefa?', 'Cortana', '{}'::text[], array['GLaDOS', 'EDI']::text[], 'board'),
('igrice', 'Što u igrama znači kratica NPC?', 'lik kojim ne upravlja igrač', array['non-player character', 'neigrivi lik']::text[], array['sporedna misija', 'nadogradnja oružja']::text[], 'board'),
('igrice', 'Što znači kratica RPG?', 'igra igranja uloga', array['role-playing game', 'role playing game']::text[], array['brza pucačina', 'strategija u stvarnom vremenu']::text[], 'board'),
('igrice', 'Kako se zove žanr u kojem pobjeđuje posljednji preživjeli od mnogo igrača?', 'battle royale', '{}'::text[], array['MOBA', 'roguelike']::text[], 'board'),
('igrice', 'Kako se zove prelaženje igre što je brže moguće?', 'speedrun', array['speedrunning']::text[], array['grind', 'respawn']::text[], 'board'),
('igrice', 'Kako se u SAD-u zvala Segina konzola Mega Drive?', 'Genesis', array['Sega Genesis']::text[], array['Saturn', 'Master System']::text[], 'board'),
('igrice', 'Kako se zove Nintendova konzola iz 2001. s ručkom za nošenje?', 'GameCube', '{}'::text[], array['Nintendo 64', 'Wii']::text[], 'board'),
('igrice', 'Kako se zove Nintendova kućna konzola iz 1985. (kratica)?', 'NES', array['Nintendo Entertainment System']::text[], array['SNES', 'N64']::text[], 'board'),
('igrice', 'Kako se zove Sonyjeva prijenosna konzola iz 2011.?', 'PS Vita', array['PlayStation Vita', 'Vita']::text[], array['PSP', 'Nintendo 3DS']::text[], 'board'),
('igrice', 'Kako se zove Sonicov crveni rival i prijatelj, ehidna?', 'Knuckles', '{}'::text[], array['Shadow', 'Tails']::text[], 'board'),
('igrice', 'Kako se zove Mariov zli dvojnik u žutom?', 'Wario', '{}'::text[], array['Waluigi', 'Bowser Jr.']::text[], 'board'),
('igrice', 'Kako se zove Luigijev zli dvojnik u ljubičastom?', 'Waluigi', '{}'::text[], array['Wario', 'King Boo']::text[], 'board'),
('igrice', 'Kako se zove trkaća igra s Mariom i likovima iz Nintenda?', 'Mario Kart', '{}'::text[], array['Crash Team Racing', 'Sonic Racing']::text[], 'board'),
('igrice', 'Kako se zove borbena igra s Mariom, Linkom, Pikachuom i drugima?', 'Super Smash Bros.', array['Smash Bros', 'Smash']::text[], array['Tekken', 'Brawlhalla']::text[], 'board'),
('igrice', 'Kako se zove borbena igra s Kazuyom Mishimom?', 'Tekken', '{}'::text[], array['Soulcalibur', 'Virtua Fighter']::text[], 'board'),
('igrice', 'Kako se zove FIFA-in način igre u kojem skupljate karte igrača?', 'Ultimate Team', array['FUT', 'FIFA Ultimate Team']::text[], array['Career Mode', 'Pro Clubs']::text[], 'board'),
('igrice', 'Kako se zove legendarna puzzle igra u kojoj se povezuju tri bombona iste boje?', 'Candy Crush Saga', array['Candy Crush']::text[], array['Bejeweled', 'Zuma']::text[], 'board'),
('igrice', 'Kako se zove igra s lemmingsima koji slijepo hodaju?', 'Lemmings', '{}'::text[], array['Worms', 'Pikmin']::text[], 'board'),
('igrice', 'Kako se zove strateška igra s crvima koji ratuju bazukama i ovcama?', 'Worms', '{}'::text[], array['Lemmings', 'Scorched Earth']::text[], 'board'),
('igrice', 'Kako se zove serijal strategija u kojem se kaže „Just one more turn”?', 'Civilization', array['Civ', 'Sid Meier''s Civilization']::text[], array['Age of Empires', 'Total War']::text[], 'board'),
('igrice', 'Kako se zove strategija u stvarnom vremenu s Bizantom, Francima i Mongolima?', 'Age of Empires II', array['Age of Empires', 'AoE']::text[], array['Civilization', 'Stronghold']::text[], 'board'),
('igrice', 'Kako se zove igra u kojoj kao guska radiš nepodopštine po selu?', 'Untitled Goose Game', array['Goose Game']::text[], array['Goat Simulator', 'Duck Game']::text[], 'board'),
('igrice', 'Kako se zove indie igra u kojoj kao vitez buba istražuješ Hallownest?', 'Hollow Knight', '{}'::text[], array['Ori', 'Celeste']::text[], 'board')
on conflict (question) do update set category = excluded.category, answer = excluded.answer,
  aliases = excluded.aliases, wrong = excluded.wrong, usage = excluded.usage;

select category, usage, count(*) from public.questions where category = 'igrice' group by 1, 2;
