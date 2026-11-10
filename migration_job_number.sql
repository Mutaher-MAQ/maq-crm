-- MAQ CRM: Job Number on orders (entered by hand on the order form).
-- Safe to re-run.

alter table opportunities add column if not exists job_number text;

notify pgrst, 'reload schema';
