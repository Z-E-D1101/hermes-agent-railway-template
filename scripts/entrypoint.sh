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

# Auto-detect provider dari env vars yang terisi
# Priority: Custom Endpoint > NVIDIA NIM > Mistral > GitHub > Groq > OpenRouter > Cohere > Cerebras > HuggingFace
PROVIDER=""
MODEL="${HERMES_MODEL:-Auto}"

if [ -n "${CUSTOM_ENDPOINT_URL:-}" ]; then
  PROVIDER="custom"
  BASE_URL="${CUSTOM_ENDPOINT_URL}"
  API_KEY="${CUSTOM_ENDPOINT_API_KEY:-}"
elif [ -n "${NVIDIA_NIM_API_KEY:-}" ]; then
  PROVIDER="nvidia-nim"
  BASE_URL="${NIM_BASE_URL:-https://integrate.api.nvidia.com/v1}"
  API_KEY="${NVIDIA_NIM_API_KEY}"
elif [ -n "${MISTRAL_API_KEY:-}" ]; then
  PROVIDER="mistral"
  BASE_URL="${MISTRAL_BASE_URL:-https://api.mistral.ai/v1}"
  API_KEY="${MISTRAL_API_KEY}"
elif [ -n "${GITHUB_TOKEN:-}" ]; then
  PROVIDER="github"
  BASE_URL="${GITHUB_BASE_URL:-https://models.inference.ai.azure.com}"
  API_KEY="${GITHUB_TOKEN}"
elif [ -n "${GROQ_API_KEY:-}" ]; then
  PROVIDER="groq"
  BASE_URL="${GROQ_BASE_URL:-https://api.groq.com/openai/v1}"
  API_KEY="${GROQ_API_KEY}"
elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
  PROVIDER="openrouter"
  BASE_URL="${OPENROUTER_BASE_URL:-https://openrouter.ai/api/v1}"
  API_KEY="${OPENROUTER_API_KEY}"
elif [ -n "${COHERE_API_KEY:-}" ]; then
  PROVIDER="cohere"
  BASE_URL="${COHERE_BASE_URL:-https://api.cohere.ai/v2}"
  API_KEY="${COHERE_API_KEY}"
elif [ -n "${CEREBRAS_API_KEY:-}" ]; then
  PROVIDER="cerebras"
  BASE_URL="${CEREBRAS_BASE_URL:-https://api.cerebras.ai/v1}"
  API_KEY="${CEREBRAS_API_KEY}"
elif [ -n "${HUGGINGFACE_API_KEY:-}" ]; then
  PROVIDER="huggingface-inference"
  BASE_URL="${HF_BASE_URL:-https://api-inference.huggingface.co/v1}"
  API_KEY="${HUGGINGFACE_API_KEY}"
fi

if [ -z "$PROVIDER" ]; then
  echo "[WARN] Tidak ada API key provider yang ter-set. Set salah satu:" >&2
  echo "  NVIDIA_NIM_API_KEY, MISTRAL_API_KEY, GITHUB_TOKEN, GROQ_API_KEY," >&2
  echo "  OPENROUTER_API_KEY, COHERE_API_KEY, CEREBRAS_API_KEY, HUGGINGFACE_API_KEY" >&2
  echo "[WARN] Menjalankan gateway tanpa LLM... (akan error saat chat)" >&2
else
  echo "[provider] Detected: $PROVIDER | model: $MODEL"
fi

# Tulis config.yaml baru dari awal
rm -f "$HERMES_HOME/config.yaml"

python3 - <<PY
import os, yaml

home = os.environ["HERMES_HOME"]
config_path = os.path.join(home, "config.yaml")

cfg = {
    "model": {
        "provider": os.environ.get("PROVIDER", "openrouter"),
        "default": os.environ.get("MODEL", "auto"),
    }
}

api_key = os.environ.get("API_KEY", "")
base_url = os.environ.get("BASE_URL", "")

if api_key:
    cfg["model"]["api_key"] = api_key
if base_url:
    cfg["model"]["base_url"] = base_url

os.makedirs(home, exist_ok=True)
with open(config_path, "w") as f:
    f.write(yaml.dump(cfg) + "\n")

print(f"[entrypoint] config.yaml written:")
print(f"  provider = {cfg['model']['provider']}")
print(f"  model    = {cfg['model']['default']}")
print(f"  base_url = {cfg['model'].get('base_url', 'default')}")
print(f"  api_key  = {'***' if api_key else '(not set)'}")
PY

exec "$@"