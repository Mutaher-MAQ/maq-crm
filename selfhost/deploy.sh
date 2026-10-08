#!/usr/bin/env bash
# Pull the latest CRM code from GitHub and publish it on this server.
# The server only makes OUTBOUND connections to github.com; GitHub never connects in.
#
# One-time setup:
#   sudo apt-get install -y git rsync perl
#   sudo cp crm.env.example /opt/crm-proxy/crm.env   # then fill in the address + key
#   sudo cp deploy.sh /usr/local/bin/crm-deploy && sudo chmod +x /usr/local/bin/crm-deploy
# Run by hand:   sudo crm-deploy
# Or every 15 minutes (so a push to GitHub goes live by itself):
#   sudo crontab -e   ->   */15 * * * *  /usr/local/bin/crm-deploy >> /var/log/crm-deploy.log 2>&1
set -euo pipefail
REPO="${REPO:-https://github.com/Mutaher-MAQ/maq-crm.git}"
SRC="${SRC:-/opt/crm-src}"
WEB="${WEB:-/srv/crm}"
ENVF="${ENVF:-/opt/crm-proxy/crm.env}"

[ -d "$SRC/.git" ] || git clone --depth 1 "$REPO" "$SRC"
before="$(git -C "$SRC" rev-parse HEAD)"
git -C "$SRC" pull --ff-only -q
after="$(git -C "$SRC" rev-parse HEAD)"
if [ "$before" = "$after" ] && [ -f "$WEB/index.html" ] && [ -z "${FORCE:-}" ]; then
  exit 0   # nothing new (set FORCE=1 to rebuild anyway, e.g. after changing crm.env)
fi

set -a; . "$ENVF"; set +a     # provides SUPABASE_URL and SUPABASE_KEY
out="$(mktemp -d)"
SITE_OUT="$out" bash "$SRC/selfhost/build-site.sh"
mkdir -p "$WEB"
rsync -a --delete "$out"/ "$WEB"/
rm -rf "$out"
echo "$(date) deployed $(git -C "$SRC" rev-parse --short HEAD)"
