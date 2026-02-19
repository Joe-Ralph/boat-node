-- Temporary script to update the 'profiles' table role check constraint in production.
-- This allows 'super_admin' to be stored in the 'role' column.

DO $$
BEGIN
  -- 1. Drop existing constraint (name might vary, so we try standard naming first)
  ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
  
  -- 2. Add new constraint with 'super_admin'
  ALTER TABLE public.profiles 
    ADD CONSTRAINT profiles_role_check 
    CHECK (role IN ('owner', 'crew', 'land_user', 'land_admin', 'super_admin'));
    
  RAISE NOTICE 'Profiles check constraint updated successfully.';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Error updating constraint: %', SQLERRM;
END;
$$;
