-- Plant Alert — Supabase schema
-- Run this once in your project's SQL Editor (supabase.com -> SQL Editor).
-- Both phones then just need the project URL, the anon key, and a shared
-- household code entered in the app's Settings.

create table if not exists plants (
  id uuid primary key,
  household_id text not null,
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
  household_id text not null,
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

create policy "anon full access" on plants
  for all to anon using (true) with check (true);
create policy "anon full access" on watering_events
  for all to anon using (true) with check (true);

-- Photos live in Storage, not in the table, so the rows stay small enough
-- for the app to pull them all on every sync.
insert into storage.buckets (id, name, public)
  values ('plant-photos', 'plant-photos', false)
  on conflict (id) do nothing;

create policy "anon full access photos" on storage.objects
  for all to anon
  using (bucket_id = 'plant-photos')
  with check (bucket_id = 'plant-photos');
