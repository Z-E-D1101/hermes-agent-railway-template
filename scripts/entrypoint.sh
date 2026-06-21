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

# Optional: make Hermes use your local OpenAI-compatible endpoint via Tailscale.
# Example Railway vars:
#   HERMES_PROVIDER=custom
#   HERMES_MODEL=openai/gpt-oss-20b  # or whatever your local server exposes
#   HERMES_BASE_URL=http://100.64.73.96:20128/v1
#   HERMES_API_KEY=local-not-needed
[ -n "${HERMES_PROVIDER:-}" ] && hermes config set model.provider "$HERMES_PROVIDER" || true
[ -n "${HERMES_MODEL:-}" ] && hermes config set model.default "$HERMES_MODEL" || true
[ -n "${HERMES_BASE_URL:-}" ] && hermes config set model.base_url "$HERMES_BASE_URL" || true
[ -n "${HERMES_API_KEY:-}" ] && hermes config set model.api_key "$HERMES_API_KEY" || true

exec "$@"
