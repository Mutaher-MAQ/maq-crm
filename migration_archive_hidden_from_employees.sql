-- MAQ CRM: employees cannot see archived records. Managers, admins and directors still can.
-- Enforced in the database (read policy), not just hidden in the app. Safe to re-run.

create or replace function is_employee()
returns boolean language sql stable security definer as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'employee')
$$;

drop policy if exists "opp read" on opportunities;
create policy "opp read" on opportunities
  for select using (
    can_see_opp_full(id, department, assigned_to, po_principal_id)
    and (not archived or not is_employee())
  );

notify pgrst, 'reload schema';

select 'archived rows: ' || count(*) as r from opportunities where archived
union all select 'employees: ' || count(*) from profiles where role = 'employee';
