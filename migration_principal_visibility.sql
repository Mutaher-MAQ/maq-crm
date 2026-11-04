-- MAQ CRM: let a teammate see every record that involves certain principals,
-- whichever department or person owns it (e.g. Daniyal sees all Lufkin work,
-- including Asma's, without seeing the rest of her department).
-- profiles.extra_principals lists the principals; only admins can edit profiles.
-- A record matches if one of its RFQ principals (opportunity_principals) or its
-- PO principal is in the list. They can view and edit those records.
-- Safe to re-run.

alter table profiles add column if not exists extra_principals uuid[] not null default '{}';

create or replace function can_see_opp_full(opp uuid, dept text, assignee uuid, po_principal uuid)
returns boolean language sql stable security definer as $$
  select can_see_opp(dept, assignee)
    or exists (
      select 1 from profiles me
      where me.id = auth.uid()
        and cardinality(me.extra_principals) > 0
        and (
          po_principal = any(me.extra_principals)
          or exists (
            select 1 from opportunity_principals op
            where op.opportunity_id = opp and op.principal_id = any(me.extra_principals)
          )
        )
    )
$$;

drop policy if exists "opp read" on opportunities;
drop policy if exists "opp update" on opportunities;
drop policy if exists "opp delete" on opportunities;
create policy "opp read" on opportunities
  for select using (can_see_opp_full(id, department, assigned_to, po_principal_id));
create policy "opp update" on opportunities
  for update using (can_see_opp_full(id, department, assigned_to, po_principal_id))
  with check (auth.role() = 'authenticated');
create policy "opp delete" on opportunities
  for delete using (can_see_opp_full(id, department, assigned_to, po_principal_id));

notify pgrst, 'reload schema';
