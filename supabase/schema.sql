-- Plant Alert — Supabase schema
--
-- Before running: Authentication -> Sign In / Providers -> enable
-- "Allow anonymous sign-ins". Then run this whole file in the SQL Editor.
-- It is safe to run again.
--
-- Every phone signs in as its own anonymous user and joins a household with a
-- shared code through join_household(). The row and photo policies admit a
-- user only to the households they have joined, so the anon key on its own
-- can read nothing.
--
-- Upgrading from the first version (text household_id, "anon full access"
-- policies): drop the old tables first and empty the plant-photos bucket —
--   drop table if exists plants, watering_events;
-- Nothing is lost: each phone re-uploads everything it has when it joins.

-- Households --------------------------------------------------------------

create table if not exists households (
  id uuid primary key default gen_random_uuid(),
  -- sha256 of the join code; the code itself is never stored.
  code_hash text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists household_members (
  household_id uuid not null references households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create index if not exists household_members_user_idx
  on household_members (user_id);

-- No policies: both tables are reached only through the functions below.
alter table households enable row level security;
alter table household_members enable row level security;

-- The households the calling user belongs to. Security definer so policies
-- can use it without needing read access to household_members themselves.
create or replace function public.my_household_ids()
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select household_id from household_members where user_id = auth.uid()
$$;

-- Joins the household for `code`, creating it if this is the first phone to
-- use the code. Returns the household id.
create or replace function public.join_household(code text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  hash text := encode(sha256(convert_to(code, 'UTF8')), 'hex');
  hid uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in before joining a household';
  end if;
  -- The code is the only thing standing between a stranger and the plants.
  if length(code) < 12 then
    raise exception 'The household code must be at least 12 characters';
  end if;

  insert into households (code_hash) values (hash)
    on conflict (code_hash) do nothing;
  select id into hid from households where code_hash = hash;

  insert into household_members (household_id, user_id) values (hid, auth.uid())
    on conflict do nothing;
  return hid;
end
$$;

revoke execute on function public.my_household_ids() from public, anon;
revoke execute on function public.join_household(text) from public, anon;
grant execute on function public.my_household_ids() to authenticated;
grant execute on function public.join_household(text) to authenticated;

-- Plants and history -------------------------------------------------------

create table if not exists plants (
  id uuid primary key,
  household_id uuid not null references households (id) on delete cascade,
  name text not null default '',
  species text not null default '',
  room text not null default '',
  notes text not null default '',
  symbol_name text not null default 'leaf.fill',
  color_name text not null default 'green',
  interval_days int not null default 7,
  amount_ml int not null default 250,
  last_watered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_removed boolean not null default false,
  image_path text
);

create table if not exists watering_events (
  id uuid primary key,
  household_id uuid not null references households (id) on delete cascade,
  plant_id uuid not null,
  watered_at timestamptz not null default now(),
  amount_ml int not null default 0,
  person_name text not null default '',
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_removed boolean not null default false
);

create index if not exists plants_household_idx
  on plants (household_id);
create index if not exists watering_events_household_idx
  on watering_events (household_id);

alter table plants enable row level security;
alter table watering_events enable row level security;

drop policy if exists "anon full access" on plants;
drop policy if exists "household members" on plants;
create policy "household members" on plants
  for all to authenticated
  using (household_id in (select public.my_household_ids()))
  with check (household_id in (select public.my_household_ids()));

drop policy if exists "anon full access" on watering_events;
drop policy if exists "household members" on watering_events;
create policy "household members" on watering_events
  for all to authenticated
  using (household_id in (select public.my_household_ids()))
  with check (household_id in (select public.my_household_ids()));

-- Photos -------------------------------------------------------------------

-- Photos live in Storage, not in the table, so the rows stay small enough for
-- the app to pull them all on every sync. Each object sits under a folder
-- named after its household id, which is what the policy checks.
insert into storage.buckets (id, name, public)
  values ('plant-photos', 'plant-photos', false)
  on conflict (id) do nothing;

drop policy if exists "anon full access photos" on storage.objects;
drop policy if exists "household members photos" on storage.objects;
create policy "household members photos" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] in (select hid::text from public.my_household_ids() as t(hid))
  )
  with check (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] in (select hid::text from public.my_household_ids() as t(hid))
  );

-- Retention ----------------------------------------------------------------

-- Nightly: drop watering history and deleted-plant tombstones older than 90
-- days, so the app's full-table pull stays small. A tombstone only has to
-- outlive the other phone's next sync. Re-scheduling by name replaces the job.
create extension if not exists pg_cron;

select cron.schedule(
  'plant-alert-retention',
  '0 3 * * *',
  $$
    delete from public.watering_events where watered_at < now() - interval '90 days';
    delete from public.plants where is_removed and updated_at < now() - interval '90 days';
  $$
);
