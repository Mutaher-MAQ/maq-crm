#!/usr/bin/env bash
# Copies the CRM data from the Supabase CLOUD project into the LOCAL self-hosted database.
# Run it on the new server, in the folder that contains post-import.sql.
# Nothing in the cloud project is changed (it only reads). Do a full TEST run first.
#
#   export CLOUD_DB_URL='postgresql://postgres.<ref>:<password>@<pooler-host>:5432/postgres'
#   ./migrate-from-cloud.sh
#
# Get the connection string from the cloud dashboard: Connect > Session pooler.
# Keep the password out of shell history/chat; IT enters it directly on the server.
set -uo pipefail
: "${CLOUD_DB_URL:?Set CLOUD_DB_URL to the cloud project's database connection string}"
PG_IMAGE="${PG_IMAGE:-postgres:17}"        # must be the same or newer major version than the cloud database
DB_CONTAINER="${DB_CONTAINER:-supabase-db}"
OUT="${OUT:-./cloud-export}"
mkdir -p "$OUT"

dump() { docker run --rm "$PG_IMAGE" pg_dump "$CLOUD_DB_URL" "$@"; }
local_sql() { docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres "$@"; }

echo "1/5 exporting the CRM schema + data (public)..."
dump --no-owner --no-privileges --schema=public > "$OUT/public.sql" || { echo "export failed"; exit 1; }

echo "2/5 exporting login accounts (auth.users, auth.identities)..."
dump --data-only --no-owner --no-privileges --table=auth.users --table=auth.identities > "$OUT/auth.sql" || { echo "export failed"; exit 1; }

# Triggers are switched off while loading so nothing double-fires (e.g. profile creation, department auto-tag).
echo "3/5 importing login accounts (must go first: profiles refer to them)..."
{ echo "SET session_replication_role = replica;"; cat "$OUT/auth.sql"; } | local_sql > "$OUT/import-auth.log" 2>&1
echo "    errors: $(grep -c 'ERROR' "$OUT/import-auth.log" || true)  (see $OUT/import-auth.log)"

echo "4/5 importing CRM schema + data..."
{ echo "SET session_replication_role = replica;"; cat "$OUT/public.sql"; } | local_sql > "$OUT/import-public.log" 2>&1
echo "    errors: $(grep -c 'ERROR' "$OUT/import-public.log" || true)  (see $OUT/import-public.log)"

echo "5/5 re-creating triggers, live updates and permissions..."
local_sql < "$(dirname "$0")/post-import.sql" > "$OUT/post-import.log" 2>&1
echo "    errors: $(grep -c 'ERROR' "$OUT/post-import.log" || true)  (see $OUT/post-import.log)"

echo
echo "Row counts on the NEW server (compare each with the cloud project):"
local_sql -t -A -F ' | ' -c "
select 'auth.users', count(*) from auth.users union all
select 'profiles', count(*) from public.profiles union all
select 'customers', count(*) from public.customers union all
select 'principals', count(*) from public.principals union all
select 'contacts', count(*) from public.contacts union all
select 'opportunities', count(*) from public.opportunities union all
select 'opportunity_principals', count(*) from public.opportunity_principals union all
select 'tasks', count(*) from public.tasks union all
select 'activities', count(*) from public.activities;"
