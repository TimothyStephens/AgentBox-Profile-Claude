# agents/

Sub-agents, one Markdown file each, mounted read-only at the user level in every project.
A sub-agent runs in its own context window and reports back; use one to keep a large,
self-contained search or review out of the main conversation.

## File format

`agents/<name>.md` — YAML frontmatter between `---` fences, then the agent's system prompt.

```markdown
---
name: my-agent
description: Use for <task>. Returns <what it returns>.
tools: Read, Grep, Glob
model: sonnet
---

You are a ... Your job is to ...
```

## Frontmatter Claude Code expects

| Key | Required | Notes |
|---|---|---|
| `name` | yes | How the agent is addressed. Lowercase and hyphens. |
| `description` | yes | How Claude decides to delegate to it. Say when to use it and what it returns. |
| `tools` | no | Comma-separated allow-list. Omit to inherit every tool. Narrow it for read-only agents. |
| `model` | no | `haiku`, `sonnet`, `opus`, or `inherit`. |

`./build.sh check` requires `name` and `description`. It also requires that `agents/` hold only
loadable items: a `README*` at any depth (in any case) or any non-`.md` file directly in
`agents/` is an error, because Claude Code tries to load whatever it finds. That is why this
file lives in `docs/` instead.

There is no `agents/` directory yet — nothing here. Create it when you add the first agent.
