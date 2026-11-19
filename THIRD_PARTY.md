# Third-party content

Skills vendored into `skills/`. Plugins are not vendored — they are declared in `plugins.toml`
and installed by agentbox.

One section per skill, the heading being its name, then these fields in this order: source URL,
path within that repo, commit, license, local changes. The format is shared with the sibling
profile repo, so keep the field order when you add an entry.

One skill is vendored here: `skill-creator`, which only Claude Code can use (its test-and-tune
scripts call `claude -p`; moved from `agentbox-skills` on 2026-11-19). `show-me`, `ub-mode` and `mags-manifest-design`, with
the other skills shared by every agentbox profile, moved to the `agentbox-skills` repository on
2026-11-19 (see `docs/decisions.md`). Their provenance, pinned commits, licences and local
changes are recorded in that repository's
[`THIRD_PARTY.md`](https://github.com/TimothyStephens/AgentBox-Skills/blob/main/THIRD_PARTY.md).

## skills/skill-creator

| Field | Value |
| --- | --- |
| Name | `skill-creator` |
| Source URL | <https://github.com/anthropics/skills> |
| Path | `skills/skill-creator` |
| Commit | `e4bb5d960d87126ff3b3a8af1a104b7db67560ba` (commit date 2026-11-16) |
| License | Apache-2.0 — `skills/skill-creator/LICENSE.txt` (upstream's own file in the skill directory) |
| Vendored | 2026-11-19 |
| `disable-model-invocation` | not set (model-invocable) |

**Local changes**

None. Every file, `LICENSE.txt` included, is byte-identical to upstream.
Upstream's `THIRD_PARTY_NOTICES.md` names neither this skill nor
`webapp-testing`.

**Notes**

- **Cross-references:** its own `agents/grader.md`, `agents/comparator.md` and
  `agents/analyzer.md` are prompts the model reads before spawning a sub-agent;
  they are inside the skill directory, so no agent loads them as sub-agents.
  It names no other skill.
- **Tools:**
  - `scripts/run_eval.py`, `scripts/improve_description.py` and
    `scripts/run_loop.py` (description optimisation) shell out to
    **`claude -p`**: Claude Code only. They do not work in OMP or Pi.
    `run_eval.py` also **writes a command file into the project's
    `.claude/commands/`** so the skill under test is visible; that is a write
    into the user's repository.
  - `scripts/quick_validate.py` imports `yaml` (PyYAML, present in
    agentbox-base); the other scripts are standard library.
  - The body runs scripts as `python -m scripts.<name>` from the skill
    directory. Only the OMP image has a `python` command (`python-is-python3`);
    in the Claude and Pi images it is `python3`. The skill directory is
    read-only in a session.
  - `eval-viewer/generate_review.py` serves an HTML viewer and calls
    `webbrowser.open()`; a session has no display or browser, so the
    `--static <output_path>` mode the skill describes for headless use is the
    one that works. Step "open it: `open /tmp/...html`" is macOS-only.
- **Triggering:** only on skill-authoring requests. No take-over instruction;
  its "go all caps" passage is about generating the eval viewer inside the
  skill's own workflow. It advises making new skills' descriptions "pushy" to
  combat under-triggering; that is a style choice for skills it writes, to be
  weighed against keeping opt-in skills opt-in here.

## Declared, not vendored

These come from `plugins.toml`, installed by `ab profile install claude` from their own
repositories at the pinned commits. None of their content lives in this repository.

- `egm@egm` — Elephant Goldfish Model, <https://github.com/google/elephant-goldfish-model>.
- `agentbox@agentbox-skills` — the skills shared by every agentbox profile,
  <https://github.com/TimothyStephens/AgentBox-Skills>. Third-party skills in it are vendored
  there, and its `THIRD_PARTY.md` is their record.

## Re-syncing a vendored skill

```
curl -sSL https://raw.githubusercontent.com/<owner>/<repo>/<new-commit>/<path>/SKILL.md \
  -o skills/<name>/SKILL.md
```

That overwrites local changes, so diff before you commit and re-apply the ones listed for it:

```
git diff -- skills/<name>/SKILL.md
```

Then update the commit here, re-list the local changes you kept, and run `./build.sh check`.
Prefer carrying zero local changes. Record the ones you keep in this file and nowhere else —
the skills' frontmatter stays free of bookkeeping, so it keeps diffing cleanly against upstream.
A skill every profile should have belongs in `agentbox-skills` instead.
