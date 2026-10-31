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

-- Reports of offensive names (App Store guideline 1.2). Players can only add a report (which
-- entry, nothing else); nobody can read reports with the publishable key. Review them in the
-- dashboard (Table Editor -> ggjumps_leaderboard_reports) and delete entries that break the rules.
-- An entry with REPORTS_TO_HIDE (3) reports is hidden from everyone right away; to bring it back,
-- set hidden = false and delete its reports.
alter table public.ggjumps_leaderboard add column if not exists hidden boolean not null default false;

create table if not exists public.ggjumps_leaderboard_reports (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.ggjumps_leaderboard (id) on delete cascade,
  reported_at timestamptz not null default now()
);

create index if not exists ggjumps_leaderboard_reports_entry on public.ggjumps_leaderboard_reports (entry_id);

alter table public.ggjumps_leaderboard_reports enable row level security;

drop policy if exists "Anyone can report an entry" on public.ggjumps_leaderboard_reports;
create policy "Anyone can report an entry"
  on public.ggjumps_leaderboard_reports for insert
  to anon, authenticated
  with check (true);

revoke all on public.ggjumps_leaderboard_reports from anon, authenticated;
grant insert (entry_id) on public.ggjumps_leaderboard_reports to anon, authenticated;

create or replace function public.ggjumps_hide_reported() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.ggjumps_leaderboard_reports where entry_id = new.entry_id) >= 3 then
    update public.ggjumps_leaderboard set hidden = true where id = new.entry_id;
  end if;
  return new;
end;
$$;

drop trigger if exists ggjumps_hide_reported on public.ggjumps_leaderboard_reports;
create trigger ggjumps_hide_reported after insert on public.ggjumps_leaderboard_reports
  for each row execute function public.ggjumps_hide_reported();

-- Hidden entries are left out of the list.
drop policy if exists "Anyone can read the leaderboard" on public.ggjumps_leaderboard;
create policy "Anyone can read the leaderboard"
  on public.ggjumps_leaderboard for select
  to anon, authenticated
  using (not hidden);
