-- Revert v10: hybrid LoRaWAN+mesh schema additions.
-- Drops everything v10 added in dependency-safe order.

begin;

-------------------------------------------------------------------------------
-- 7. View
-------------------------------------------------------------------------------
drop view if exists public.boats_public;

-------------------------------------------------------------------------------
-- 6. pair_boat RPC
-------------------------------------------------------------------------------
revoke execute on function public.pair_boat(bytea, bytea, bytea, text) from authenticated;
drop function if exists public.pair_boat(bytea, bytea, bytea, text);

-------------------------------------------------------------------------------
-- 5. get_crew_token RPC
-------------------------------------------------------------------------------
revoke execute on function public.get_crew_token(uuid) from authenticated;
drop function if exists public.get_crew_token(uuid);

-------------------------------------------------------------------------------
-- 4. boat_journey_events
-------------------------------------------------------------------------------
drop policy if exists "Journey events writable by self if member"
  on public.boat_journey_events;
drop policy if exists "Journey events readable by boat owner or member"
  on public.boat_journey_events;
drop index if exists bje_boat_ts;
drop table if exists public.boat_journey_events;

-------------------------------------------------------------------------------
-- 3. sos_signals: restore status CHECK to pre-v10 set, drop v10 columns + index
-------------------------------------------------------------------------------
drop index if exists sos_dedup;

alter table public.sos_signals
  drop constraint if exists sos_signals_status_check;

-- Restore original status set (matches v4 definition).
alter table public.sos_signals
  add constraint sos_signals_status_check
  check (status in ('pending', 'accepted', 'rejected', 'ignored'));

alter table public.sos_signals
  drop column if exists acked_at,
  drop column if exists ack_status,
  drop column if exists gateway_boat_id,
  drop column if exists mesh_hops,
  drop column if exists mesh_seq,
  drop column if exists trigger_user_id,
  drop column if exists trigger_user_short_id,
  drop column if exists origin;

-------------------------------------------------------------------------------
-- 2. profiles.user_short_id
-------------------------------------------------------------------------------
drop trigger if exists profiles_assign_short_id on public.profiles;
drop function if exists public.assign_user_short_id();
alter table public.profiles drop column if exists user_short_id;

-------------------------------------------------------------------------------
-- 1. boats
-------------------------------------------------------------------------------
alter table public.boats
  drop column if exists unpaired_at,
  drop column if exists relay_mode,
  drop column if exists last_sos_seq,
  drop column if exists dev_eui,
  drop column if exists crew_token,
  drop column if exists hmac_secret,
  drop column if exists mesh_src_id;

commit;
