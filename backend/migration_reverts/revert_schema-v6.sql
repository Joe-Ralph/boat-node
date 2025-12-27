-- Revert script for supabase_schema-v6.sql

-- 1. Drop Triggers
drop trigger if exists audit_profiles_update on public.profiles;
drop trigger if exists audit_boats_changes on public.boats;
drop trigger if exists audit_boat_members_changes on public.boat_members;
drop trigger if exists audit_sos_broadcast on public.sos_signals;

-- 2. Drop Trigger Function
drop function if exists log_user_action();

-- 3. Drop Table
drop table if exists public.user_actions_audit;

-- 4. Drop Enums
drop type if exists audit_action_type;
drop type if exists audit_status;

-- 5. Revert delete_account RPC to its previous state (v5) or drop it?
-- Usually a revert script just drops what was added or "undoes" changes.
-- Since v6 *updated* delete_account, ideally we should revert it to v5's logic.
-- However, if we just want to strip v6 features, we can leave delete_account as is (it will just fail to log audit and error out) or revert it.
-- Reverting to v5 logic is safer to restore functionality.

create or replace function delete_account()
returns void
language plpgsql
security definer
as $$
declare
  requester_id uuid;
begin
  requester_id := auth.uid();
  
  delete from public.boat_logs where boat_id in (select id from public.boats where owner_id = requester_id);
  delete from public.sos_signals where boat_id in (select id from public.boats where owner_id = requester_id);
  delete from public.boats where owner_id = requester_id;
  delete from auth.users where id = requester_id;
end;
$$;
