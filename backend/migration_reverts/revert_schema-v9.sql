-- Revert enabling Realtime for sos_signals
begin;

-- Remove table from publication
alter publication supabase_realtime drop table public.sos_signals;

-- Remove the policy
drop policy if exists "SOS signals are viewable by everyone" on public.sos_signals;

commit;
