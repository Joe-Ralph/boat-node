-- Revert policies added in supabase_schema-v8.sql

drop policy if exists "Land Admins can view boats in their village" on public.boats;
drop policy if exists "Super Admins can view all boats" on public.boats;
drop policy if exists "Land Admins can view members" on public.boat_members;
