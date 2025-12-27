-- 1. Enums
create type audit_status as enum ('STARTED', 'COMPLETED', 'FAILED');
create type audit_action_type as enum (
  'UPDATE_PROFILE',
  'REGISTER_BOAT',
  'UPDATE_BOAT',
  'DELETE_BOAT', -- Manual or Cascade
  'JOIN_BOAT',
  'LEAVE_BOAT',
  'BROADCAST_SOS',
  'DELETE_ACCOUNT'
);

-- 2. Audit Table
create table if not exists user_actions_audit (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null, -- Keep log even if user deleted
  action audit_action_type not null,
  status audit_status not null default 'COMPLETED',
  original_data jsonb, -- Snapshot of data before change (or new data for insert)
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table user_actions_audit enable row level security;

-- Policies: Users can view their own audit logs (if they exist)
create policy "Users can view own audit logs"
  on user_actions_audit for select
  using (user_id = auth.uid());

-- 3. Generic Trigger Function
create or replace function log_user_action()
returns trigger
language plpgsql
security definer
as $$
declare
  v_action audit_action_type;
  v_user_id uuid;
  v_data jsonb;
begin
  -- Determine Action and User based on table and operation
  if TG_TABLE_NAME = 'profiles' then
    if TG_OP = 'UPDATE' then
      v_action := 'UPDATE_PROFILE';
      v_user_id := NEW.id;
      v_data := row_to_json(OLD); -- Log previous state
    end if;
  
  elsif TG_TABLE_NAME = 'boats' then
    if TG_OP = 'INSERT' then
      v_action := 'REGISTER_BOAT';
      v_user_id := NEW.owner_id;
      v_data := row_to_json(NEW);
    elsif TG_OP = 'UPDATE' then
      v_action := 'UPDATE_BOAT';
      v_user_id := NEW.owner_id;
      v_data := row_to_json(OLD);
    elsif TG_OP = 'DELETE' then
      v_action := 'DELETE_BOAT';
      v_user_id := OLD.owner_id;
      v_data := row_to_json(OLD);
    end if;

  elsif TG_TABLE_NAME = 'boat_members' then
    if TG_OP = 'INSERT' then
      v_action := 'JOIN_BOAT';
      v_user_id := NEW.user_id;
      v_data := row_to_json(NEW);
    elsif TG_OP = 'DELETE' then
      v_action := 'LEAVE_BOAT';
      v_user_id := OLD.user_id;
      v_data := row_to_json(OLD);
    end if;

  elsif TG_TABLE_NAME = 'sos_signals' then
    if TG_OP = 'INSERT' then
      v_action := 'BROADCAST_SOS';
      v_user_id := NEW.sender_id;
      v_data := row_to_json(NEW);
    end if;
  end if;

  -- Insert Audit Log if valid action identified
  if v_action is not null then
    insert into user_actions_audit (user_id, action, status, original_data)
    values (v_user_id, v_action, 'COMPLETED', v_data);
  end if;

  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end;
$$;

-- 4. Apply Triggers
create trigger audit_profiles_update
  after update on public.profiles
  for each row execute function log_user_action();

create trigger audit_boats_changes
  after insert or update or delete on public.boats
  for each row execute function log_user_action();

create trigger audit_boat_members_changes
  after insert or delete on public.boat_members
  for each row execute function log_user_action();

create trigger audit_sos_broadcast
  after insert on public.sos_signals
  for each row execute function log_user_action();


-- 5. Updated Delete Account RPC (with Audit)
create or replace function delete_account()
returns void
language plpgsql
security definer
as $$
declare
  requester_id uuid;
  audit_id uuid;
  user_data jsonb;
begin
  requester_id := auth.uid();
  
  -- Prevent double deletion or concurrency issues
  if requester_id is null then raise exception 'Not authenticated'; end if;

  -- Snapshot user data for audit
  select row_to_json(u) into user_data from auth.users u where id = requester_id;

  -- 1. Log STARTED
  insert into user_actions_audit (user_id, action, status, original_data)
  values (requester_id, 'DELETE_ACCOUNT', 'STARTED', user_data)
  returning id into audit_id;

  -- 2. Clean up dependencies (same as v5 logic)
  delete from public.boat_logs where boat_id in (select id from public.boats where owner_id = requester_id);
  delete from public.sos_signals where boat_id in (select id from public.boats where owner_id = requester_id);
  delete from public.boats where owner_id = requester_id;
  
  -- 3. Delete User
  -- NOTE: This triggers the Foreign Key 'ON DELETE SET NULL' on the audit row we just created.
  delete from auth.users where id = requester_id;

  -- 4. Log COMPLETED
  -- We update the audit record. 'user_id' is now NULL, but we have 'audit_id'.
  update user_actions_audit
  set status = 'COMPLETED', updated_at = now()
  where id = audit_id;

end;
$$;
