-- MAQ CRM: rename the department "Instrumentation & Commissioning" to "Instrumentation & Control"
-- everywhere it is stored: on records, on people and on people's extra departments.
-- The matching change in the app is the DEPARTMENTS list in index.html. Safe to re-run.

update opportunities set department = 'Instrumentation & Control'
  where department = 'Instrumentation & Commissioning';

update profiles set department = 'Instrumentation & Control'
  where department = 'Instrumentation & Commissioning';

update profiles set extra_departments = array_replace(extra_departments, 'Instrumentation & Commissioning', 'Instrumentation & Control')
  where 'Instrumentation & Commissioning' = any(extra_departments);

select 'records: ' || count(*) as r from opportunities where department = 'Instrumentation & Control'
union all select 'people: ' || count(*) from profiles where department = 'Instrumentation & Control'
union all select 'extra: ' || count(*) from profiles where 'Instrumentation & Control' = any(extra_departments)
union all select 'old left: ' || count(*) from opportunities where department = 'Instrumentation & Commissioning';
