-- 1. Create Devices Table
create table public.devices (
  device_id text primary key, -- The ID found in the SSID (e.g., '1234')
  wifi_password text not null,
  status text default 'unpaired' check (status in ('unpaired', 'paired')),
  created_at timestamptz default now()
);

-- 2. Enable RLS
alter table public.devices enable row level security;

-- 3. Policies
-- Only authenticated users can read device info (or restrict further if needed)
create policy "Authenticated users can view devices"
  on public.devices for select
  to authenticated
  using (true);

-- 4. Secure Function to get password (Optional, if you want to hide the table)
-- This allows fetching password only if the device is unpaired, for example.
create or replace function get_device_password(p_device_id text)
returns text
language plpgsql
security definer
as $$
declare
  v_password text;
begin
  select wifi_password into v_password
  from public.devices
  where device_id = p_device_id;
  
  return v_password;
end;
$$;

-- 5. Insert some mock data for testing
insert into public.devices (device_id, wifi_password)
values 
  ('1234', 'pairme-1234'),
  ('5678', 'pairme-5678')
on conflict (device_id) do nothing;
