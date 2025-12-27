-- 1. Delete Account RPC
-- Deletes the current user and all associated data.
-- Handles tables that do not have ON DELETE CASCADE configured.
create or replace function delete_account()
returns void
language plpgsql
security definer -- Required to access auth.users and other user's data during cleanup if needed
as $$
declare
  requester_id uuid;
begin
  requester_id := auth.uid();
  
  -- 1. Delete Boat Logs (Blocks deletion of Boats)
  -- Find boats owned by the user
  delete from public.boat_logs
  where boat_id in (select id from public.boats where owner_id = requester_id);

  -- 2. Delete SOS Signals referencing User's Boats (Blocks deletion of Boats)
  -- (Signals where sender/receiver is the user will cascade automatically, 
  -- but signals referencing the boat might not if boat_id is just a link)
  delete from public.sos_signals 
  where boat_id in (select id from public.boats where owner_id = requester_id);

  -- 3. Delete Boats (Owned by User)
  -- This will CASCADE delete:
  --   - boat_members (where boat_id = deleted_boat)
  --   - boat_live_locations (where boat_id = deleted_boat)
  delete from public.boats where owner_id = requester_id;

  -- 4. Delete Profile (Should cascade, but safe to be explicit or leave to cascade)
  -- (public.profiles references auth.users on delete cascade)

  -- 5. Delete User from Auth
  -- This will CASCADE delete:
  --   - public.profiles
  --   - public.boat_members (where user_id = requester_id)
  --   - public.sos_signals (where sender_id or receiver_id = requester_id)
  delete from auth.users where id = requester_id;
  
end;
$$;
