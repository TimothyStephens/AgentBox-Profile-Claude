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
| `disable-model-invocation` | no | `true` makes the skill user-invocable only (`/my-skill`), never auto-loaded. |
| `comments` | no | Free text; used here to record local changes to a vendored skill. |

`./build.sh check` rejects any other key — add it to the allow-list in `tools/check.py` first if
Claude Code grows one you want.

## Vendored skills

`show-me`, `ub-mode`, and `mags-manifest-design` come from upstream repos; see `THIRD_PARTY.md`
for source, pinned commit, license, and local changes. Do not reformat their `SKILL.md` files —
that makes re-syncing with upstream painful.
