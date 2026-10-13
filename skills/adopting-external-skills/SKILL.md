---
name: adopting-external-skills
description: Import external skills into the Codespace tree, adapted.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [skills, importing, mattpocock, codespace, adaptation]
    related_skills: [codespace-persistent-symlinks, ci-lint-check]
---

# Adopting External Skills

Bring a skill from an external/upstream source (e.g. mattpocock/skills, an
obra-style repo) into the user's committable Codespace skills tree
(`skills/`). The rule is *adapt, don't copy 1:1* — strip what
won't work, graft the genuinely novel ideas into an existing base skill when
one already covers the territory, and make the result Hermes-shaped and
git-persisted.

## When to Use

- User points at an upstream skill (URL or repo) and asks "how would you structure this in our skills? / copy it?"
- A new external skill notes the execution technique beats what an existing local skill already documents.

## Decide: new skill or graft into an existing one

**Check for an existing local skill covering the same territory FIRST**
(`skills_list` + `skill_view`). If one exists and is solid, GRAFT the novel
distinctive content into it — do not create a narrow sibling. If the upstream
turns out to be *less* complete than the local skill, say so and fold in only
what the local one genuinely lacks.

Split-coordinator skills ("call these two sub-skills") are usually dead ends:
merge their behavior into one active skill under a single name rather than
shipping a routing stub.

## Procedure

1. **Fetch the upstream raw content.** Use the `raw.githubusercontent.com`
   URL, NOT the github blob URL — the blob URL returns only page chrome
   (repo/path metadata), never the file body. `web_extract` on the raw URL
   works; for small files (<2KB, and whenever the extract backend times out)
   fall back to `terminal(command="curl -s <raw-url>")`.
2. **List the skill's full file set** so you don't miss support files:
   `terminal(command="curl -s https://api.github.com/repos/<owner>/<repo>/contents/<path>")`
   and grep for `"name"` at every level (SKILL.md + references/ + agents/
   configs). Fetch the referenced templates/formats too — they are often the
   most reusable part.
3. **Strip what is not Hermes.** Remove `agents/openai.yaml` (OpenAI-Codex
   config, no Hermes equivalent), and frontmatter fields that mean nothing
   here like `disable-model-invocation`. Keep `name` + `description` as the
   core trigger; description should be self-contained within ~57 chars.
4. **Adapt content.** Graft distinctive, reusable ideas from the upstream
   into the base skill. Deep templates/formats (an ADR format, a glossary
   format, a mocking guideline) go in `references/<topic>.md` under the skill
   dir, pointed to from SKILL.md — don't inline bulk in the body.
5. **Place in the committable tree.** Write to `skills/<name>/`
   (symlinked to `~/.hermes/skills/codespace/`), NOT `~/.hermes/skills/`
   directly — the symlinked dir is what is git-tracked and survives rebuilds.
6. **Verify the CI gates** mirror our lint-check: frontmatter opens with `---`
   on byte 0, closes within the first 20 lines, and has a `name:` field.
   `markdownlint` is often not installed locally — say the structural gates
   passed but the line-length rule is unverified locally, and watch for long
   upstream lines on commit (CI will flag them).

## Duplicate-name collision

If a Hermes-managed copy of the same skill already lives elsewhere (e.g.
`~/.hermes/skills/<category>/<name>/`), the loader sees two same-named skills
and auto-triggering becomes ambiguous. When the new git-tracked copy is the
authoritative one, the fix is to DELETE the stale Hermes-managed copy so only
the persisted version remains. The repo path is unaffected (it was never
tracked). Do not leave both to fight over the loader.

## Pitfalls

- **Blob URL instead of raw URL.** `github.com/.../blob/main/...` returns page
  chrome, not content. Always hit `raw.githubusercontent.com/.../main/...`.
- **Extract backend rate/timeout flakiness.** `web_extract`/the search backend
  intermittently times out or returns an error on keyless fetch. For short
  files, `curl -s` the raw URL is the reliable path.
- **Skill-format mismatch (grill-with-docs case).** An upstream "coordinator"
  skill with `disable-model-invocation: true` is a two-line router — merging it
  into the skill it routes to removes a dead hop.
- **Grafting skips the target's own layers.** When extending a local base
  skill, remember the local one may carry its own rich scaffolding
  (rationalizations, checklists, Hermes integration). Preserve all of it and
  ADD the upstream idea — do not let the shorter upstream file crowd it out.
- **The repo persistence symlink.** Confirm `~/.hermes/skills/codespace` still
  points at `skills` before writing, and verify the new dir
  appears under it, not just in an un-symlinked category path.

## Verification

- `head -1` == `---`; a `^---$` within lines 2-20; a `^name:` in frontmatter — all PASS.
- New skill dir resolves under `~/.hermes/skills/codespace/` (symlinked), i.e. committable.
- `skills_list` shows the new skill (note: the loader cache may delay it ~30s until next session).
- No stale same-named sibling remains to collide in the loader.
- Every upstream support file either landed in `references/` or was deliberately dropped (and why).