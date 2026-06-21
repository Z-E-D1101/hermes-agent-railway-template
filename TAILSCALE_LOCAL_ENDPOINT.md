# Railway -> Local endpoint via Tailscale

Goal: Hermes on Railway uses your local OpenAI-compatible endpoint:

```txt
http://localhost:20128/v1
```

Railway cannot reach your computer's `localhost`. Use Tailscale:

```txt
Railway container -> Tailscale -> your PC 100.64.73.96:20128
```

## 1. On your PC

Your current Tailscale IP:

```txt
100.64.73.96
```

Check endpoint is listening:

```bash
curl http://127.0.0.1:20128/v1/models
```

Make the service listen on LAN/Tailscale, not only loopback.

Good:

```txt
0.0.0.0:20128
```

Bad:

```txt
127.0.0.1:20128 only
```

If using llama.cpp:

```bash
llama-server --host 0.0.0.0 --port 20128 ...
```

If using Ollama OpenAI-compatible endpoint, set bind host before start:

```bash
export OLLAMA_HOST=0.0.0.0:20128
ollama serve
```

Test from another tailnet device if possible:

```bash
curl http://100.64.73.96:20128/v1/models
```

Firewall allow only Tailscale interface:

```bash
sudo ufw allow in on tailscale0 to any port 20128 proto tcp
```

## 2. Create Tailscale auth key

Tailscale admin console:

```txt
https://login.tailscale.com/admin/settings/keys
```

Create auth key:

- Ephemeral: yes
- Reusable: yes (optional)
- Pre-approved: yes (if available)
- Expiration: short if possible

Copy key: `tskey-auth-...`

## 3. Railway variables

Set these vars in Railway project:

```env
TAILSCALE_AUTHKEY=tskey-auth-...
TAILSCALE_HOSTNAME=hermes-railway
HERMES_PROVIDER=custom
HERMES_MODEL=<your-model-name>
HERMES_BASE_URL=http://100.64.73.96:20128/v1
HERMES_API_KEY=local-not-needed
```

Also set normal Hermes/gateway vars, e.g. Telegram/API key vars.

## 4. Deploy

This repo was modified to:

- install `tailscale` in Dockerfile
- start `tailscaled` in userspace mode in `scripts/entrypoint.sh`
- join your tailnet with `TAILSCALE_AUTHKEY`
- set HTTP proxy env vars so app traffic can reach tailnet IPs
- set Hermes model config from `HERMES_PROVIDER`, `HERMES_MODEL`, `HERMES_BASE_URL`, `HERMES_API_KEY`

## 5. Verify in Railway logs

Look for:

```txt
Starting Tailscale...
Tailscale IP: 100.x.y.z
```

Then verify Hermes can call:

```txt
http://100.64.73.96:20128/v1
```

## Notes

`localhost` inside Railway = Railway container, not your PC.

Use your PC's Tailscale IP instead:

```txt
http://100.64.73.96:20128/v1
```

Tailscale userspace networking does not create kernel routes. This template sets:

```env
HTTP_PROXY=http://localhost:1055
HTTPS_PROXY=http://localhost:1055
ALL_PROXY=http://localhost:1055
NO_PROXY=127.0.0.1,localhost,::1
```

So HTTP clients can reach `100.x.y.z` tailnet addresses through tailscaled.
