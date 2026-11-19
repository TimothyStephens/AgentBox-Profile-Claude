# Third-party content

Skills vendored into `skills/`. Plugins are not vendored — they are declared in `plugins.toml`
and installed by agentbox.

One section per skill, the heading being its name, then these fields in this order: source URL,
path within that repo, commit, license, local changes. The format is shared with the sibling
profile repo, so keep the field order when you add an entry.

No skill is vendored here at the moment. `show-me`, `ub-mode` and `mags-manifest-design`, with
the other skills shared by every agentbox profile, moved to the `agentbox-skills` repository on
2026-11-19 (see `docs/decisions.md`). Their provenance, pinned commits, licences and local
changes are recorded in that repository's
[`THIRD_PARTY.md`](https://github.com/TimothyStephens/AgentBox-Skills/blob/main/THIRD_PARTY.md).

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
