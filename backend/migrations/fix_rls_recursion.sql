-- Fix Infinite Recursion in RLS Policies
-- The issue arises because 'boats' policies query 'boat_members', and 'boat_members' policies query 'boats'.
-- We break this cycle by using a SECURITY DEFINER function to check access on 'boat_members' without triggering RLS on 'boats'.

-- 1. Create a helper function to check if a user is a land_admin for a specific boat's village
-- This function runs with the privileges of the creator (superuser), bypassing RLS
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

-- 2. Drop the problematic policy on boat_members
drop policy if exists "Land Admins can view members" on public.boat_members;

-- 3. Re-create the policy using the security definer function
create policy "Land Admins can view members"
  on public.boat_members for select
  using (
    public.is_land_admin_for_boat(boat_id)
  );

-- 4. Ensure the policy for boats itself is safe (it queries profiles directly, which is fine)
-- "Land Admins can view boats in their village" is safe as is.
