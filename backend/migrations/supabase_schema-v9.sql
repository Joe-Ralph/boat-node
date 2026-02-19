-- 1. Enable Realtime for sos_signals table
begin;

-- Add table to publication if it exists
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' 
    and schemaname = 'public' 
    and tablename = 'sos_signals'
  ) then
    alter publication supabase_realtime add table public.sos_signals;
  end if;
end $$;

-- 2. Ensure RLS is enabled
alter table public.sos_signals enable row level security;

-- 3. Add Policy for selecting SOS signals (Required for Realtime subscriptions)
-- Drop existing policy if it exists to avoid conflicts
drop policy if exists "SOS signals are viewable by everyone" on public.sos_signals;

create policy "SOS signals are viewable by everyone"
  on public.sos_signals for select
  using (true);

commit;
