# Builds the self-hosted copy of the CRM front end into selfhost\site\
#
#   * takes the normal ..\index.html (single source of truth, no duplicate to maintain)
#   * swaps every internet dependency (CDN scripts, Google Fonts) for the local files in vendor\
#   * moves the Supabase address + public key out of the code into config.js
#
# Usage (PowerShell, from this folder):
#   .\build-site.ps1 -SupabaseUrl https://crm.yourcompany.local -PublishableKey <key from the new server>
#
# Copy the resulting site\ folder to the server (Caddy serves it from /srv/crm).
param(
  [Parameter(Mandatory=$true)][string]$SupabaseUrl,
  [Parameter(Mandatory=$true)][string]$PublishableKey
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$app  = Split-Path -Parent $here
$site = Join-Path $here 'site'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# fresh output folder
if(Test-Path $site){ [System.IO.Directory]::Delete($site, $true) }
New-Item -ItemType Directory -Path $site | Out-Null

$html = [System.IO.File]::ReadAllText((Join-Path $app 'index.html'), $utf8)

# 1) Google Fonts -> local fonts
$fontPattern = '<link rel="preconnect" href="https://fonts.googleapis.com">\s*<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\s*<link href="https://fonts.googleapis.com/css2[^"]*" rel="stylesheet">'
if($html -notmatch $fontPattern){ throw 'Font links not found in index.html - build script needs updating.' }
$html = [regex]::Replace($html, $fontPattern, '<link rel="stylesheet" href="./vendor/fonts/fonts.css">')

# 2) CDN scripts -> local vendor files, plus config.js before them
$sbTag   = '<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>'
$xlsxTag = '<script src="https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js"></script>'
if(-not $html.Contains($sbTag) -or -not $html.Contains($xlsxTag)){ throw 'CDN script tags not found in index.html - build script needs updating.' }
$html = $html.Replace($sbTag, "<script src=`"./config.js`"></script>`n<script src=`"./vendor/supabase.js`"></script>")
$html = $html.Replace($xlsxTag, '<script src="./vendor/xlsx.full.min.js"></script>')

# 3) Supabase address/key come from config.js
$html = [regex]::Replace($html, "const SUPABASE_URL = '[^']*';", 'const SUPABASE_URL = window.CRM_CONFIG.SUPABASE_URL;')
$html = [regex]::Replace($html, "const SUPABASE_ANON_KEY = '[^']*';", 'const SUPABASE_ANON_KEY = window.CRM_CONFIG.SUPABASE_KEY;')
if($html -match "const SUPABASE_(URL|ANON_KEY) = '"){ throw 'Supabase constants were not replaced.' }

# 4) nothing may still point at the internet
foreach($bad in @('cdn.jsdelivr.net','fonts.googleapis.com','fonts.gstatic.com','unpkg.com','cdnjs.cloudflare.com')){
  if($html.Contains($bad)){ throw "index.html still references $bad" }
}

[System.IO.File]::WriteAllText((Join-Path $site 'index.html'), $html, $utf8)
$cfg = "window.CRM_CONFIG = { SUPABASE_URL: '$($SupabaseUrl.TrimEnd('/'))', SUPABASE_KEY: '$PublishableKey' };`n"
[System.IO.File]::WriteAllText((Join-Path $site 'config.js'), $cfg, $utf8)

# 5) static assets
foreach($f in 'sw.js','manifest.json','icon-192.png','icon-512.png','apple-touch-icon.png'){ Copy-Item (Join-Path $app $f) $site }
Copy-Item (Join-Path $app 'logos') (Join-Path $site 'logos') -Recurse
New-Item -ItemType Directory -Path (Join-Path $site 'vendor\fonts') -Force | Out-Null
Copy-Item (Join-Path $here 'vendor\supabase.js'), (Join-Path $here 'vendor\xlsx.full.min.js') (Join-Path $site 'vendor')
Copy-Item (Join-Path $here 'vendor\fonts\*.woff2'), (Join-Path $here 'vendor\fonts\fonts.css') (Join-Path $site 'vendor\fonts')

"Built $site"
Get-ChildItem $site -Recurse -File | Measure-Object -Property Length -Sum | ForEach-Object { "{0} files, {1:N0} KB" -f $_.Count, ($_.Sum/1KB) }
