-- squad comms schema (anonymous, code-based app — no user sign-in)
-- Applied live to project cqhugvirbxrxqhhbwklc 2026-08-28.
-- The app connects with the project publishable/anon key, so RLS must permit
-- the anon role. Do NOT restore the old `to authenticated` policies — they made
-- every create/join fail because the app never signs in.

create table if not exists squads (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  join_code  text not null unique check (join_code ~ '^[0-9]{6}$'),
  created_at timestamptz not null default now(),
  created_by uuid
);

create table if not exists squad_members (
  squad_id     uuid not null references squads(id) on delete cascade,
  user_id      uuid not null,
  display_name text not null,
  joined_at    timestamptz not null default now(),
  primary key (squad_id, user_id)
);
create index if not exists squad_members_user_idx on squad_members(user_id);

alter table squads enable row level security;
alter table squad_members enable row level security;

drop policy if exists squads_read on squads;
drop policy if exists squads_insert on squads;
drop policy if exists members_read on squad_members;
drop policy if exists members_join on squad_members;
drop policy if exists members_leave on squad_members;

create policy squads_anon_read   on squads        for select to anon, authenticated using (true);
create policy squads_anon_insert on squads        for insert to anon, authenticated with check (true);
create policy members_anon_all   on squad_members for all    to anon, authenticated using (true) with check (true);
