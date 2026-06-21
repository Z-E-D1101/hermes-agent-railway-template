#!/bin/sh
set -e

HERMES_HOME="${HERMES_HOME:-/data/hermes}"
INSTALL_DIR="/opt/hermes"
export HERMES_HOME
export HERMES_ALLOW_ROOT_GATEWAY=1
export PATH="/opt/hermes/.venv/bin:/root/.local/bin:${PATH}"
export VIRTUAL_ENV="/opt/hermes/.venv"

mkdir -p \
  "$HERMES_HOME/cron" \
  "$HERMES_HOME/sessions" \
  "$HERMES_HOME/logs" \
  "$HERMES_HOME/hooks" \
  "$HERMES_HOME/memories" \
  "$HERMES_HOME/skills" \
  "$HERMES_HOME/skins" \
  "$HERMES_HOME/plans" \
  "$HERMES_HOME/workspace" \
  "$HERMES_HOME/home"

if [ ! -f "$HERMES_HOME/.env" ] && [ -f "$INSTALL_DIR/.env.example" ]; then
  cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
fi

if [ ! -f "$HERMES_HOME/config.yaml" ] && [ -f "$INSTALL_DIR/cli-config.yaml.example" ]; then
  cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
fi

if [ ! -f "$HERMES_HOME/SOUL.md" ] && [ -f "$INSTALL_DIR/docker/SOUL.md" ]; then
  cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

if [ -d "$INSTALL_DIR/skills" ]; then
  python3 "$INSTALL_DIR/tools/skills_sync.py" || true
fi

# Optional: join Tailscale tailnet so Railway can reach private services on your PC.
# Required Railway vars:
#   TAILSCALE_AUTHKEY=tskey-auth-...
# Optional:
#   TAILSCALE_HOSTNAME=hermes-railway
#   TAILSCALE_EXTRA_ARGS=--accept-routes
if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
  echo "Starting Tailscale..."
  mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale
  tailscaled \
    --tun=userspace-networking \
    --socks5-server=localhost:1055 \
    --outbound-http-proxy-listen=localhost:1055 \
    --state=/var/lib/tailscale/tailscaled.state \
    >/tmp/tailscaled.log 2>&1 &

  for i in $(seq 1 20); do
    tailscale status >/dev/null 2>&1 && break
    sleep 0.5
  done

  tailscale up \
    --authkey="${TAILSCALE_AUTHKEY}" \
    --hostname="${TAILSCALE_HOSTNAME:-hermes-railway}" \
    ${TAILSCALE_EXTRA_ARGS:-} || {
      echo "Tailscale failed. Log:" >&2
      cat /tmp/tailscaled.log >&2 || true
      exit 1
    }

  # userspace-networking has no kernel routes; apps must use the local HTTP proxy.
  export HTTP_PROXY="${HTTP_PROXY:-http://localhost:1055}"
  export HTTPS_PROXY="${HTTPS_PROXY:-http://localhost:1055}"
  export ALL_PROXY="${ALL_PROXY:-http://localhost:1055}"
  export NO_PROXY="${NO_PROXY:-127.0.0.1,localhost,::1}"

  echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || true)"
fi

# --- Local OpenAI-compatible endpoint (hardcoded) ---
# Endpoint & model sudah di-hardcode di sini. Kamu hanya perlu set:
#   HERMES_API_KEY=... di Railway Variables.
HERMES_PROVIDER="${HERMES_PROVIDER:-custom}"
HERMES_MODEL="${HERMES_MODEL:-Auto}"
HERMES_BASE_URL="${HERMES_BASE_URL:-http://100.64.73.96:20128/v1}"
HERMES_API_KEY="${HERMES_API_KEY:-}"

# Tulis langsung config.yaml agar gateway baca provider + model yang benar
# (hermes config set kadang tidak reliable jika dijalankan setelah startup)
if [ -n "$HERMES_BASE_URL" ] || [ -n "$HERMES_API_KEY" ] || [ "$HERMES_PROVIDER" != "openrouter" ]; then
  python3 - <<'PY'
import os, yaml, json
home = os.environ["HERMES_HOME"]
config_path = os.path.join(home, "config.yaml")
cfg = {}
try:
    if os.path.exists(config_path):
        with open(config_path) as f:
            cfg = yaml.safe_load(f.read()) or {}
except Exception:
    cfg = {}
if "model" not in cfg:
    cfg["model"] = {}
cfg["model"]["provider"] = os.environ.get("HERMES_PROVIDER", "custom")
cfg["model"]["default"] = os.environ.get("HERMES_MODEL", "Auto")
cfg["model"]["base_url"] = os.environ.get("HERMES_BASE_URL", "")
api_key = os.environ.get("HERMES_API_KEY", "")
if api_key:
    cfg["model"]["api_key"] = api_key
with open(config_path, "w") as f:
    f.write(yaml.dump(cfg) + "\n")
print(f"[entrypoint] wrote config.yaml with provider={cfg['model']['provider']}, model={cfg['model']['default']}, base_url={cfg['model']['base_url']}", flush=True)
PY
fi

exec "$@"
