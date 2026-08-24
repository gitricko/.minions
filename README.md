# .minions

Portable bootstrap for a self-contained AI coding stack rooted at `~/.minions`.

```
firstmate ──dispatch──►  boot.sh  ──►  Pi-Agent (RPC)
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
               OmniRoute        ModelRelay       Hermes (opt-in)
            :20128/v1         :7352/v1        gateway
```

## Quick Start

```bash
# One-liner install (from minions.sh when published)
curl -fsSL https://minions.sh/install.sh | bash

# Or from this repo
./install.sh
```

Then start the stack:

```bash
~/.minions/boot.sh
```

You'll see:
```
==============================================
  .minions stack is UP

  ✅ omniroute   http://localhost:20128/v1
  ✅ modelrelay  http://localhost:7352/v1
  ✅ pi-agent    http://localhost:8080 (RPC mode)
  ✅ base_url    http://localhost:20128/v1

  READY FOR FIRSTMATE DISPATCH
==============================================
```

## Components

| Component | Role | Port | Notes |
|-----------|------|------|-------|
| **Pi-Agent** | Coding agent / firstmate crewmate harness | 8080 (RPC) | Standalone Bun binary |
| **OmniRoute** | LLM proxy, 350+ providers, quota-aware fallback | 20128 | Default proxy for Pi |
| **ModelRelay** | Lightweight OpenAI-compatible router | 7352 | Alternative proxy (`auto-fastest`) |
| **Hermes** | Self-improving generalist agent | 8081 (gateway) | Opt-in via `MINIONS_HERMES=on` |

## Usage

### Start the stack
```bash
~/.minions/boot.sh              # Interactive (blocks, Ctrl+C to stop)
~/.minions/boot.sh --daemon     # Detach after starting
```

### Stop the stack
```bash
~/.minions/stop.sh
```

### Check status
```bash
~/.minions/status.sh
```

### Switch LLM proxy
```bash
# Use ModelRelay instead of OmniRoute
export MINIONS_LLM_BASE_URL=http://localhost:7352/v1
~/.minions/boot.sh
```

### Enable Hermes gateway
```bash
export MINIONS_HERMES=on
~/.minions/boot.sh
```

### Custom install location
```bash
MINIONS_HOME=/custom/path ./install.sh --minions-home /custom/path
```

## Configuration

All configuration lives in `~/.minions/etc/`:

| File | Purpose |
|------|---------|
| `versions.env` | Pinned component versions (lockfile) |
| `minions.env` | Runtime config (ports, proxy choice, log level) |
| `pi.toml` | Pi-Agent config (RPC, LLM, workspace) |
| `omniroute.env` | OmniRoute overrides |
| `modelrelay.env` | ModelRelay overrides |
| `hermes.env` | Hermes provider/model config |

Key environment variables (in `minions.env`):

```bash
MINIONS_HOME=~/.minions              # Relocatable root
MINIONS_LLM_BASE_URL=http://localhost:20128/v1  # Default proxy for Pi
OMNIROUTE_PORT=20128                 # OmniRoute port
MODELRELAY_PORT=7352                 # ModelRelay port
PI_RPC_PORT=8080                     # Pi-Agent RPC port
MINIONS_HERMES=off                   # Set to 'on' to enable Hermes
MINIONS_DAEMON=off                   # Set to 'on' for detached mode
```

## Architecture

```
~/.minions/
├── install.sh          # Bootstrap installer
├── boot.sh             # Start the stack
├── stop.sh             # Stop the stack
├── status.sh           # Health check
├── bin/                # Symlinks to component CLIs (on PATH)
├── lib/                # Helper scripts + vendored runtimes
│   ├── node/           # Node.js >=22.22.2 (if system Node too old)
│   ├── uv/             # uv (for Hermes)
│   ├── pi/             # Pi-Agent standalone binary
│   ├── hermes/         # Hermes Agent (uv venv)
│   ├── omniroute/      # OmniRoute (npm)
│   └── modelrelay/     # ModelRelay (npm)
├── etc/                # Configuration templates
├── var/
│   ├── run/            # .pid files
│   ├── log/            # Service logs
│   └── cache/          # Downloaded tarballs
└── workspace/          # Scratch dir for agents
```

## Requirements

- **Linux** (x86_64, arm64) or **macOS** (Intel, Apple Silicon)
- **curl** or **wget** for downloads
- **bash** or **zsh** for PATH integration (optional)

The installer handles everything else:
- Vendors Node.js ≥22.22.2 if system version is too old (for OmniRoute/ModelRelay)
- Installs uv for Hermes (Python 3.11+ managed by uv)
- Downloads Pi-Agent as a Bun standalone binary (no Node needed for Pi)

## Development

Run tests:

```bash
# Install shellcheck
# Ubuntu/Debian: apt-get install shellcheck
# macOS: brew install shellcheck

./tests/test_install.sh
./tests/test_boot.sh
```

## License

MIT