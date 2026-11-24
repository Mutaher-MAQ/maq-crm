-- MAQ CRM: service principals (e.g. Bureau Veritas) - no goods, no shipment, no LC.
-- 1) principals.business_type: 'product' (default) or 'service'
-- 2) opportunities.service_line: BV "Product Line" (Certification, Industry, B&I, AFC ...)
-- 3) shipment_status also allows 'in_progress' (service delivery: Pending / In Progress / Completed)
-- 4) Bureau Veritas is marked as a service principal; its "Bureau Veritas - <line>" project names move to service_line.
-- Safe to re-run.
alter table principals add column if not exists business_type text not null default 'product';
alter table principals drop constraint if exists principals_business_type_check;
alter table principals add constraint principals_business_type_check check (business_type in ('product','service'));

alter table opportunities add column if not exists service_line text;

alter table opportunities drop constraint if exists opportunities_shipment_status_check;
alter table opportunities add constraint opportunities_shipment_status_check check (shipment_status in ('pending','in_progress','done'));

update principals set business_type = 'service' where name ilike '%bureau veritas%';

update opportunities o
   set service_line = nullif(btrim(regexp_replace(o.project_name, '^Bureau Veritas\s*-\s*', '', 'i')), ''),
       project_name = null
 where o.project_name ~* '^Bureau Veritas\s*-\s*.+'
   and o.service_line is null;

notify pgrst, 'reload schema';
