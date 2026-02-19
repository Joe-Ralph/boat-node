-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- 1. Villages Table
create table public.villages (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  district text not null,
  created_at timestamptz default now()
);

-- 2. Boats Table
create table public.boats (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  registration_number text,
  owner_id uuid references auth.users(id),
  village_id uuid references public.villages(id),
  device_id text, -- LoRa Device ID
  created_at timestamptz default now()
);

-- 3. Profiles Table (Extends Auth.Users)
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  email text,
  display_name text,
  role text check (role in ('owner', 'crew', 'land_user', 'land_admin', 'super_admin')),
  village_id uuid references public.villages(id),
  boat_id uuid references public.boats(id), -- Current active boat
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 4. Boat Logs (Location History)
create table public.boat_logs (
  id bigint generated always as identity primary key,
  boat_id uuid references public.boats(id),
  lat double precision not null,
  lon double precision not null,
  battery_level int,
  speed double precision,
  heading double precision,
  recorded_at timestamptz default now()
);

-- 5. Boat Members (Crew/Guests)
create table public.boat_members (
  boat_id uuid references public.boats(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  role text check (role in ('crew', 'land_user')),
  joined_at timestamptz default now(),
  primary key (boat_id, user_id)
);

-- 6. Geofences
create table public.geofences (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  coordinates jsonb not null, -- GeoJSON or list of points
  type text check (type in ('border', 'danger_zone', 'fishing_zone')),
  created_at timestamptz default now()
);

-- Row Level Security (RLS) Policies

-- Enable RLS
alter table public.villages enable row level security;
alter table public.boats enable row level security;
alter table public.profiles enable row level security;
alter table public.boat_logs enable row level security;
alter table public.boat_members enable row level security;
alter table public.geofences enable row level security;

-- Policies

-- Villages: Public read
create policy "Villages are viewable by everyone"
  on public.villages for select
  using (true);

-- Profiles: Public read (for boat members), Update own
create policy "Public profiles are viewable by everyone"
  on public.profiles for select
  using (true);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

-- Boats: Read by members/owners, Insert by authenticated
create policy "Boats viewable by members and owners"
  on public.boats for select
  using (
    auth.uid() = owner_id or
    exists (
      select 1 from public.boat_members
      where boat_id = public.boats.id and user_id = auth.uid()
    )
  );

create policy "Authenticated users can create boats"
  on public.boats for insert
  with check (auth.role() = 'authenticated');

create policy "Owners can update boats"
  on public.boats for update
  using (auth.uid() = owner_id);

-- Boat Logs: Read by members/owners, Insert by device (via Edge Function or specific role)
-- For now, allow authenticated users to insert logs for their boats
create policy "Members can view logs"
  on public.boat_logs for select
  using (
    exists (
      select 1 from public.boats
      where id = public.boat_logs.boat_id and (
        owner_id = auth.uid() or
        exists (
          select 1 from public.boat_members
          where boat_id = public.boats.id and user_id = auth.uid()
        )
      )
    )
  );

create policy "Owners/Members can insert logs"
  on public.boat_logs for insert
  with check (
    exists (
      select 1 from public.boats
      where id = boat_id and (
        owner_id = auth.uid() or
        exists (
          select 1 from public.boat_members
          where boat_id = public.boats.id and user_id = auth.uid()
        )
      )
    )
  );

-- Geofences: Public read
create policy "Geofences are viewable by everyone"
  on public.geofences for select
  using (true);

-- Functions & Triggers

-- Handle New User -> Create Profile
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, new.raw_user_meta_data->>'display_name');
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
