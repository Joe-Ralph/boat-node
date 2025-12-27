-- Revert script for supabase_schema-v4.sql

-- Drop RPC function
drop function if exists broadcast_sos(double precision, double precision);

-- Drop table
drop table if exists public.sos_signals;

-- Remove keys added to app_settings (instead of dropping table which is from v3)
delete from public.app_settings where key in ('sos_broadcast_count', 'sos_search_radius_meters');

-- Note: user_locations was removed from v4 final schema, so no need to drop it.
-- But just in case it existed from a bad apply:
drop table if exists public.user_locations;
