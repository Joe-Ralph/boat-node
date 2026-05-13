-- v10: Hybrid LoRaWAN+mesh schema additions.
--   * Adds mesh identity + secrets to boats.
--   * Adds compact u16 user_short_id to profiles for over-the-air SOS attribution.
--   * Extends sos_signals with mesh origin, hops, gateway, ACK status, dedup.
--   * Adds boat_journey_events for crew journey toggle audit.
--   * Adds RPCs: pair_boat (owner), get_crew_token (members), boats_public (view).
--
-- Existing column conventions preserved:
--   boats.id        -> uuid
--   profiles.id     -> uuid (= auth.users.id)
--   sos_signals.id  -> uuid
--   sos_signals lat/long columns kept (note `long`, not `lon`).
--   boats.name kept as display string (no separate display_name column).

begin;

-------------------------------------------------------------------------------
-- 1. boats: mesh identity + secrets
-------------------------------------------------------------------------------

alter table public.boats
  add column if not exists mesh_src_id   integer unique
    check (mesh_src_id is null or (mesh_src_id > 0 and mesh_src_id < 65535)),
  add column if not exists hmac_secret   bytea,
  add column if not exists crew_token    bytea,
  add column if not exists dev_eui       bytea,
  add column if not exists last_sos_seq  integer default 0
    check (last_sos_seq >= 0 and last_sos_seq <= 65535),
  add column if not exists relay_mode    boolean default false,
  add column if not exists unpaired_at   timestamptz;

-------------------------------------------------------------------------------
-- 2. profiles: u16 user_short_id with auto-assign trigger + backfill
-------------------------------------------------------------------------------

alter table public.profiles
  add column if not exists user_short_id integer unique
    check (user_short_id is null or (user_short_id > 0 and user_short_id < 65535));

create or replace function public.assign_user_short_id()
returns trigger language plpgsql as $$
begin
  if NEW.user_short_id is null then
    select coalesce(max(user_short_id), 0) + 1
      into NEW.user_short_id from public.profiles;
  end if;
  return NEW;
end $$;

drop trigger if exists profiles_assign_short_id on public.profiles;
create trigger profiles_assign_short_id
  before insert on public.profiles
  for each row execute function public.assign_user_short_id();

-- Backfill existing rows in creation order.
with ordered as (
  select id, row_number() over (order by created_at) as rn
  from public.profiles
  where user_short_id is null
)
update public.profiles p
   set user_short_id = ordered.rn
  from ordered
 where p.id = ordered.id;

-------------------------------------------------------------------------------
-- 3. sos_signals: mesh origin metadata + ACK lifecycle
--    Existing CHECK on status is replaced to include the v10 lifecycle.
-------------------------------------------------------------------------------

alter table public.sos_signals
  add column if not exists origin                 text not null default 'phone_direct'
    check (origin in ('mesh', 'phone_direct')),
  add column if not exists trigger_user_short_id  integer references public.profiles(user_short_id),
  add column if not exists trigger_user_id        uuid    references public.profiles(id),
  add column if not exists mesh_seq               integer
    check (mesh_seq is null or (mesh_seq >= 0 and mesh_seq <= 65535)),
  add column if not exists mesh_hops              smallint,
  add column if not exists gateway_boat_id        uuid    references public.boats(id),
  add column if not exists ack_status             smallint default 0
    check (ack_status >= 0 and ack_status <= 3),
  add column if not exists acked_at               timestamptz;

do $$
declare con text;
begin
  -- Drop the existing status CHECK if present (name varies; find it).
  select conname into con
    from pg_constraint
   where conrelid = 'public.sos_signals'::regclass
     and contype  = 'c'
     and pg_get_constraintdef(oid) ilike '%status%pending%';
  if con is not null then
    execute format('alter table public.sos_signals drop constraint %I', con);
  end if;
end $$;

alter table public.sos_signals
  add constraint sos_signals_status_check
  check (status in ('pending', 'accepted', 'rejected', 'ignored',
                    'active', 'canceled', 'resolved', 'false_alarm'));

-- Unique mesh dedup: a (boat, mesh_seq) pair only once for mesh-origin rows.
create unique index if not exists sos_dedup
  on public.sos_signals (boat_id, mesh_seq)
  where origin = 'mesh';

-------------------------------------------------------------------------------
-- 4. boat_journey_events: crew start/end audit log
-------------------------------------------------------------------------------

create table if not exists public.boat_journey_events (
  id      bigint generated always as identity primary key,
  boat_id uuid not null references public.boats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  action  text not null check (action in ('start', 'end')),
  ts      timestamptz not null default now()
);

create index if not exists bje_boat_ts
  on public.boat_journey_events (boat_id, ts desc);

alter table public.boat_journey_events enable row level security;

drop policy if exists "Journey events readable by boat owner or member"
  on public.boat_journey_events;
create policy "Journey events readable by boat owner or member"
  on public.boat_journey_events for select
  using (
    exists (select 1 from public.boats b
             where b.id = boat_journey_events.boat_id
               and b.owner_id = auth.uid())
    or exists (select 1 from public.boat_members m
                where m.boat_id = boat_journey_events.boat_id
                  and m.user_id = auth.uid())
  );

drop policy if exists "Journey events writable by self if member"
  on public.boat_journey_events;
create policy "Journey events writable by self if member"
  on public.boat_journey_events for insert
  with check (
    user_id = auth.uid()
    and (
      exists (select 1 from public.boats b
               where b.id = boat_journey_events.boat_id
                 and b.owner_id = auth.uid())
      or exists (select 1 from public.boat_members m
                  where m.boat_id = boat_journey_events.boat_id
                    and m.user_id = auth.uid())
    )
  );

-------------------------------------------------------------------------------
-- 5. RPC: get_crew_token(boat_id) -> bytea
--    Returns the boat's crew_token to authenticated members or owner.
-------------------------------------------------------------------------------

create or replace function public.get_crew_token(p_boat_id uuid)
returns bytea
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  token  bytea;
begin
  if caller is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (
        select 1 from public.boat_members
         where boat_id = p_boat_id and user_id = caller
      )
     and not exists (
        select 1 from public.boats
         where id = p_boat_id and owner_id = caller
      )
  then
    raise exception 'not_a_member';
  end if;
  select crew_token into token from public.boats where id = p_boat_id;
  return token;
end $$;

revoke all on function public.get_crew_token(uuid) from public;
grant  execute on function public.get_crew_token(uuid) to authenticated;

-------------------------------------------------------------------------------
-- 6. RPC: pair_boat(...) -> integer mesh_src_id
--    Owner sends generated secrets + display name; backend assigns mesh_src_id.
-------------------------------------------------------------------------------

create or replace function public.pair_boat(
  p_dev_eui      bytea,
  p_hmac_secret  bytea,
  p_crew_token   bytea,
  p_display_name text
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  caller  uuid := auth.uid();
  new_src integer;
begin
  if caller is null then
    raise exception 'not_authenticated';
  end if;
  if p_hmac_secret is null or octet_length(p_hmac_secret) <> 16 then
    raise exception 'hmac_secret_must_be_16_bytes';
  end if;
  if p_crew_token is null or octet_length(p_crew_token) <> 8 then
    raise exception 'crew_token_must_be_8_bytes';
  end if;

  select coalesce(max(mesh_src_id), 0) + 1 into new_src from public.boats;
  if new_src >= 65535 then
    raise exception 'mesh_src_id_pool_exhausted';
  end if;

  insert into public.boats (owner_id, mesh_src_id, dev_eui,
                            hmac_secret, crew_token, name)
  values (caller, new_src, p_dev_eui,
          p_hmac_secret, p_crew_token, p_display_name);
  return new_src;
end $$;

revoke all on function public.pair_boat(bytea, bytea, bytea, text) from public;
grant  execute on function public.pair_boat(bytea, bytea, bytea, text) to authenticated;

-------------------------------------------------------------------------------
-- 7. View: boats_public
--    Apps and admin read this; never expose hmac_secret / crew_token through PostgREST.
-------------------------------------------------------------------------------

create or replace view public.boats_public as
  select id, owner_id, mesh_src_id, name, village_id, registration_number,
         device_id, created_at, last_sos_seq, relay_mode
    from public.boats;

grant select on public.boats_public to authenticated, anon;

commit;
