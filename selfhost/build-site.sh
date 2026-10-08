#!/usr/bin/env bash
# Linux version of build-site.ps1: builds the offline CRM front end from ../index.html.
#   SUPABASE_URL=https://crm.example.com SUPABASE_KEY=<publishable key> ./build-site.sh
# Output goes to ./site (or $SITE_OUT). Used by deploy.sh on the server.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$(dirname "$here")"
site="${SITE_OUT:-$here/site}"
: "${SUPABASE_URL:?set SUPABASE_URL}"
: "${SUPABASE_KEY:?set SUPABASE_KEY}"

rm -rf "$site"
mkdir -p "$site/vendor/fonts"

# swap internet dependencies for local files; Supabase address/key come from config.js
perl -0pe '
  s{<link rel="preconnect" href="https://fonts\.googleapis\.com">\s*<link rel="preconnect" href="https://fonts\.gstatic\.com" crossorigin>\s*<link href="https://fonts\.googleapis\.com/css2[^"]*" rel="stylesheet">}{<link rel="stylesheet" href="./vendor/fonts/fonts.css">};
  s{<script src="https://cdn\.jsdelivr\.net/npm/\@supabase/supabase-js\@2"></script>}{<script src="./config.js"></script>\n<script src="./vendor/supabase.js"></script>};
  s{<script src="https://cdn\.jsdelivr\.net/npm/xlsx\@0\.18\.5/dist/xlsx\.full\.min\.js"></script>}{<script src="./vendor/xlsx.full.min.js"></script>};
  s{const SUPABASE_URL = \x27[^\x27]*\x27;}{const SUPABASE_URL = window.CRM_CONFIG.SUPABASE_URL;};
  s{const SUPABASE_ANON_KEY = \x27[^\x27]*\x27;}{const SUPABASE_ANON_KEY = window.CRM_CONFIG.SUPABASE_KEY;};
' "$app/index.html" > "$site/index.html"

# refuse to publish anything that still points at the internet or still has the old constants
for bad in cdn.jsdelivr.net fonts.googleapis.com fonts.gstatic.com unpkg.com cdnjs.cloudflare.com; do
  if grep -q "$bad" "$site/index.html"; then echo "index.html still references $bad: build script needs updating" >&2; exit 1; fi
done
if grep -Eq "const SUPABASE_(URL|ANON_KEY) = '" "$site/index.html"; then echo "Supabase constants were not replaced" >&2; exit 1; fi
grep -q 'window.CRM_CONFIG.SUPABASE_URL' "$site/index.html" || { echo "config hook missing" >&2; exit 1; }

printf "window.CRM_CONFIG = { SUPABASE_URL: '%s', SUPABASE_KEY: '%s' };\n" "${SUPABASE_URL%/}" "$SUPABASE_KEY" > "$site/config.js"

for f in sw.js manifest.json icon-192.png icon-512.png apple-touch-icon.png; do cp "$app/$f" "$site/"; done
cp -r "$app/logos" "$site/logos"
cp "$here/vendor/supabase.js" "$here/vendor/xlsx.full.min.js" "$site/vendor/"
cp "$here"/vendor/fonts/*.woff2 "$here/vendor/fonts/fonts.css" "$site/vendor/fonts/"
echo "Built $site ($(find "$site" -type f | wc -l) files)"
