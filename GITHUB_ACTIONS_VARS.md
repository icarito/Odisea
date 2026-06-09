# GitHub Actions Variables

## Secrets (Configure in Repo Settings > Secrets and variables > Actions)

- `ODISEA_BRIDGE_TOKEN`: Shared secret token for Central/Peer authentication.
- `DEPLOY_HOST`: Target deployment host (e.g., `35.182.238.36`).
- `DEPLOY_USER`: SSH user for deployment (e.g., `ubuntu`).
- `DEPLOY_KEY`: SSH private key for deployment access.

## Environment Variables

```env
# Central Configuration
CENTRAL_HTTP_PORT=5003
CENTRAL_CACHE_TTL=120
CENTRAL_STORE_GHOSTS=true
CENTRAL_GHOSTS_DIR=./data/ghosts
CENTRAL_GHOSTS_MAX_BYTES=104857600
CENTRAL_STATIC_DIR=./dashboard/dist
CENTRAL_AUTH_MAX_FAILS=8
CENTRAL_AUTH_FAIL_WINDOW=60
CENTRAL_AUTH_LOCKOUT=300

# Peer Configuration
PEER_PORT=4999
ANNA_HOST=127.0.0.1
ANNA_PORT=5000
CENTRAL_WS_URL=ws://35.182.238.36:5003/ws
```

## Workflow Step: Build React Dashboard

Add this step to your GitHub Actions workflow before deploying or packaging:

```yaml
- name: Build React Dashboard
  run: |
    cd dashboard
    npm ci
    npm run build
    mkdir -p ../static/dashboard
    cp -r dist/* ../static/dashboard/
```

## HTML5 / WS Anonymous Connection Note

The Central server accepts WebSocket connections without a token in "anonymous" mode.
- If a client connects without a valid `BRIDGE_TOKEN` during handshake, it is assigned a `peer_id` prefixed with `html5-`.
- Heartbeats from these clients are still processed and stored, allowing HTML5 clients to report telemetry without full authentication.
- Ensure `ODISEA_BRIDGE_TOKEN` is properly set in production to prevent unauthorized access to authenticated endpoints.
