-- GG Jumps leaderboard: everyone who reached the 100th island, with their run time.
-- Lives in the ggcuts Supabase project (the free plan allows two active projects, both taken),
-- in its own table. Run once in the dashboard SQL Editor. The app uses the publishable key,
-- so row-level security below is what keeps the list safe: anyone may read it and add an
-- entry, nobody (with that key) may change or delete entries.

create table if not exists public.ggjumps_leaderboard (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 10),
  time_ms integer not null check (time_ms > 0),
  finished_at timestamptz not null default now()
);

create index if not exists ggjumps_leaderboard_fastest on public.ggjumps_leaderboard (time_ms, finished_at);

alter table public.ggjumps_leaderboard enable row level security;

drop policy if exists "Anyone can read the leaderboard" on public.ggjumps_leaderboard;
create policy "Anyone can read the leaderboard"
  on public.ggjumps_leaderboard for select
  to anon, authenticated
  using (true);

drop policy if exists "Anyone can add a finished run" on public.ggjumps_leaderboard;
create policy "Anyone can add a finished run"
  on public.ggjumps_leaderboard for insert
  to anon, authenticated
  with check (char_length(btrim(name)) between 1 and 10 and time_ms > 0);

-- No update or delete policies: with RLS on, those are denied for the publishable key.
-- Clients may only send a name and a time; id and finished_at always come from the database.
revoke insert, update, delete on public.ggjumps_leaderboard from anon, authenticated;
grant insert (name, time_ms) on public.ggjumps_leaderboard to anon, authenticated;
grant select on public.ggjumps_leaderboard to anon, authenticated;
