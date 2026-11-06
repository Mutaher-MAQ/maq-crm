-- MAQ CRM: give every deal an automatic opportunity number like MAQ-2026-0042.
-- The number is created when the record is first saved (as a lead, RFQ or order) and
-- stays with the deal as it moves through the pipeline. Existing records with a blank
-- number are numbered once, oldest first. Numbers already typed in by hand are left alone.
-- Run once (it creates the trigger).

create sequence if not exists opp_number_seq;

with n as (
  select id, row_number() over (order by created_at, id) as rn
  from opportunities where opportunity_number is null
)
update opportunities o
set opportunity_number = 'MAQ-' || to_char(o.created_at, 'YYYY') || '-' || lpad(n.rn::text, 4, '0')
from n where n.id = o.id;

select setval('opp_number_seq', greatest((select count(*) from opportunities), 1));

create or replace function opp_assign_number()
returns trigger language plpgsql security definer as $$
begin
  if new.opportunity_number is null or new.opportunity_number = '' then
    new.opportunity_number := 'MAQ-' || to_char(coalesce(new.created_at, now()), 'YYYY') || '-' || lpad(nextval('opp_number_seq')::text, 4, '0');
  end if;
  return new;
end $$;

create trigger opp_number before insert on opportunities
  for each row execute function opp_assign_number();

notify pgrst, 'reload schema';
