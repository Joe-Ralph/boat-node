-- Enable PostGIS if not already enabled
create extension if not exists postgis;

-- 1. App Settings (Update)
-- Insert default SOS settings if they don't exist
insert into app_settings (key, value, description)
values
  ('sos_broadcast_count', '5', 'Number of nearest users to notify for SOS'),
  ('sos_search_radius_meters', '5000', 'Radius in meters to search for helpers')
on conflict (key) do nothing;

-- 2. SOS Signals Table
-- Stores the SOS event dispatch. 
-- Sender creates the event.
-- Receivers listen for 'insert' on this table where receiver_id matches theirs.
create table if not exists sos_signals (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  boat_id uuid references public.boats(id), -- Optional: Link to the boat providing the location
  status text check (status in ('pending', 'accepted', 'rejected', 'ignored')) default 'pending',
  lat double precision not null,
  long double precision not null,
  created_at timestamptz default now()
);

-- RLS for sos_signals
alter table sos_signals enable row level security;

-- Receiver can read (listen) their own signals
create policy "Users can see signals sent to them"
  on sos_signals
  for select
  using (receiver_id = auth.uid());

-- Sender can see signals they sent
create policy "Proposers can see signals they sent"
  on sos_signals
  for select
  using (sender_id = auth.uid());


-- 3. RPC Function: Broadcast SOS (Refactored)
-- Finds nearest BOATS (via boat_live_locations) and inserts into sos_signals for their OWNERS.
drop function if exists broadcast_sos(double precision, double precision);

create or replace function broadcast_sos(p_lat double precision, p_long double precision)
returns void
language plpgsql
security definer
as $$
declare
  sender_uid uuid;
  broadcast_count int;
  search_radius int;
begin
  sender_uid := auth.uid();
  
  -- Get settings (with fallbacks)
  select replace(value, '"', '')::int into broadcast_count from app_settings where key = 'sos_broadcast_count';
  if broadcast_count is null then broadcast_count := 5; end if;

  select replace(value, '"', '')::int into search_radius from app_settings where key = 'sos_search_radius_meters';
  if search_radius is null then search_radius := 5000; end if;

  -- Insert signals for nearest N boats within Radius
  -- We join boat_live_locations -> boats to get the owner_id
  insert into sos_signals (sender_id, receiver_id, boat_id, lat, long, status)
  select 
    sender_uid,
    b.owner_id,
    b.id,
    p_lat,
    p_long,
    'pending'
  from boat_live_locations bll
  join boats b on b.id = bll.boat_id
  where 
    b.owner_id != sender_uid -- Don't notify self
    and (
      6371000 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(p_lat)) * cos(radians(bll.lat)) *
          cos(radians(bll.lon) - radians(p_long)) +
          sin(radians(p_lat)) * sin(radians(bll.lat))
        ))
      )
    ) <= search_radius
  order by 
    (
      6371000 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(p_lat)) * cos(radians(bll.lat)) *
          cos(radians(bll.lon) - radians(p_long)) +
          sin(radians(p_lat)) * sin(radians(bll.lat))
        ))
      )
    ) asc
  limit broadcast_count;

end;
$$;
