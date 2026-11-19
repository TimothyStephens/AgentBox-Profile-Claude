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

`skills/` itself holds only skill directories: a plain file sitting directly in `skills/` is an
error, since nothing loads it (`.gitkeep` excepted, see below). Inside `skills/<name>/` put whatever the skill needs —
references, scripts, a `LICENSE` — with one exception: no `README*` file, at any depth and in
any case. Documentation never sits inside a load directory, which is why this file lives in
`docs/` instead. If a vendored skill ships a README, drop it and summarize it in
`THIRD_PARTY.md` under that skill's local changes.

## Shared skills: the `agentbox-skills` plugin

The skills every agentbox profile has are not in `skills/`. They live in one repository,
`agentbox-skills` (<https://github.com/TimothyStephens/AgentBox-Skills>), declared in
`plugins.toml` as `agentbox@agentbox-skills` at a pinned commit. Claude Code namespaces plugin
skills, so they run as `/agentbox:<name>`, e.g. `/agentbox:show-me` or `/agentbox:learn-repo`.
Provenance, licences and local changes of the vendored ones are in that repository's
`THIRD_PARTY.md`; change them there, never by copying one back into `skills/`.

| Skill | What for | Model-invocable |
| --- | --- | --- |
| `learn-repo` | build an understanding of an existing repo before a task | no |
| `review-drift` | review another agent's work for scope creep and drift from a plan, from a clean context | no |
| `show-me` | explain the current topic with diagrams, code-shape sketches or an HTML file under `.dev/show-me` | no |
| `ub-mode` | the reduced coding principles, on request | no |
| `mags-manifest-design` | write or edit a MAGs-CodeDev `manifest.json` | yes |
| `full-review` | a read-only, comprehensive code review of a branch, range, PR or the whole repo | no |
| `handoff` | a dated handoff note at the end of a session, for the next one's `learn-repo` | no |
| `characterization-tests` | pin the current behaviour of untested code before changing it | no |
| `systematic-debugging` | root-cause a bug or failure before fixing it | yes |
| `verification-before-completion` | run the checks before claiming work is done | yes |
| `test-driven-development` | write the test first | yes |
| `webapp-testing` | drive a local web UI with Playwright (not in the images; see agentbox-skills' THIRD_PARTY.md) | yes |
| `differential-review` | security-focused review of a PR, commit or diff | yes |
| `insecure-defaults` | find fail-open insecure defaults (hardcoded secrets, weak auth) | yes |
| `supply-chain-risk-auditor` | audit a project's dependencies (needs network the `packages` egress mostly blocks) | yes |

"Model-invocable: no" means `disable-model-invocation: true`: the skill runs only when invoked.
The list is the plugin's at the pinned commit; its README is the current one.

`skills/` holds only skills this profile alone has, and none today: it is empty but for
`.gitkeep`, which keeps it in git. It must still exist, because agentbox mounts it read-only
over the skill path; that `.gitkeep` is the one plain file `check` allows directly in `skills/`.
A skill every profile should have goes in `agentbox-skills` instead.

## Claude-only skills (in this repo's `skills/`)

| Skill | What for | Model may load it |
| --- | --- | --- |
| `skill-creator` | author a skill and test and tune it (its scripts call `claude -p`; vendored from anthropics/skills, see `THIRD_PARTY.md`) | yes |
