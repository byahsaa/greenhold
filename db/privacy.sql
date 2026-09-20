-- Greenhold: two privacy changes to the database.
--
-- Neither is applied. Read them, then run them from the Supabase SQL editor
-- (Dashboard > SQL Editor) or hand them back and they can be applied for you.
--
-- Written against the schema as it stands: `profiles` and `matches`, RLS on
-- both, anonymous sign-in, and foreign keys that already cascade correctly
-- (matches.host_id CASCADE, guest_id and winner_id SET NULL, profiles.id
-- CASCADE from auth.users).


-- 1. Let a player delete themselves.
--
-- `profiles` has policies for INSERT, UPDATE and SELECT and none for DELETE.
-- With row level security on, a missing policy is a refusal, so a delete from
-- the client removes nothing and reports no error. There is currently no way
-- for a player to take their name off the server, which is the thing a privacy
-- notice has to be able to promise.
--
-- The cascade does the rest: rooms this player hosted go with the row, and
-- rooms they only joined keep their record with the guest forgotten.

create policy "a player deletes only their own profile"
  on public.profiles
  for delete
  to authenticated
  using (id = auth.uid());


-- 2. Stop signed-in players from reading the whole table.
--
-- The SELECT policy is `using (true)`, so any signed-in player can read every
-- profile row, not just the ten the leaderboard asks for. The leaderboard's
-- LIMIT 10 is a query, not a rule, and anyone can write their own query
-- against the same publishable key.
--
-- What is exposed is a self-chosen nickname and a wave count, so the harm is
-- small, but the table is still readable in full by anyone who signs in, and
-- that is worth closing while it is cheap.
--
-- This replaces the open policy with two narrower ones: your own row, and the
-- rows of people you are actually in a room with. The leaderboard then needs
-- to come from a view or an RPC instead of a direct select, because it is a
-- public ranking rather than a per-player read. `bump_best` already shows the
-- shape: a security definer function that answers one question.
--
-- Left commented out, because it breaks sbBoard() until that view exists.
-- Uncomment both halves together, or neither.

-- drop policy "profiles are readable by signed-in players" on public.profiles;
--
-- create policy "a player reads their own profile"
--   on public.profiles for select to authenticated
--   using (id = auth.uid());
--
-- create policy "a player reads whoever they share a room with"
--   on public.profiles for select to authenticated
--   using (exists (
--     select 1 from public.matches m
--     where (m.host_id = auth.uid() and m.guest_id = profiles.id)
--        or (m.guest_id = auth.uid() and m.host_id = profiles.id)
--   ));
--
-- create or replace function public.leaderboard()
--   returns table (nick text, best_wave int, matches_won int, matches_played int)
--   language sql stable security definer set search_path = public as $$
--     select nick, best_wave, matches_won, matches_played
--     from public.profiles order by best_wave desc limit 10
--   $$;
-- grant execute on function public.leaderboard() to authenticated;


-- Not covered here: the anonymous row in auth.users.
--
-- Deleting the profile takes away the name, the record and the match history,
-- which is everything the game knows about a person. What is left behind is an
-- auth.users row holding a uuid and two timestamps, and no client can delete
-- it: that needs the service role. If those empty rows should go too, it takes
-- a scheduled job or an edge function, and that is a separate decision.
