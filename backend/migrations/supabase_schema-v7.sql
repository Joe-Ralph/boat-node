-- SOS Cancellation RPC
-- Allows a user to cancel their active SOS broadcast by deleting their sent signals.
create or replace function cancel_sos()
returns void
language plpgsql
security definer
as $$
declare
  requester_id uuid;
begin
  requester_id := auth.uid();
  
  if requester_id is null then raise exception 'Not authenticated'; end if;

  -- Delete all signals sent by this user
  delete from public.sos_signals where sender_id = requester_id;
  
end;
$$;
