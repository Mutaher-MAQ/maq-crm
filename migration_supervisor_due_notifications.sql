-- MAQ CRM: when someone's offer or follow-up is overdue, their supervisor gets a notification too.
--   * offer due today or overdue          -> owner (as before) + the owner's "Reports to" supervisor/manager
--   * follow-up overdue (1+ day late)     -> owner (as before) + the owner's "Reports to" supervisor/manager
-- The 2-days-ahead warning and "follow-up due today" stay with the owner only (less noise for supervisors).
-- Only goes to a supervisor, manager, admin or director, who are the people who can see the record anyway.
-- Safe to re-run.
create or replace function generate_due_notifications()
returns int language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Karachi')::date;
  n int := 0; r record; cnt int; sup uuid; sup_role text; owner_name text;
begin
  for r in
    select o.id, o.assigned_to, o.follow_up_date, o.due_date, o.rfq_status,
           coalesce(nullif(o.project_name,''), nullif(o.item_product,''), 'an RFQ') || coalesce(' (' || c.name || ')', '') as label
    from opportunities o left join customers c on c.id = o.customer_id
    where o.assigned_to is not null and not o.archived and o.pipeline_stage = 'rfq'
      and coalesce(o.win_lose, 'pending') = 'pending'
  loop
    -- the owner's supervisor, if they have one who can see the record
    select p.reports_to into sup from profiles p where p.id = r.assigned_to;
    sup_role := null; owner_name := null;
    if sup is not null and sup <> r.assigned_to then
      select role into sup_role from profiles where id = sup;
      if sup_role not in ('supervisor','manager','admin','director') then sup := null; end if;
      select coalesce(nullif(nullif(full_name,''), email), split_part(email,'@',1)) into owner_name from profiles where id = r.assigned_to;
    else
      sup := null;
    end if;

    if r.follow_up_date is not null and r.follow_up_date <= today then
      insert into notifications (user_id, kind, title, body, opportunity_id, dedupe_key)
      values (r.assigned_to, 'due',
        'Follow-up ' || case when r.follow_up_date < today then 'overdue' else 'due today' end || ': ' || r.label,
        'Follow-up date ' || to_char(r.follow_up_date, 'DD/MM/YYYY'), r.id, 'fu:' || r.id || ':' || today)
      on conflict do nothing;
      get diagnostics cnt = row_count; n := n + cnt;
      if sup is not null and r.follow_up_date < today then
        insert into notifications (user_id, kind, title, body, opportunity_id, dedupe_key)
        values (sup, 'team', owner_name || '''s follow-up is overdue: ' || r.label,
          'Follow-up date ' || to_char(r.follow_up_date, 'DD/MM/YYYY'), r.id, 'sfu:' || r.id || ':' || today)
        on conflict do nothing;
        get diagnostics cnt = row_count; n := n + cnt;
      end if;
    end if;
    if r.due_date is not null and r.due_date <= today + 2 and r.rfq_status in ('not_started', 'in_progress') then
      insert into notifications (user_id, kind, title, body, opportunity_id, dedupe_key)
      values (r.assigned_to, 'due',
        'Offer ' || case when r.due_date < today then 'overdue' when r.due_date = today then 'due today' else 'due in ' || (r.due_date - today) || ' day(s)' end || ': ' || r.label,
        'Offer due date ' || to_char(r.due_date, 'DD/MM/YYYY'), r.id, 'od:' || r.id || ':' || today)
      on conflict do nothing;
      get diagnostics cnt = row_count; n := n + cnt;
      if sup is not null and r.due_date <= today then
        insert into notifications (user_id, kind, title, body, opportunity_id, dedupe_key)
        values (sup, 'team', owner_name || '''s offer is ' || case when r.due_date < today then 'overdue' else 'due today' end || ': ' || r.label,
          'Offer due date ' || to_char(r.due_date, 'DD/MM/YYYY'), r.id, 'sod:' || r.id || ':' || today)
        on conflict do nothing;
        get diagnostics cnt = row_count; n := n + cnt;
      end if;
    end if;
  end loop;
  delete from notifications where read_at is not null and read_at < now() - interval '60 days';
  return n;
end $$;
grant execute on function generate_due_notifications() to authenticated;
notify pgrst, 'reload schema';
