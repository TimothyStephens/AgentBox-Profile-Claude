# commands/

Slash commands, one Markdown file each, mounted read-only at the user level in every project.
`commands/deploy.md` becomes `/deploy`; `commands/git/sync.md` becomes `/git:sync`.

## File format

`commands/<name>.md` — the file body is the prompt, expanded in place when the command runs.
Frontmatter is optional.

```markdown
---
description: One line shown in the slash-command menu.
argument-hint: [branch]
allowed-tools: Bash(git status:*), Bash(git diff:*)
---

Summarize the state of $1, using:

!`git status --short`
```

## Frontmatter Claude Code expects

| Key | Required | Notes |
|---|---|---|
| `description` | no | Menu text. Defaults to the first line of the body. |
| `argument-hint` | no | Shown after the command name while typing. |
| `allowed-tools` | no | Tools the command may use without a prompt. |
| `model` | no | Override the model for this command. |

In the body: `$ARGUMENTS` is everything the user typed, `$1`/`$2` are positional,
``!`cmd` `` inlines a shell command's output, and `@path` inlines a file.

`./build.sh check` requires that each command file be non-empty. It also requires that
`commands/` hold only loadable items: a `README*` at any depth (in any case) or any non-`.md`
file directly in `commands/` is an error. Every `.md` file under `commands/` becomes a slash
command, so a `README.md` left here would show up as `/README`, and `commands/git/README.md`
as `/git:README`. That is why this file lives in `docs/` instead.

There is no `commands/` directory yet — nothing here. Create it when you add the first command.
