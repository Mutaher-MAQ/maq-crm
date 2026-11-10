-- MAQ CRM: Director role. Directors see every record in every department
-- (like an admin) but cannot create, edit, delete or archive anything.
-- Enforced here in the database, not just in the screens.
-- Set a person's role to Director on the Team page.
-- Safe to re-run.

-- 1. Allow the new role value
do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'profiles'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%role%'
  loop
    execute format('alter table profiles drop constraint %I', c);
  end loop;
end $$;
alter table profiles add constraint profiles_role_check
  check (role in ('employee','manager','director','admin'));

-- 2. Helper: true for everyone except directors
create or replace function is_not_director()
returns boolean language sql stable security definer as $$
  select not exists (select 1 from profiles where id = auth.uid() and role = 'director')
$$;

-- 3. Directors see all opportunities
create or replace function can_see_opp(dept text, assignee uuid)
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from profiles me
    where me.id = auth.uid()
      and (
        me.role in ('admin','director')
        or dept is null
        or assignee = auth.uid()
        or (me.role = 'manager' and (me.department = dept or dept = any(me.extra_departments)))
        or (assignee is null and (me.department = dept or dept = any(me.extra_departments)))
      )
  )
$$;

-- 4. Opportunities: everyone who can see a row can read it; directors cannot write
drop policy if exists "opp read" on opportunities;
drop policy if exists "opp insert" on opportunities;
drop policy if exists "opp update" on opportunities;
drop policy if exists "opp delete" on opportunities;
create policy "opp read" on opportunities
  for select using (can_see_opp_full(id, department, assigned_to, po_principal_id));
create policy "opp insert" on opportunities
  for insert with check (auth.role() = 'authenticated' and is_not_director());
create policy "opp update" on opportunities
  for update using (can_see_opp_full(id, department, assigned_to, po_principal_id) and is_not_director())
  with check (auth.role() = 'authenticated' and is_not_director());
create policy "opp delete" on opportunities
  for delete using (can_see_opp_full(id, department, assigned_to, po_principal_id) and is_not_director());

-- 5. Other tables: everyone signed in reads, directors cannot write
do $$
declare t text;
begin
  foreach t in array array['customers','principals','contacts','opportunity_principals','tasks','activities']
  loop
    execute format('drop policy if exists "authenticated full access" on %I', t);
    execute format('drop policy if exists "read all" on %I', t);
    execute format('drop policy if exists "write not director" on %I', t);
    execute format('create policy "read all" on %I for select using (auth.role() = ''authenticated'')', t);
    execute format('create policy "write not director" on %I for all using (auth.role() = ''authenticated'' and is_not_director()) with check (auth.role() = ''authenticated'' and is_not_director())', t);
  end loop;
end $$;

notify pgrst, 'reload schema';
