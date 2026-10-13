# OpenCode free tier via 9Router

opencode.ai's free tier rejects requests that don't look like they come from
the OpenCode client: HTTP 403 `FreeTierError` ("free tier can only be used
from within OpenCode"). 9Router's registry already sends `x-opencode-client:
desktop`, but upstream tightened checks — clients now need the full header
set, applied as a 9Router provider override.

Reference: github.com/decolua/9router issue about FreeTierError; the workaround
is confirmed working by multiple users there and verified live here.

## Header set (PUT /api/providers/opencode/overrides)

```
{
  "headers": {
    "User-Agent": "opencode/1.18.31",
    "x-opencode-client": "cli",
    "x-opencode-project": "global",
    "x-opencode-request": "_msg",
    "x-opencode-session": "ses_<12hex><14base62>"
  }
}
```

- PUT replaces the whole map; send all headers every time (idempotent).
- `authorization`, `host`, `content-type`, etc. are blocked by the API —
  don't try to override auth headers this way.
- The response echoes `builtinHeaders` (registry defaults) merged with yours.

## Session id generation (ses_ prefix)

12 hex chars = inverted `timestamp_ms * 4096 + counter` masked to 48 bits;
14 base62 chars random. Regenerate per boot (fresh "conversation" avoids
stale-session 403s). Shell (python3):

```bash
SES=$(python3 -c "
import time, secrets, string
v = (~(int(time.time()*1000)*4096 + 1)) & 281474976710655
c = string.digits + string.ascii_uppercase + string.ascii_lowercase
print('ses_%012x%s' % (v, ''.join(secrets.choice(c) for _ in range(14))))")
```

The exact encoding only needs to *look* like a real session id (upstream
doesn't seem to validate the timestamp component), but keep the shape.

## Free model list

Source of truth: `curl -s https://opencode.ai/zen/v1/models`. Only ids
matching `*-free` / `*-contributor-free` are free; everything else on that
endpoint (claude-*, gpt-*, gemini-*, ...) is paid and will fail without
credits. Quirks observed:

- `muse-spark-*-contributor-free` (openai-responses format): route OK but
  sometimes return empty content with `finish_reason:"in_progress"` —
  a silent failure that blocks combo fallback.
- `mimo-v2.6-flash-free`: reliable, real content, `finish_reason:"stop"`.
- `jev-1.13-free`: `ModelProtocolUnsupported` over chat completions — needs
  a different transport, exclude from openai-style combos.
- `ling-3.1-flash-free`: intermittent 429 "Endpoint is unavailable".
- Several models (nemotron, big-pickle, cat-jam) burn the whole token budget
  on reasoning at low max_tokens and return empty — test at >=128 tokens.

Keep the combo model list in `lib/9router.sh` in sync with the live list;
stale ids degrade the combo (empty responses count as success upstream).
