-- Revert script for supabase_schema-v5.sql

-- Drop RPC function
-- Note: v6 updates this function, but v5 created it. Dropping it here removes it.
drop function if exists delete_account();
