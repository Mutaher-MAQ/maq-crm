-- MAQ CRM: attach files (PO copies, RFQs, drawings, etc.) to any opportunity or order.
-- Files go in a PRIVATE storage bucket; nobody can open them without signing in, and only
-- people who can see the record can see its files. Directors can view and download but not
-- upload or delete. Max 10 MB per file. Safe to re-run.

-- 1. Does this signed-in person have access to this record? (same rules as the record itself)
create or replace function can_see_opp_id(opp uuid)
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from opportunities o
    where o.id = opp and can_see_opp_full(o.id, o.department, o.assigned_to, o.po_principal_id)
  )
$$;

-- 2. File list (one row per uploaded file)
create table if not exists opportunity_files (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references opportunities(id) on delete cascade,
  file_name text not null,
  storage_path text not null,
  size_bytes bigint,
  content_type text,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists opportunity_files_opp_idx on opportunity_files(opportunity_id);
alter table opportunity_files enable row level security;

drop policy if exists "files read" on opportunity_files;
drop policy if exists "files insert" on opportunity_files;
drop policy if exists "files delete" on opportunity_files;
create policy "files read" on opportunity_files for select
  using (can_see_opp_id(opportunity_id));
create policy "files insert" on opportunity_files for insert
  with check (can_see_opp_id(opportunity_id) and is_not_director());
create policy "files delete" on opportunity_files for delete
  using (can_see_opp_id(opportunity_id) and is_not_director());

-- 3. Private bucket for the files themselves, stored as <opportunity id>/<file>
insert into storage.buckets (id, name, public, file_size_limit)
values ('po-files', 'po-files', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

drop policy if exists "po files read" on storage.objects;
drop policy if exists "po files insert" on storage.objects;
drop policy if exists "po files delete" on storage.objects;
create policy "po files read" on storage.objects for select
  using (bucket_id = 'po-files' and can_see_opp_id(((storage.foldername(name))[1])::uuid));
create policy "po files insert" on storage.objects for insert
  with check (bucket_id = 'po-files' and can_see_opp_id(((storage.foldername(name))[1])::uuid) and is_not_director());
create policy "po files delete" on storage.objects for delete
  using (bucket_id = 'po-files' and can_see_opp_id(((storage.foldername(name))[1])::uuid) and is_not_director());

-- 4. Live updates: other open screens see new files straight away
do $$ begin
  alter publication supabase_realtime add table opportunity_files;
exception when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';
