# skills/

One directory per skill, mounted read-only at the user level in every project.

## File format

`skills/<name>/SKILL.md` — YAML frontmatter between `---` fences, then Markdown instructions.
Supporting files (references, scripts, licenses) sit beside it in the same directory and are
referenced from the body by relative path.

```markdown
---
name: my-skill
description: Use when <situation>. <What it does.>
---

# My skill

Instructions for Claude...
```

## Frontmatter Claude Code expects

| Key | Required | Notes |
|---|---|---|
| `name` | yes | Must equal the directory name. `^[a-z0-9][a-z0-9-]{0,63}$`. |
| `description` | yes | How Claude decides whether to load the skill. Say *when* to use it, not just what it is. The body is only read after this matches, so everything needed to trigger it belongs here. |
| `disable-model-invocation` | no | `true` → user-invocable only (`/my-skill`), never auto-loaded. For side effects. |
| `user-invocable` | no | `false` → Claude-only, no slash command. For background knowledge. |
| `allowed-tools` | no | Restrict tool access, e.g. `Read, Grep, Glob`. |
| `disallowed-tools` | no | The inverse: deny specific tools. |
| `tools` | no | Older spelling of `allowed-tools`, still used by some marketplace skills. |
| `model` | no | Override the model while the skill is active. |
| `context` | no | `fork` runs the skill in an isolated subagent. |
| `agent` | no | Which agent type to use when forked. |
| `argument-hint` | no | Shown after the name while typing, for user-invocable skills. |
| `license` | no | SPDX id. |
| `version` | no | Free-form, e.g. `0.1.0`. |
| `metadata` | no | Nested mapping of whatever you like. |
| `hide` | no | Keep the skill out of the menu. |

`./build.sh check` requires `name` and `description` and **warns** on any key not in that list.
A warning does not fail the run: Claude Code adds keys faster than the validator can track, so
an unrecognized key is a reason to look for a typo, not a reason to block a deploy. Once you
have confirmed a new key is real, add it to `SKILL_KEYS` in `tools/check.py` (the comment above
it cites where each current key is documented).

`comments` is not a Claude Code key — it is a local convention, allowed but unused. Local
changes to a vendored skill belong in `THIRD_PARTY.md`, so the skill keeps diffing cleanly
against upstream.

## Vendored skills

`show-me`, `ub-mode`, and `mags-manifest-design` come from upstream repos; see `THIRD_PARTY.md`
for source, pinned commit, license, and local changes. Do not reformat their `SKILL.md` files —
that makes re-syncing with upstream painful.
