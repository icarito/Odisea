# Auto-deploy webhook

Lets a push to `main` on GitHub trigger a pull + redeploy on
`odisea.educa.juegos`, replacing the manual SSH → `git pull` → `deploy.sh` flow.

## How it works

1. GitHub sends a `push` webhook to `POST /webhook/deploy` on the central server
   (port 5003, behind the gateway at `https://odisea.educa.juegos`).
2. `odisea_central.py` validates the HMAC-SHA256 signature
   (`X-Hub-Signature-256`) using the deploy secret.
3. If it's a push to `main`, it spawns `~/odisea-deploy/deploy.sh` **detached**
   (so the deploy can restart central without killing the script).
4. `deploy.sh` hard-resets a **dedicated clone** (not the interactive workspace)
   to `origin/main`, builds the dashboard, backs up and migrates SQLite, copies
   `odisea_central.py` + dashboard assets, and restarts the service.

## Server setup (one time)

```bash
ssh ubuntu@odisea.educa.juegos
mkdir -p ~/odisea-deploy
git clone git@github.com:icarito/Odisea.git ~/odisea-deploy/Odisea
cp ~/odisea-deploy/Odisea/scripts/deploy-webhook/deploy.sh ~/odisea-deploy/deploy.sh
chmod +x ~/odisea-deploy/deploy.sh
```

The central process must be able to run the script. By default it looks for
`~/odisea-deploy/deploy.sh` (override with `DEPLOY_SCRIPT`). Deploy output is
appended to `~/odisea-deploy/deploy.log`.

Because `deploy.sh` ends with `sudo systemctl restart odisea-central.service`
and the webhook runs non-interactively, grant a passwordless sudo rule scoped to
exactly that command:

```bash
echo 'ubuntu ALL=(root) NOPASSWD: /usr/bin/systemctl restart odisea-central.service' \
  | sudo tee /etc/sudoers.d/odisea-deploy
sudo chmod 440 /etc/sudoers.d/odisea-deploy
```

The runtime layout is: the systemd unit runs `~/anna-central/odisea_central.py`
(WorkingDirectory `~/anna-central`, env from `/etc/odisea-central.env`). The
deploy clone lives separately at `~/odisea-deploy/Odisea`, so pulling never
touches the interactive `~/.openclaw` workspace.

### Environment (optional)

Set on the central process if defaults don't fit:

| Var | Default | Meaning |
| --- | --- | --- |
| `DEPLOY_WEBHOOK_SECRET` | `BRIDGE_TOKEN` | HMAC secret; empty disables the endpoint |
| `DEPLOY_SCRIPT` | `~/odisea-deploy/deploy.sh` | script to run on push |
| `DEPLOY_BRANCH` | `main` | branch whose pushes trigger deploy |

And on `deploy.sh` itself:

| Var | Default | Meaning |
| --- | --- | --- |
| `REPO_DIR` | `~/odisea-deploy/Odisea` | dedicated deploy clone |
| `REPO_URL` | `git@github.com:icarito/Odisea.git` | repo cloned on first run |
| `BRANCH` | `main` | branch deployed by the script |
| `DEPLOY_DIR` | `~/anna-central` | runtime directory |
| `SERVICE` | `odisea-central.service` | systemd service to restart |
| `DB_PATH` | `$DEPLOY_DIR/data/ghosts.db` | SQLite database to back up/migrate |
| `BACKUP_DIR` | `$DEPLOY_DIR/data/backups` | SQLite backup destination |

Before restarting the service, the script creates a SQLite backup using the
SQLite backup API, runs idempotent schema setup for `hotzones`, and verifies
`PRAGMA integrity_check` plus required columns. Any failure aborts the deploy
before files are copied/restarted, leaving the backup in place.

## GitHub setup

Repo → Settings → Webhooks → Add webhook:

- **Payload URL:** `https://odisea.educa.juegos/webhook/deploy`
- **Content type:** `application/json`
- **Secret:** the bridge token (same value as `DEPLOY_WEBHOOK_SECRET`)
- **Events:** "Just the push event"

GitHub's initial `ping` returns `{"ok": true, "pong": true}` so you can confirm
the wiring from the webhook's "Recent Deliveries" tab.

## Test manually

```bash
# from anywhere, with the secret in $SECRET:
BODY='{"ref":"refs/heads/main"}'
SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"
curl -X POST https://odisea.educa.juegos/webhook/deploy \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: $SIG" \
  -H "Content-Type: application/json" \
  -d "$BODY"
# then watch ~/odisea-deploy/deploy.log on the server
```
