-- Revert script for supabase_schema-v2.sql

-- Drop function
drop function if exists get_device_password(text);

-- Drop table
drop table if exists public.devices;
