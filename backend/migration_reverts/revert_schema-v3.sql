-- Revert script for supabase_schema-v3.sql

-- Drop function
drop function if exists public.get_nearby_boats(double precision, double precision, double precision, int);

-- Drop tables
drop table if exists public.boat_live_locations;
-- Note: app_settings is modified in later migrations, usually safe to drop if reverting this specifc version,
-- but if we reverted v4 then v3, dropping it here is correct.
drop table if exists public.app_settings;
