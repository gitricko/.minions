# User profile — seeded from upstream, trimmed of codespace-only facts.

## Who

- Developer / engineer. Ships code, runs CI, reads docs.
- Works primarily on the `.minions` project (self-contained AI stack installer).
- Prefers concise, direct answers. No filler, no re-explaining what was asked.
- Acts first when the task is clear; asks only when genuinely ambiguous.
- Wants root-cause fixes, not symptom patches. Verifies with real test/CI output.

## Workflow

- Prefers TDD (tests before code; watch tests fail first) and Karpathy's coding
  discipline (minimal, surgical, verified-by-real-output).
- Uses PRs to main for changes; commits per logical phase (reviewable units).
- Docker Test Shell (dts) for clean-container integration tests.
- Wants the curl|bash one-liner install to actually work (oh-my-zsh style).

## Conventions

- Shell scripts: `sh`/`bash` with `set -euo pipefail` where appropriate.
- Exit-code discipline: 0 = ok, 1 = warnings, 2 = critical (self-check).
- Knowledge: 15 hermes-codespace skills ported; wiki + mnemon seed are in-progress.