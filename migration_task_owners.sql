-- MAQ CRM: tasks belong to the person who created them.
-- Before this, every signed-in user could read (and change) every task, including the contact and
-- opportunity names on it. After this:
--   * you see and edit your own tasks
--   * a supervisor or manager also sees the tasks of the people who report to them
--   * admins and directors see all (directors read-only)
-- Safe to re-run.
alter table tasks add column if not exists created_by uuid references profiles(id) on delete set null default auth.uid();

-- Existing tasks have no creator: give those linked to an opportunity to that opportunity's owner
update tasks t set created_by = o.assigned_to
  from opportunities o
  where t.created_by is null and t.opportunity_id = o.id and o.assigned_to is not null;

create or replace function can_see_task(creator uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles me
    where me.id = auth.uid()
      and (
        me.role in ('admin','director')
        or creator = me.id
        or (me.role in ('supervisor','manager')
            and exists (select 1 from profiles c where c.id = creator and c.reports_to = me.id))
      )
  );
$$;

do $$ declare p text; begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'tasks' loop
    execute format('drop policy %I on tasks', p);
  end loop;
end $$;

create policy "tasks read own" on tasks for select using (can_see_task(created_by));
create policy "tasks insert" on tasks for insert
  with check (auth.role() = 'authenticated' and is_not_director() and (created_by is null or created_by = auth.uid()));
create policy "tasks update" on tasks for update
  using (is_not_director() and can_see_task(created_by))
  with check (is_not_director() and can_see_task(created_by));
create policy "tasks delete" on tasks for delete
  using (is_not_director() and can_see_task(created_by));

notify pgrst, 'reload schema';
