-- squad comms schema
-- Run in the SquadComms Supabase project SQL editor.

create table if not exists squads (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  join_code   text not null unique check (join_code ~ '^[0-9]{6}$'),
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id) on delete set null
);

create table if not exists squad_members (
  squad_id     uuid not null references squads(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  joined_at    timestamptz not null default now(),
  primary key (squad_id, user_id)
);

create index if not exists squad_members_user_idx on squad_members(user_id);

alter table squads enable row level security;
alter table squad_members enable row level security;

-- Anyone signed in can look a squad up by its code in order to join.
create policy squads_read on squads
  for select to authenticated using (true);

create policy squads_insert on squads
  for insert to authenticated with check (auth.uid() = created_by);

-- You can only see the membership of squads you are actually in.
create policy members_read on squad_members
  for select to authenticated
  using (exists (
    select 1 from squad_members m
    where m.squad_id = squad_members.squad_id and m.user_id = auth.uid()
  ));

create policy members_join on squad_members
  for insert to authenticated with check (auth.uid() = user_id);

create policy members_leave on squad_members
  for delete to authenticated using (auth.uid() = user_id);
