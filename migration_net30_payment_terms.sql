-- MAQ CRM: add "Net 30" as a payment-terms option. Safe to re-run.
do $$
declare c text;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.opportunities'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%payment_terms%'
  loop
    execute format('alter table public.opportunities drop constraint %I', c);
  end loop;
end $$;
alter table public.opportunities add constraint opportunities_payment_terms_check
  check (payment_terms in ('LC','CAD','Advance','Net 30'));
notify pgrst, 'reload schema';
