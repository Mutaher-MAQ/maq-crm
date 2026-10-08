-- Run after the data import (migrate-from-cloud.sh does this for you).
-- Re-creates the pieces that pg_dump --schema=public does not carry over.
-- Safe to run more than once.

-- 1) Every new login gets a profile row (this trigger lives on auth.users, outside the public schema)
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2) Live updates: the app listens to these eight tables
do $$
declare t text;
begin
  foreach t in array array['profiles','customers','principals','contacts','opportunities','opportunity_principals','tasks','activities'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- 3) Standard Supabase table permissions (row-level security still decides who sees what;
--    the anon role has no policies, so it sees nothing)
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables    in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;
