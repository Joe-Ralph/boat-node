-- Revert script for supabase_schema-v1.sql

-- Drop triggers
drop trigger if exists on_auth_user_created on auth.users;

-- Drop functions
drop function if exists public.handle_new_user();

-- Drop RLS policies (Policies are dropped when tables are dropped, but good to be explicit if recreating)
-- (Implicitly handled by drop table)

-- Drop Tables (Order matters: Drop dependents first)
drop table if exists public.boat_members;
drop table if exists public.boat_logs;
drop table if exists public.profiles;
drop table if exists public.boats;
drop table if exists public.villages;
drop table if exists public.geofences;

-- Drop extensions (Optional, usually we keep extensions enabled)
-- drop extension if exists "uuid-ossp";
