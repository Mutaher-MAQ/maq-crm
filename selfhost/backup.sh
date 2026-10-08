#!/usr/bin/env bash
# Nightly backup of the whole CRM database (accounts, data, security rules).
# Install:  sudo cp backup.sh /usr/local/bin/crm-backup && sudo chmod +x /usr/local/bin/crm-backup
# Schedule: sudo crontab -e   ->   30 1 * * *  /usr/local/bin/crm-backup >> /var/log/crm-backup.log 2>&1
#
# DEST      where backups are kept on this server
# COPY_TO   OPTIONAL second location (a mounted network share or another machine). A backup that only
#           lives on the same server is not a backup: set this.
set -euo pipefail
DEST="${DEST:-/var/backups/crm}"
KEEP_DAYS="${KEEP_DAYS:-30}"
COPY_TO="${COPY_TO:-}"
DB_CONTAINER="${DB_CONTAINER:-supabase-db}"

mkdir -p "$DEST"
file="$DEST/crm-$(date +%F-%H%M).dump"
docker exec "$DB_CONTAINER" pg_dump -U postgres -d postgres -Fc > "$file"
[ -s "$file" ] || { echo "$(date) backup is empty, aborting" >&2; rm -f "$file"; exit 1; }
echo "$(date) wrote $file ($(du -h "$file" | cut -f1))"

if [ -n "$COPY_TO" ]; then
  cp "$file" "$COPY_TO"/ && echo "$(date) copied to $COPY_TO"
fi
find "$DEST" -name 'crm-*.dump' -mtime +"$KEEP_DAYS" -delete
