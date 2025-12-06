-- 1. Boat Live Locations Table
-- Stores only the MOST RECENT location for each boat.
create table public.boat_live_locations (
  boat_id uuid references public.boats(id) on delete cascade primary key,
  lat double precision not null,
  lon double precision not null,
  heading double precision,
  speed double precision,
  battery_level int,
  last_updated timestamptz default now()
);

-- 2. RLS Policies
alter table public.boat_live_locations enable row level security;

-- Everyone can read live locations (for map/nearby features)
create policy "Live locations are viewable by everyone"
  on public.boat_live_locations for select
  using (true);

-- Authenticated users (owners/members) can update their boat's location
create policy "Owners/Members can upsert live location"
  on public.boat_live_locations for insert
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

create policy "Owners/Members can update live location"
  on public.boat_live_locations for update
  using (
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

-- 3. App Settings Table
create table public.app_settings (
  key text primary key,
  value text not null,
  description text
);

alter table public.app_settings enable row level security;

create policy "Settings are viewable by everyone"
  on public.app_settings for select
  using (true);

-- Insert default limit
insert into public.app_settings (key, value, description)
values ('nearby_boats_limit', '20', 'Max number of boats to return in nearby search')
on conflict (key) do nothing;

-- 4. Nearby Boats RPC Function
-- Unpaired phones use this to find boats near them from the server.
-- Uses Haversine formula for spherical distance (approximate but sufficient).
create or replace function public.get_nearby_boats(
  my_lat double precision,
  my_lon double precision,
  radius_meters double precision default 50000, -- 50km default
  limit_count int default null -- If null, uses setting or default
)
returns table (
  boat_id uuid,
  boat_name text,
  lat double precision,
  lon double precision,
  heading double precision,
  speed double precision,
  last_updated timestamptz,
  distance_meters double precision
)
language plpgsql
security definer
as $$
declare
  v_limit int;
begin
  -- Get limit from settings table, acting as system default/override
  select value::int into v_limit
  from public.app_settings
  where key = 'nearby_boats_limit';
  
  -- Logic: If limit_count input is provided, use it? Or use setting?
  -- User request: "adjust... in the settings and that will be used"
  -- So we prioritize the setting if it exists, otherwise fallback to input or default 20.
  
  if v_limit is null then
     v_limit := coalesce(limit_count, 20);
  end if;

  return query
  select
    b.id as boat_id,
    b.name as boat_name,
    loc.lat,
    loc.lon,
    loc.heading,
    loc.speed,
    loc.last_updated,
    (
      6371000 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(my_lat)) * cos(radians(loc.lat)) *
          cos(radians(loc.lon) - radians(my_lon)) +
          sin(radians(my_lat)) * sin(radians(loc.lat))
        ))
      )
    ) as distance_meters
  from
    public.boat_live_locations loc
  join
    public.boats b on b.id = loc.boat_id
  where
    (
      6371000 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(my_lat)) * cos(radians(loc.lat)) *
          cos(radians(loc.lon) - radians(my_lon)) +
          sin(radians(my_lat)) * sin(radians(loc.lat))
        ))
      )
    ) <= radius_meters
  order by
    distance_meters asc
  limit v_limit;
end;
$$;
