# Plan: Replace ModelRelay with 9Router in .minions

## Overview
Migrate from `modelrelay` (npm package `modelrelay@1.22.1`, binary `modelrelay`, port 7352) to `9router` (npm package `9router@0.5.81`, binary `9router`, same port 7352).

This mirrors the changes in hermes-codespace PR #57 but adapted for the .minions repository structure.

---

## Files to Modify

### 1. Configuration & Version Files
| File | Changes |
|------|---------|
| `etc/deps.yaml` | Replace MODELRELAY entry with 9ROUTER entry (npm package `9router`, version `0.5.81`, bin `cli.js`) |
| `etc/versions.env` | Will be regenerated from deps.yaml; update MODELRELAY_VERSION → NINEROUTER_VERSION |
| `etc/models.json` | Replace `modelrelay` provider with `9router` provider; update fallback chains |

### 2. Core Scripts
| File | Changes |
|------|---------|
| `install.sh` | Replace `INSTALL_MODELRELAY` → `INSTALL_NINEROUTER`; `--no-modelrelay` → `--no-9router`; update all variable names, log messages, function calls |
| `boot.sh` | Replace ModelRelay service with 9Router service; update port variable names, service startup, log messages |
| `stop.sh` | Update service stop order: `modelrelay` → `9router` |
| `status.sh` | Replace ModelRelay checks with 9Router checks |
| `lib/npm_packages.sh` | Replace `ensure_modelrelay()` with `ensure_9router()`; update package name, binary path, version variable |

### 3. Config Templates
| File | Changes |
|------|---------|
| `etc/pi.toml` | Keep as-is (uses OMNIROUTE_PORT, generic base_url via MINIONS_LLM_BASE_URL) |
| `install.sh` (Hermes config generation) | Replace `modelrelay` provider config with `9router`; update fallback_providers |

### 4. Tests
| File | Changes |
|------|---------|
| `tests/test_install.sh` | Update all ModelRelay references to 9Router |
| `tests/test_boot.sh` | Update all ModelRelay references to 9Router |
| `tests/test_cli_integration.sh` | Update all ModelRelay references to 9Router |
| `tests/test_dts.sh` | Update all ModelRelay references to 9Router; update install flags |
| `tests/test_bootstrap.sh` | Update install flags |

### 5. Documentation & Wiki
| File | Changes |
|------|---------|
| `README.md` | Update badge, component list, configuration env vars |
| `docs/requirements-research.md` | Update all ModelRelay references |
| `docs/PLAN-v4.md` | Update table entries |
| `docs/IMPLEMENTATION-STATUS.md` | Update all ModelRelay references |
| `docs/PROPOSAL-skills-wiki-integration.md` | Update service list |
| `docs/PROPOSAL-self-update-dependencies.md` | Update references |
| `wiki/repository-analysis.md` | Update architecture diagrams, service tables |
| `wiki/codespace-playbook.md` | Update script descriptions |
| `wiki/github-actions-testing-plan.md` | Update health check commands |
| `wiki/persistent-knowledge-proposal.md` | Update binary checks |
| `memories/MEMORY.md` | Update component list |

### 6. Mnemon Seeds
| File | Changes |
|------|---------|
| `etc/mnemon-seed-pi.json` | Update entity references from `modelrelay` to `9router` |

---

## Variable/Constant Renaming Map

| Old | New |
|-----|-----|
| `MODELRELAY_VERSION` | `NINEROUTER_VERSION` |
| `MODELRELAY_PORT` | `NINEROUTER_PORT` (keep 7352) |
| `MODELRELAY_HOST` | `NINEROUTER_HOST` |
| `INSTALL_MODELRELAY` | `INSTALL_NINEROUTER` |
| `--no-modelrelay` | `--no-9router` |
| `ensure_modelrelay` | `ensure_9router` |
| `modelrelay` (service name) | `9router` |
| `modelrelay` (provider name) | `9router` |
| `ModelRelay` (display) | `9Router` |

---

## TDD Approach (per karpathy-coding-guidelines & tdd skills)

### RED Phase - Write Failing Tests First
1. For each modified test file, write a test that expects 9Router behavior
2. Run tests to confirm they fail (since implementation still uses modelrelay)

### GREEN Phase - Minimal Implementation
1. Make minimal changes to pass each test
2. Follow vertical tracer bullets: one test → one implementation at a time

### REFACTOR Phase
1. Clean up any duplication
2. Ensure consistent naming

---

## Step-by-Step Implementation Order

### Phase 1: Configuration & Version Files (Foundation)
1. ✅ `etc/deps.yaml` - Add 9router dependency, remove modelrelay
2. ✅ `etc/models.json` - Replace modelrelay provider with 9router
3. Run `scripts/sync-versions.sh` to regenerate `etc/versions.env`

### Phase 2: Core Installation Logic
4. ✅ `lib/npm_packages.sh` - Replace `ensure_modelrelay()` with `ensure_9router()`
5. ✅ `install.sh` - Update all variable references, flags, function calls

### Phase 3: Runtime Scripts
6. ✅ `boot.sh` - Replace ModelRelay service startup with 9Router
7. ✅ `stop.sh` - Update service stop list
8. ✅ `status.sh` - Replace ModelRelay health checks with 9Router

### Phase 4: Config Generation
9. ✅ `install.sh` (Hermes config section) - Update provider config

### Phase 5: Tests (RED-GREEN per file)
10. ✅ `tests/test_install.sh` - Write failing test for 9router, then fix
11. ✅ `tests/test_boot.sh` - Write failing test for 9router, then fix
12. ✅ `tests/test_cli_integration.sh` - Write failing test for 9router, then fix
13. ✅ `tests/test_dts.sh` - Write failing test for 9router, then fix
14. ✅ `tests/test_bootstrap.sh` - Update flags

### Phase 6: Documentation & Wiki
15. ✅ `README.md` - Update badge, component list, env vars
16. ✅ All docs/*.md files
17. ✅ All wiki/*.md files
18. ✅ `memories/MEMORY.md`
19. ✅ `etc/mnemon-seed-pi.json`

### Phase 7: Self-Check & Validation
20. ✅ `self-check.sh` - Update service port checks (keep port 7352, rename service)

### Phase 8: Verification
21. Run full test suite: `./tests/test_install.sh`, `./tests/test_boot.sh`, `./tests/test_cli_integration.sh`
22. Run DTS: `bash tests/test_dts.sh` (if Docker available)
23. Run self-check: `./self-check.sh`

---

## Key Technical Details

### 9Router Package Info
- **Package**: `9router@0.5.81` (npm)
- **Binary**: `cli.js` (exposed as `9router` via bin field)
- **Port**: 7352 (same as ModelRelay)
- **CLI**: `9router --host 127.0.0.1 --port 7352`

### Breaking Changes to Handle
1. Binary name: `modelrelay` → `9router`
2. Package name: `modelrelay` → `9router`
3. Bin path in package: `bin/modelrelay.js` → `cli.js`
4. Environment variable prefix: `MODELRELAY_` → `NINEROUTER_`
5. Service name in PID files: `modelrelay.pid` → `9router.pid`

### Non-Breaking (Keep Same)
- Port: 7352 (no change)
- Host: 127.0.0.1 (no change)
- OpenAI-compatible API at `/v1`
- Fallback chain logic (just provider name change)

---

## Verification Criteria

### Unit Tests Pass
- [ ] `./tests/test_install.sh` passes
- [ ] `./tests/test_boot.sh` passes
- [ ] `./tests/test_cli_integration.sh` passes
- [ ] `./tests/test_bootstrap.sh` passes

### Integration Tests Pass
- [ ] `bash tests/test_dts.sh` passes (full install→boot→chat→stop)

### Health Checks Pass
- [ ] `./self-check.sh` passes (all services, models, persistence)
- [ ] `./status.sh` shows 9router ✅

### Manual Verification
- [ ] `~/.minions/bin/9router --version` works
- [ ] `curl http://localhost:7352/v1/models` returns models
- [ ] Hermes config shows `provider: 9router` in fallback_providers
- [ ] Pi models.json has 9router provider with correct baseUrl

---

## Rollback Plan
If critical issues arise:
1. `git stash` changes
2. Run original tests to confirm baseline works
3. Re-apply changes incrementally with more granular TDD cycles

---

## Notes
- Follow karpathy guidelines: surgical changes only, no drive-by refactoring
- Follow TDD: test first, watch it fail, minimal code to pass, refactor
- Update seed.json entries for Mnemon persistence if new important facts discovered
- Verify CI lint-check passes for modified shell scripts