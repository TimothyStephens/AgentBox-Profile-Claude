# agentbox-profile-claude

Tim's Claude Code profile for agentbox (`ab`), a rootless-podman sandbox launcher.
**This repo is the source.** The live profile is a clone of it at
`~/.config/agentbox/claude/profile`; nothing here edits that clone except `./build.sh deploy`.

## What each part is

| Path | What it is | How agentbox uses it |
|---|---|---|
| `CLAUDE.md` | Standing rules, in every session's context | Mounted **read-only** at the user level |
| `skills/` | One directory per skill, each with a `SKILL.md` | Mounted **read-only** |
| `agents/` | Sub-agent definitions, one `.md` each | Mounted **read-only** |
| `commands/` | Slash commands, one `.md` each | Mounted **read-only** |
| `docs/` | Documentation for each load directory, `docs/<dir>.md`, and `docs/decisions.md` | Not loaded — that is the point |
| `settings.json` | Durable harness settings (permissions, hooks, env) | **Copied fresh** at each session start |
| `plugins.toml` | Plugin declarations, pinned by commit | Installed by `ab profile install claude` |
| `Containerfile` | Personal tool layer on the agentbox-claude image | Built by `ab image build claude` |
| `build.sh` | check / status / deploy / install driver | — |
| `tools/check.py` | The validator `check` runs (python3 ≥ 3.11, stdlib only) | — |
| `tests/run.sh` | Tests for the validator and the host guards | — |
| `THIRD_PARTY.md` | Source, commit, license and local changes of vendored skills | — |
| `.dev/` | Scratch space: EGM artifacts (`.dev/docs`), show-me's HTML files | Gitignored; never deployed |

[`docs/skills.md`](docs/skills.md), [`docs/agents.md`](docs/agents.md), and
[`docs/commands.md`](docs/commands.md) each state the file format and the frontmatter Claude
Code expects. Read those before adding anything.

They live in `docs/` rather than inside the directories they describe because the load
directories are loaded, not read: every `.md` under `commands/` becomes a slash command, so a
`commands/README.md` showed up as `/README`. `check` now errors on a `README*` at any depth in
any load directory, whatever its case. `agents/` and `commands/` currently do not exist —
every load directory except `skills/` is optional, and absent means empty; create one when you
add its first item.

This repo has a sibling, `agentbox-profile-omp`, for OMP. `build.sh`, the `Containerfile`, the
shared core block of `CLAUDE.md` and the shared `check` rules are kept the same in both, and the
test cases named `shared:` exist under the same name in both repos. Change a shared part here
and make the same change there.

Two things that are easy to get wrong:

- **`settings.json` is copied, not mounted.** Changing settings inside a session is lost at the
  end of it. Durable changes belong in this repo.
- **Never vendor plugin files into `skills/`.** Declare the plugin in `plugins.toml`. EGM in
  particular resolves its personas and standards through `${CLAUDE_PLUGIN_ROOT}` and breaks when
  its files are copied somewhere else.

## Workflow

```
edit  ->  ./build.sh check  ->  git commit  ->  ./build.sh all   (Tim, on the host)
```

On a new host, clone this repo anywhere and run `./build.sh all`. `deploy` sees that
`~/.config/agentbox/claude/profile` does not exist yet and clones it; `install` then installs the
plugins and builds the image. After that, the same command picks up each new commit.

`./build.sh check` is offline and runs anywhere, including inside a session sandbox. It prints
every problem as `path: problem` and exits 1 if any of them is an error. Warnings print the same
way and do not fail the run. It rejects any top-level entry it does not recognize, so adding a
directory here means adding it to `TOP_LEVEL` in `tools/check.py` too. `.dev/` is allowed and
exempt from the symlink and file-size rules — it is gitignored scratch space and nothing in it
reaches a session — but a file named like a secret (`.env*`, `*.pem`, `id_*`) is an error
anywhere, `.dev/` included.

`./build.sh status` runs anywhere too: it compares the live profile's commit against this repo's
HEAD, lists the plugin pins, and reports whether `ab` and its subcommands are available.

`./build.sh deploy` and `./build.sh install` are **host only** — they refuse to run when
`$AGENTBOX_SESSION` is set or `/run/agentbox` exists, because the live profile and `ab` are not
visible from inside a session.

- `deploy` does `git -C ~/.config/agentbox/claude/profile pull --ff-only`. If that directory
  does not exist (or is empty), it is a first-time setup: `deploy` creates
  `~/.config/agentbox/claude/` and clones this repo (its `origin` URL, or this checkout if it has
  no origin) to `profile/`. If the directory exists but is not a clean clone of this repo, it
  refuses and prints the one-time migration: move it aside to `profile.pre-repo`, then
  `git clone` this repo in its place.
- `install` does `ab profile install claude`, then `ab image build claude` if a `Containerfile`
  exists. If this `ab` lacks a command, it says which and exits 3.
- `all` is check, then deploy, then install, stopping at the first failure.

New sessions pick up a deploy immediately. Sessions already running keep the `settings.json`
they were started with.

## Running a session with no profile

```
ab run --no-profile
```

That skips everything here — `CLAUDE.md`, `skills/`, `agents/`, `commands/`, `settings.json`,
plugins, and the user image layer. Use it to tell "the profile is doing this" apart from
"Claude Code is doing this", and to reproduce a bug report from a stock session.

## Rolling back

```
git revert <bad commit>     # or: git revert --no-commit <range> && git commit
./build.sh check
./build.sh all              # on the host
```

Roll *forward* with a revert commit rather than resetting history — `deploy` is `pull --ff-only`
and refuses a rewritten branch. If you do need to rewind, do it in this repo, then move the live
clone aside and re-clone using the migration `deploy` prints.

## Tests

```
./tests/run.sh
```

Builds a known-good fixture, asserts `check` passes on it and on this repo, then mutates one
rule at a time and asserts the matching message. It also asserts `deploy` and `install` refuse
to run with `AGENTBOX_SESSION` set. No network, no `ab`, no writes outside `$TMPDIR`.
