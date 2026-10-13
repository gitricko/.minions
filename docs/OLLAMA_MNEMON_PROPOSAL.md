# Proposal: Ollama + Mnemon Knowledge Graph in .minions

## Executive Summary

**The Ollama badge in README is misleading** — Mnemon doesn't require Ollama. The mnemon binary supports **two embedding protocols**:
- **Ollama** (default: `http://localhost:11434`, model `nomic-embed-text`)
- **OpenAI-compatible** (e.g., OmniRoute `:20128/v1`, 9Router `:7352/v1`)

Since `.minions` already installs **OmniRoute** and **9Router** (both OpenAI-compatible), we can configure mnemon to use them for embeddings **without installing Ollama at all**.

---

## Issue #53: Ollama badge advertised but not installed

**Current state:** README badge claims Ollama `0.33.2` (stale; latest is `v0.35.0`), but Ollama is absent from `deps.yaml`, `versions.env`, `install.sh`, and `~/.minions/bin/`.

**Root cause:** The badge was added aspirationaly; the mnemon plugin README mentions "optional vector recall via Ollama" but the plugin itself doesn't configure it.

**Two paths forward:**

### Path A (Recommended): Use OmniRoute/9Router for embeddings — **no Ollama needed**
- Configure mnemon via env vars to use existing OpenAI-compatible proxies
- Drop the Ollama badge (or replace with "Embeddings: OmniRoute/9Router")
- Cleaner, lighter, leverages existing infrastructure

### Path B: Install Ollama properly as optional component
- Add `OLLAMA` to `etc/deps.yaml` (pinned, `sha_source: shasums` against release `sha256sum.txt`)
- Handle `.tar.zst` assets (zstd support in `lib/download.sh`)
- Darwin is single universal binary (`ollama-darwin.tgz`) → schema adjustment
- Add `lib/ollama.sh` install script + `boot.sh` service management
- Add `self-check.sh` health check (binary, API `:11434`, model present, embed round-trip)
- `--no-ollama` flag for CI cost control (~1.5 GB + 275 MB model)

---

## Issue #47: "Make .minions's mnemon knowledge graph working"

**What's missing:** The mnemon plugin is installed and Hermes is pointed at it, but **embeddings are not configured**. Without embeddings:
- `mnemon recall` works (graph-based, no vectors)
- `mnomen embed` fails (no embedding provider)
- Semantic/vector recall unavailable

**Required config (in `~/.hermes/config.yaml` or env):**
```yaml
# For OmniRoute (OpenAI-compatible)
MNEMON_EMBED_ENDPOINT: "http://localhost:20128/v1"
MNEMON_EMBED_PROTOCOL: "openai"
MNEMON_EMBED_MODEL: "<embedding-model-name>"  # needs investigation
MNEMON_EMBED_API_KEY: "<omniroute-key>"       # if required
```

Or for Ollama (if Path B chosen):
```yaml
MNEMON_EMBED_ENDPOINT: "http://localhost:11434"
MNEMON_EMBED_PROTOCOL: "ollama"
MNEMON_EMBED_MODEL: "nomic-embed-text"
```

**Where to apply:** In `lib/install-mnemon-plugin.sh` or a new `lib/mnemon-config.sh`, sourced by `install.sh` and `boot.sh`.

---

## Concrete Proposal: Minimal Working Mnemon + Embeddings

### 1. Fix the knowledge graph (issue #47) — **do this first, no Ollama needed**

**Files to change:**
- `lib/install-mnemon-plugin.sh` → add embedding config after plugin install
- `lib/mnemon.sh` → ensure mnemon binary is on PATH for `mnemon embed` command
- `install.sh` → source new config step

**Code sketch (`lib/install-mnemon-plugin.sh` addition):**
```sh
# After: log_info "mnemon plugin installed"

# Configure embedding provider for mnemon (prefers OmniRoute if running)
configure_mnemon_embeddings() {
    local hermes_config="${HOME}/.hermes/config.yaml"

    # Check if OmniRoute is running on default port
    if curl -s --max-time 2 "http://localhost:20128/v1/models" >/dev/null 2>&1; then
        log_info "Configuring mnemon embeddings via OmniRoute (OpenAI-compatible)"
        # Write to mnemon.json (plugin reads this on init)
        cat > "${HOME}/.hermes/mnemon.json" <<EOF
{
  "store": "default",
  "embedding_endpoint": "http://localhost:20128/v1",
  "embedding_protocol": "openai",
  "embedding_model": "text-embedding-3-small"
}
EOF
        return 0
    fi

    # Fallback: check 9Router
    if curl -s --max-time 2 "http://localhost:7352/v1/models" >/dev/null 2>&1; then
        log_info "Configuring mnemon embeddings via 9Router (OpenAI-compatible)"
        cat > "${HOME}/.hermes/mnemon.json" <<EOF
{
  "store": "default",
  "embedding_endpoint": "http://localhost:7352/v1",
  "embedding_protocol": "openai",
  "embedding_model": "text-embedding-3-small"
}
EOF
        return 0
    fi

    log_warn "No embedding provider (OmniRoute/9Router) detected; mnemon will work without vector recall"
}

configure_mnemon_embeddings
```

**Verification:** After install, `mnomen embed --status` should show coverage stats (not "Ollama not available").

### 2. Decide on Ollama badge (issue #53)

**If Path A (use OmniRoute):**
- Delete Ollama badge from README
- Update issue #53: "Won't fix — embeddings work via OmniRoute/9Router"

**If Path B (install Ollama):**
- Implement full deps.yaml entry + install + boot + self-check
- Keep badge, now managed by sync-readme-badges.sh
- Add `--no-ollama` flag to install.sh/boot.sh

---

## My Recommendation: **Path A (OmniRoute embeddings)**

| Factor | Path A (OmniRoute) | Path B (Ollama) |
|--------|-------------------|-----------------|
| New code | ~20 lines in existing plugin install | ~300 lines (deps, install, boot, check, zstd) |
| CI cost | Zero (uses existing services) | +1.5 GB download + model pull + service |
| Disk | Zero | ~2 GB |
| Maintenance | None | Version bumps, zstd, darwin universal |
| User value | Vector recall works immediately | Local embeddings (offline capable) |
| README badge | Remove (replace or drop) | Keep, now accurate |

**Offline/local-first** is the only argument for Path B. If that's a requirement, do Path B. Otherwise Path A delivers the feature (vector recall) with existing components.

---

## Next Steps

1. **Confirm direction** (A or B)
2. **If A:** I'll implement embedding config in `install-mnemon-plugin.sh`, test `mnomen embed --status`, drop Ollama badge, close #53
3. **If B:** I'll implement full Ollama integration per .minions patterns (deps.yaml → sync-versions → sync-badges → CI guard)
4. Either way: verify mnemon knowledge graph works end-to-end (close #47)

---

## Appendix: Mnemon Embedding Configuration Details

From `mnemon/internal/memory/embed/`:
```go
// Env vars (all optional, have defaults)
MNEMON_EMBED_ENDPOINT      // default: "http://localhost:11434"
MNEMON_EMBED_MODEL         // default: "nomic-embed-text"
MNEMON_EMBED_PROTOCOL      // "ollama" | "openai" (auto-detect: /v1 path → openai)
MNEMON_EMBED_API_KEY       // for openai protocol
MNEMON_EMBED_DIMENSIONS    // optional override
```

**Protocol auto-detect:** If `MNEMON_EMBED_ENDPOINT` path ends in `/v1` → OpenAI protocol. Our OmniRoute (`:20128/v1`) and 9Router (`:7352/v1`) qualify.

**Available command:** `mnemon embed --status` shows embedding coverage; `mnemon embed --all` backfills.

**Plugin config file:** `~/.hermes/mnemon.json` (read by `MnemonMemoryProvider.initialize()`). Supports `embedding_endpoint`, `embedding_protocol`, `embedding_model`, `embedding_api_key`.

---

**Question for you:** Path A or B? (Or C: do A now, B later behind a flag?)