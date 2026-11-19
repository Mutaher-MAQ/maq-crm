-- MAQ CRM: hierarchy Associate (stored as 'employee') -> Supervisor -> Manager -> Director (admin is separate).
-- Adds the Supervisor role and a "reports to" link on each person. A supervisor (and a manager)
-- sees their own records plus the records of the people who report to them.
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
  check (role in ('employee','supervisor','manager','director','admin'));

-- 2. Who each person reports to
alter table profiles add column if not exists reports_to uuid references profiles(id) on delete set null;

-- 3. Visibility: add "records assigned to someone who reports to me"
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
        or (me.role in ('supervisor','manager') and assignee is not null
            and exists (select 1 from profiles rep where rep.id = assignee and rep.reports_to = me.id))
      )
  )
$$;

-- 4. Set up the current team
update profiles set role = 'supervisor' where email ilike 'asma.chan%';
update profiles set reports_to = (select id from profiles where email ilike 'asma.chan%' limit 1) where email ilike 'hammad.ahmed%';
update profiles set reports_to = (select id from profiles where email ilike 'talha.ahmed%' limit 1) where email ilike 'abdul.basit%';

notify pgrst, 'reload schema';

select split_part(p.email,'@',1) || ' | ' || p.role || ' | reports to ' || coalesce(split_part(b.email,'@',1),'-') as team
from profiles p left join profiles b on b.id = p.reports_to order by p.role, p.email;
