-- MAQ CRM: rename the department "Transmission & Distribution" to "Electrical"
-- everywhere it is stored: on records, on people and on people's extra departments.
-- The matching change in the app is the DEPARTMENTS list in index.html. Safe to re-run.

update opportunities set department = 'Electrical'
  where department = 'Transmission & Distribution';

update profiles set department = 'Electrical'
  where department = 'Transmission & Distribution';

update profiles set extra_departments = array_replace(extra_departments, 'Transmission & Distribution', 'Electrical')
  where 'Transmission & Distribution' = any(extra_departments);

select 'records: ' || count(*) as r from opportunities where department = 'Electrical'
union all select 'people: ' || count(*) from profiles where department = 'Electrical'
union all select 'extra: ' || count(*) from profiles where 'Electrical' = any(extra_departments)
union all select 'old left: ' || count(*) from opportunities where department = 'Transmission & Distribution';
