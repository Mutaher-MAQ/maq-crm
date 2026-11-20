-- MAQ CRM: people only see the opportunity-to-principal links for opportunities they can see.
-- (Previously every signed-in user could read every link.) Safe to re-run.
drop policy if exists "read all" on opportunity_principals;
drop policy if exists "write not director" on opportunity_principals;
drop policy if exists "links read visible" on opportunity_principals;
drop policy if exists "links insert" on opportunity_principals;
drop policy if exists "links update" on opportunity_principals;
drop policy if exists "links delete" on opportunity_principals;
-- the subquery on opportunities is itself filtered by that table's row-level security
create policy "links read visible" on opportunity_principals for select
  using (exists (select 1 from opportunities o where o.id = opportunity_principals.opportunity_id));
create policy "links insert" on opportunity_principals for insert
  with check (auth.role() = 'authenticated' and is_not_director() and exists (select 1 from opportunities o where o.id = opportunity_principals.opportunity_id));
create policy "links update" on opportunity_principals for update
  using (auth.role() = 'authenticated' and is_not_director() and exists (select 1 from opportunities o where o.id = opportunity_principals.opportunity_id))
  with check (auth.role() = 'authenticated' and is_not_director() and exists (select 1 from opportunities o where o.id = opportunity_principals.opportunity_id));
create policy "links delete" on opportunity_principals for delete
  using (auth.role() = 'authenticated' and is_not_director() and exists (select 1 from opportunities o where o.id = opportunity_principals.opportunity_id));
notify pgrst, 'reload schema';
