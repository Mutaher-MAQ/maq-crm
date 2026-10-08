# MAQ CRM: move to the office server (runbook for IT)

Goal: run the CRM database, login, API **and** web page on the Dell R730, published at
**https://crm.maqint.com** through the FortiGate. The data never leaves the building. GitHub stays as the code
repository; nothing is served from it, and no CDN or cloud service is needed at run time.

```
 staff (office / phone) ──https 443──▶ FortiGate VIP ──▶ DMZ VM (Ubuntu, Hyper-V)
                                                           ├─ Caddy :80/:443  (Let's Encrypt certificate)
                                                           │    ├─ /rest /auth /realtime ─▶ Supabase (Docker, 127.0.0.1:8000)
                                                           │    └─ everything else ───────▶ CRM web page (/srv/crm)
 IT admin PC ──http──▶ <vm-ip>:8000 (Supabase Studio admin screen, IT subnet only, never published)
 GitHub ◀── server pulls the code (outbound only, deploy.sh)
```

## How it is published: decision
| Method | Verdict |
|---|---|
| **A. FortiGate VIP + own domain `crm.maqint.com` + Let's Encrypt (chosen)** | Data stays end to end on your own equipment: only your server holds the certificate and sees the traffic. Uses the FortiGate protections you already pay for (IPS, geo-blocking, DoS policy). No third party and no DNS migration; you just add one DNS record. Needs inbound 80/443. |
| B. VIP + a `*.fortiddns.com`-style name | Works, but a vendor-owned name looks untrustworthy in invites/emails and can't be moved. Use it only as the *target* of a CNAME if the public IP is dynamic (below). |
| C. Cloudflare Tunnel | No inbound ports and hides the server's IP, but Cloudflare decrypts all traffic in transit (conflicts with "data stays private"), the `maqint.com` DNS zone has to move to Cloudflare (risk to company email records), and you depend on a third party for uptime. Reasonable fallback if inbound ports can never be opened. |

**DNS:** at whoever hosts `maqint.com` DNS add `crm  CNAME  <your-ddns-name>` (or an `A` record if you have a static IP). Nothing
else about `maqint.com` changes. Let's Encrypt then issues the certificate for `crm.maqint.com` automatically.

## What you need
| Item | Notes |
|---|---|
| Hyper-V VM | Generation 2, **Ubuntu Server 24.04 LTS**, 4 vCPU, 8 GB RAM (fixed, not dynamic), 100 GB disk. Secure Boot template: *Microsoft UEFI Certificate Authority*. Static IP in a **DMZ** VLAN. |
| Public name | `crm.maqint.com` -> your public address (see DNS above) |
| FortiGate | A VIP and one inbound policy (see "FortiGate" below) |
| Mail account for system emails | e.g. a Microsoft 365 mailbox with SMTP AUTH enabled. Used for invites and password resets. |
| Backup target | A second machine or network share, mounted on the VM. |

Windows Server 2019 cannot run Supabase's Linux containers well, which is why this is an Ubuntu VM on Hyper-V.

## Phase 1: Build a TEST VM first
Do everything below on a throwaway VM and prove it works before touching production. The live cloud CRM keeps running
the whole time; the migration only *reads* from it. A test VM can use a test name such as `crm-test.maqint.com`.

## Phase 2: Install Supabase (official self-hosting package)
Follow Supabase's current guide: https://supabase.com/docs/guides/self-hosting/docker
Pin the version so the install is repeatable (this is what the guide showed when this was written):
```sh
sudo apt-get update && sudo apt-get install -y git rsync perl docker.io docker-compose-v2
git clone --depth 1 --branch self-hosted/v0.8.2 https://github.com/supabase/supabase
mkdir supabase-project && cp -rf supabase/docker/. supabase-project
cd supabase-project && cp .env.example .env
sh utils/generate-keys.sh
sh utils/add-new-auth-keys.sh
```
Edit `.env` (IT chooses and stores all secrets; do not send them in chat or email):
```
SUPABASE_PUBLIC_URL=https://crm.maqint.com
API_EXTERNAL_URL=https://crm.maqint.com/auth/v1
SITE_URL=https://crm.maqint.com
POSTGRES_PASSWORD=<letters and digits only>
DASHBOARD_PASSWORD=<long; letters and digits, at least one letter>
DISABLE_SIGNUP=true            # IMPORTANT, see below
SMTP_ADMIN_EMAIL=crm@maqint.com
SMTP_HOST=smtp.office365.com
SMTP_PORT=587
SMTP_USER=...
SMTP_PASS=...
SMTP_SENDER_NAME=MAQ CRM
```
> **`DISABLE_SIGNUP=true` is critical once the server is public.** In the CRM, every signed-in user can read all customers,
> contacts and principals. If strangers could register themselves, they would see that data. Accounts must only be created
> by an admin invite. Verify it in the test checklist (try to sign up with a new address: it must be refused).
> Also lower the sign-in rate limits in `.env` if the package exposes them, and keep email confirmation on.

Then `sh run.sh start`, wait until `docker compose ps` shows everything healthy, and run `sh run.sh secrets` to see the
**publishable key**. You need it in Phase 3.

Bind the Supabase gateway to localhost only for the CRM path (Caddy is the only thing on the network), and use ufw:
allow 80 and 443 from anywhere (the FortiGate decides who really gets here), 8000 only from `127.0.0.1` and the IT admin
subnet, SSH from IT only. **Postgres (5432) is never exposed.**

## Phase 3: Front end + HTTPS
```sh
sudo mkdir -p /opt/crm-proxy /srv/crm
# put Caddyfile + docker-compose.proxy.yml + crm.env.example (as crm.env) in /opt/crm-proxy
# crm.env: SUPABASE_URL=https://crm.maqint.com  and  SUPABASE_KEY=<publishable key from Phase 2>
cd /opt/crm-proxy && docker compose -f docker-compose.proxy.yml up -d
sudo cp deploy.sh /usr/local/bin/crm-deploy && sudo chmod +x /usr/local/bin/crm-deploy
sudo crm-deploy            # clones the repo from GitHub, builds the offline web page, publishes it to /srv/crm
```
The web page makes **no internet requests**: every library and font is bundled (`vendor/`).
Check: `https://crm.maqint.com` shows the sign-in page, and `curl -I https://crm.maqint.com/auth/v1/health` answers.

Windows alternative for building by hand: `selfhost\build-site.ps1 -SupabaseUrl ... -PublishableKey ...`, then copy `site\` to `/srv/crm`.

## FortiGate
Nothing existing changes. Add:
1. **Virtual IP:** external = the WAN address, map to the VM's DMZ address, port forwarding **TCP 443 -> 443** and **TCP 80 -> 80**
   (80 only for the certificate check and the redirect to https). Do **not** forward 8000, 5432 or 22.
2. **DDNS** (if the public IP is dynamic): keep your existing FortiGuard DDNS or provider; `crm.maqint.com` is a CNAME to it.
3. **One inbound policy:** WAN -> DMZ, destination = that VIP, services HTTPS + HTTP, NAT off.
   Attach **IPS** (e.g. the `protect_http_server` sensor) and AV. Use certificate inspection only (not deep inspection) on this policy.
   Optionally a **Web Application Firewall** profile if the model is licensed, a **geo-IP source restriction** to the countries your
   staff actually work from, and a **DoS policy** on the WAN interface for this VIP (SYN/connection limits).
4. **DMZ -> LAN: deny.** The VM must not be able to reach internal systems. It only needs *outbound* access to:
   `github.com`, `registry-1.docker.io` / `*.docker.io` / `ghcr.io` / `production.cloudflare.docker.com` (image pulls),
   Ubuntu package mirrors, `smtp.office365.com:587`, DNS and NTP. (Let's Encrypt needs outbound 443 to `acme-v02.api.letsencrypt.org`.)
5. Log the VIP policy and send logs to your usual collector; alert on repeated failed sign-ins.

### Claude and GitHub: nothing changes
- **Claude** (the Chrome extension) runs in *your* browser. It never needs to reach the server from outside; it reaches
  Studio at `http://<vm-ip>:8000` from a PC on the IT subnet, exactly as it reaches the Supabase dashboard today. No inbound
  rule is needed for it, and your existing outbound policies for Claude stay untouched. If SSL deep inspection is on for staff
  PCs, keep `github.com` and Claude/Anthropic hostnames in the exemption list as they are now.
- **GitHub:** pushes still come from the PC (the sign-in you did is saved on it). The *server* pulls with `deploy.sh`
  (outbound HTTPS only). No webhook, no inbound GitHub rule. With the cron line in `deploy.sh`, a push to GitHub goes live
  on the server within 15 minutes, exactly like today's Pages deploy. Database changes (SQL) are run in the local Studio SQL
  editor instead of the cloud dashboard (validate in the test that this works the same way).
- The repo stays public or private, as you decide; it contains no secrets. `crm.env` and `.env` are only on the server.

## Phase 4: Copy the data (TEST run)
On the server, in the `selfhost` folder (needs `post-import.sql` next to the script):
```sh
export CLOUD_DB_URL='postgresql://postgres.<ref>:<password>@<pooler-host>:5432/postgres'   # cloud dashboard > Connect > Session pooler
chmod +x migrate-from-cloud.sh && ./migrate-from-cloud.sh
```
It exports from the cloud (read only), imports accounts first, then the CRM schema and data, then re-creates the new-login
trigger, live-update settings and permissions. It prints row counts for each table: **compare them with the cloud project**.
Review the three `*.log` files in `cloud-export/`. A few harmless "already exists" messages are normal; anything else
should be understood before going on.

Existing passwords keep working (hashes are copied). Everyone has to sign in once more because the new server has its own
signing secret.

## Phase 5: Test checklist (all on the test server)
- [ ] Sign in as admin; dashboard numbers match the cloud CRM
- [ ] Sign in as Talha (manager), Abid (employee), Daniyal: each sees only what the rules allow
- [ ] Orders & POs department buttons work; Excel export works
- [ ] Create, edit, drag an RFQ; a second browser sees it update live (live updates)
- [ ] Qualify a lead: it moves to RFQs; a new RFQ with no department picks up the assignee's department
- [ ] Invite a new user: the email arrives; they can set a password and sign in
- [ ] Password reset email arrives and works
- [ ] **Self sign-up is refused** (try registering a brand-new address on the sign-in API)
- [ ] From outside the network (a phone on mobile data): sign-in page loads over a valid https certificate
- [ ] From outside: ports 8000, 5432 and 22 are closed; `https://crm.maqint.com/` shows no Supabase admin screen
- [ ] Phone: "Add to home screen" installs it
- [ ] Supabase Studio opens from the IT PC at `http://<vm-ip>:8000` and NOT from a normal office PC
- [ ] `sudo crm-deploy` picks up a new commit pushed to GitHub
- [ ] Restore test: run `backup.sh`, restore that file into a blank test stack with `pg_restore`, check counts

## Phase 6: Production cutover (a quiet evening or weekend)
1. Build the production VM the same way (or promote the tested one); the production name is `crm.maqint.com`.
2. Tell staff the CRM is read-only for the evening. Stop using the cloud CRM.
3. Run `migrate-from-cloud.sh` again for the final copy; check row counts.
4. Point the DNS record at the production address; confirm the certificate is issued.
5. Everyone signs in again. Spot-check as in Phase 5. Staff then use `https://crm.maqint.com` (reinstall the phone shortcut).
6. **Keep the cloud project untouched for two weeks as the fallback**, then delete it. Rollback = repoint the DNS record and
   use the old GitHub Pages address.

## Phase 7: Backups (before go-live)
```sh
sudo cp backup.sh /usr/local/bin/crm-backup && sudo chmod +x /usr/local/bin/crm-backup
sudo crontab -e     # add:  30 1 * * *  COPY_TO=/mnt/backup-share /usr/local/bin/crm-backup >> /var/log/crm-backup.log 2>&1
```
Keeps 30 days locally and copies each backup to a second location. Test a restore every quarter. Also snapshot the VM
before every upgrade.

## Phase 8: Day-to-day
- **CRM page updates:** automatic via `crm-deploy` (cron). Force a rebuild with `sudo FORCE=1 crm-deploy`.
- **Update Supabase:** follow Supabase's *Updating* guide; always rehearse on the test VM and snapshot first. Updates
  are frequent; pin a version and move on purpose.
- **Monitoring:** alert if port 443 stops answering, the certificate is within 14 days of expiry, or the disk passes 80%.

## Things to validate on the test VM (not yet tested by the author)
The web page build (Windows and Linux scripts) was tested, including with all internet access blocked. The server side below
follows Supabase's published guide and standard PostgreSQL practice, but was **not** run end to end, so confirm each on the test VM:
1. Gateway paths `/rest/v1`, `/auth/v1`, `/realtime/v1` work through Caddy, including live updates (WebSockets).
2. The data import runs with no unexpected errors (auth schema version differences are the likeliest snag).
3. The publishable key from `run.sh secrets` works with the CRM (`supabase-js`); if the server also offers a classic
   `anon` key, either may be used in `crm.env`.
4. `DISABLE_SIGNUP=true` is the right variable name for this package version and really blocks self-registration.
5. SMTP sign-in to Microsoft 365 (SMTP AUTH must be enabled for the mailbox).
6. Studio works at `http://<vm-ip>:8000` while the public URL in `.env` is the https name. If Studio's calls fail, IT can
   open Studio through an SSH tunnel to port 8000 instead. The SQL editor automation Claude uses needs to be re-checked there.

## Security checklist
- [ ] Only 80/443 forwarded; VM in a DMZ with DMZ -> LAN denied
- [ ] `DISABLE_SIGNUP=true` confirmed by test; strong admin invites only
- [ ] `.env` and `crm.env` readable only by root/IT; secrets stored in IT's password vault
- [ ] Studio (8000) limited to the IT subnet; never in the Caddyfile
- [ ] IPS profile on the VIP policy; geo restriction and DoS policy considered
- [ ] Automatic OS security updates on; VM in IT's patching routine
- [ ] Backups copied off the server and restore-tested
- [ ] Strong passwords required when inviting users; consider turning on multi-factor for admin accounts
