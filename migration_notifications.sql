-- MAQ CRM: in-app notifications.
--   * assigned to me          - someone assigns or reassigns a record to you
--   * status changes          - a record you own is moved/updated by someone else
--   * team activity           - what the people who report to you add or change
--   * due and overdue         - follow-ups and offers, generated daily (and when anyone opens the CRM)
-- Notifications are created by database triggers, so they cannot be skipped or faked from the screen.
-- Changes made from the SQL editor or imports (no signed-in user) do not notify anyone. Safe to re-run.

create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  kind text not null,                      -- assigned | status | team | due
  title text not null,
  body text,
  opportunity_id uuid references opportunities(id) on delete cascade,
  dedupe_key text,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists notifications_user_idx on notifications (user_id, created_at desc);
create unique index if not exists notifications_dedupe_idx on notifications (user_id, dedupe_key) where dedupe_key is not null;

alter table notifications enable row level security;
drop policy if exists "own notifications read" on notifications;
drop policy if exists "own notifications update" on notifications;
drop policy if exists "own notifications delete" on notifications;
create policy "own notifications read" on notifications for select using (user_id = auth.uid());
create policy "own notifications update" on notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own notifications delete" on notifications for delete using (user_id = auth.uid());

-- live updates
do $$ begin
  alter publication supabase_realtime add table notifications;
exception when duplicate_object then null; when others then null;
end $$;

-- Who did what: triggers on opportunities
create or replace function notify_opportunity_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  actor uuid := auth.uid();
  actor_name text; cust text; label text; what text; sup uuid;
  owner_notified boolean := false;
begin
  if actor is null then return NEW; end if;
  select coalesce(nullif(full_name,''), split_part(email,'@',1)) into actor_name from profiles where id = actor;
  select name into cust from customers where id = NEW.customer_id;
  label := coalesce(nullif(NEW.project_name,''), nullif(NEW.item_product,''), 'a record') || coalesce(' (' || cust || ')', '');

  if TG_OP = 'UPDATE' then
    if NEW.pipeline_stage = 'order' and OLD.pipeline_stage is distinct from 'order' then what := 'won and moved to Orders';
    elsif NEW.win_lose = 'lost' and OLD.win_lose is distinct from 'lost' then what := 'marked lost';
    elsif NEW.pipeline_stage = 'rfq' and OLD.pipeline_stage = 'lead' then what := 'qualified and moved to RFQs';
    elsif NEW.pipeline_stage = 'rfq' and NEW.rfq_status is distinct from OLD.rfq_status then what := 'RFQ status is now ' || replace(coalesce(NEW.rfq_status,''), '_', ' ');
    elsif NEW.pipeline_stage = 'lead' and NEW.lead_status is distinct from OLD.lead_status then what := 'lead status is now ' || replace(coalesce(NEW.lead_status,''), '_', ' ');
    end if;
  end if;

  -- assigned to someone else
  if NEW.assigned_to is not null and NEW.assigned_to <> actor
     and (TG_OP = 'INSERT' or NEW.assigned_to is distinct from OLD.assigned_to) then
    insert into notifications (user_id, kind, title, body, opportunity_id)
    values (NEW.assigned_to, 'assigned', actor_name || ' assigned you ' || label, null, NEW.id);
    owner_notified := true;
  end if;

  -- someone else moved a record you own
  if what is not null and NEW.assigned_to is not null and NEW.assigned_to <> actor and not owner_notified then
    insert into notifications (user_id, kind, title, body, opportunity_id)
    values (NEW.assigned_to, 'status', label || ': ' || what, 'Changed by ' || actor_name, NEW.id);
    owner_notified := true;
  end if;

  -- whoever the person who made the change reports to
  select reports_to into sup from profiles where id = actor;
  if sup is not null and sup <> actor and (TG_OP = 'INSERT' or what is not null)
     and not (sup = NEW.assigned_to and owner_notified) then
    insert into notifications (user_id, kind, title, body, opportunity_id)
    values (sup, 'team', actor_name || case when TG_OP = 'INSERT' then ' added ' else ' updated ' end || label || coalesce(': ' || what, ''), null, NEW.id);
  end if;

  return NEW;
exception when others then
  return NEW;   -- a notification problem must never block saving a record
end $$;

drop trigger if exists trg_notify_opportunity on opportunities;
create trigger trg_notify_opportunity after insert or update on opportunities
  for each row execute function notify_opportunity_change();

-- Follow-ups and offers that are due or overdue (one notification per record per day)
create or replace function generate_due_notifications()
returns int language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Karachi')::date;
  n int := 0; r record; cnt int;
begin
  for r in
    select o.id, o.assigned_to, o.follow_up_date, o.due_date, o.rfq_status,
           coalesce(nullif(o.project_name,''), nullif(o.item_product,''), 'an RFQ') || coalesce(' (' || c.name || ')', '') as label
    from opportunities o left join customers c on c.id = o.customer_id
    where o.assigned_to is not null and not o.archived and o.pipeline_stage = 'rfq'
      and coalesce(o.win_lose, 'pending') = 'pending'
  loop
    if r.follow_up_date is not null and r.follow_up_date <= today then
      insert into notifications (user_id, kind, title, body, opportunity_id, dedupe_key)
      values (r.assigned_to, 'due',
        'Follow-up ' || case when r.follow_up_date < today then 'overdue' else 'due today' end || ': ' || r.label,
        'Follow-up date ' || to_char(r.follow_up_date, 'DD/MM/YYYY'), r.id, 'fu:' || r.id || ':' || today)
      on conflict do nothing;
      get diagnostics cnt = row_count; n := n + cnt;
    end if;
    if r.due_date is not null and r.due_date <= today + 2 and r.rfq_status in ('not_started', 'in_progress') then
      insert into notifications (user_id, kind, title, body, opportunity_id, dedupe_key)
      values (r.assigned_to, 'due',
        'Offer ' || case when r.due_date < today then 'overdue' when r.due_date = today then 'due today' else 'due in ' || (r.due_date - today) || ' day(s)' end || ': ' || r.label,
        'Offer due date ' || to_char(r.due_date, 'DD/MM/YYYY'), r.id, 'od:' || r.id || ':' || today)
      on conflict do nothing;
      get diagnostics cnt = row_count; n := n + cnt;
    end if;
  end loop;
  delete from notifications where read_at is not null and read_at < now() - interval '60 days';
  return n;
end $$;
grant execute on function generate_due_notifications() to authenticated;

-- Run it every morning at 09:00 Pakistan time (04:00 UTC), if the pg_cron extension is available
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('crm-due-notifications', '0 4 * * *', 'select generate_due_notifications()');
exception when others then
  raise notice 'pg_cron not available; due notifications will be generated when someone opens the CRM';
end $$;

notify pgrst, 'reload schema';

select 'notifications table ok; trigger: ' || (select count(*) from pg_trigger where tgname = 'trg_notify_opportunity') as r
union all select 'pg_cron installed: ' || exists (select 1 from pg_extension where extname = 'pg_cron');
