-- 1. Enable access for Land Admins
create policy "Land Admins can view boats in their village"
  on public.boats for select
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'land_admin' and village_id = public.boats.village_id
    )
  );

-- 2. Enable access for Super Admins
create policy "Super Admins can view all boats"
  on public.boats for select
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'super_admin'
    )
  );

-- 3. Allow Land Admins to view members of boats in their village
-- Helper function to avoid recursion with boats policy
create or replace function public.is_land_admin_for_boat(boat_id uuid)
returns boolean
language plpgsql
security definer
as $$
begin
  return exists (
    select 1
    from public.boats b
    join public.profiles p on p.village_id = b.village_id
    where b.id = boat_id
    and p.id = auth.uid()
    and p.role = 'land_admin'
  );
end;
$$;

create policy "Land Admins can view members"
  on public.boat_members for select
  using (
    public.is_land_admin_for_boat(boat_id)
  );

