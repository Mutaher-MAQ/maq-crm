-- MAQ CRM: tick option "MAQINT FZC" (our offshore company) on leads, RFQs and orders.
-- Safe to re-run.
alter table opportunities add column if not exists maqint_fzc boolean not null default false;
notify pgrst, 'reload schema';
