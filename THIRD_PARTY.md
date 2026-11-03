# Third-party content

Skills vendored into `skills/`. Plugins are not vendored — they are declared in `plugins.toml`
and installed by agentbox.

Each entry below was verified by fetching the file from the pinned commit and diffing it against
the vendored copy. Re-verify the same way after any re-sync.

## show-me

- Source: https://github.com/humanlayer/skills — `plugins/show-me/skills/show-me`
- Commit: `4d69d20f6e9b57b4fcf0d501ccfb1be961f0f329`
- License: MIT (`skills/show-me/LICENSE`, identical to upstream's root `LICENSE`)
- Local changes: **none.** `SKILL.md` is byte-identical to upstream at that commit. The task
  described local changes recorded in a frontmatter comment; there is no such comment, and the
  diff is empty, so there is nothing to record.

## ub-mode

- Source: https://github.com/unclebob/ub-mode — `SKILL.md` at the repository root.
  (The path given when this was vendored, `plugins/ub-mode/skills/ub-mode`, does not exist at
  this commit — upstream keeps the skill at the top level. Corrected here.)
- Commit: `3da62bf3fcfd2034de41f30d920d2739e566171f`
- License: MIT (`skills/ub-mode/LICENSE`, identical to upstream's root `LICENSE`)
- Local changes: **none.** `SKILL.md` is byte-identical to upstream at that commit, and it
  carries no frontmatter comment, for the same reason as above.

## mags-manifest-design

- Source: https://github.com/TimothyStephens/MAGS-CodeDev —
  `mags-codedev-extension/skills/mags-manifest-design`
- Commit: `63e0271ae259e973123984fa065b6d00572a277a`
- License: Tim's own project
- Local changes: none. Not diffed against upstream — the repo is private, so the sandbox's
  egress could not reach it. The other two were diffed successfully.

## Re-syncing a vendored skill

```
curl -sSL https://raw.githubusercontent.com/<owner>/<repo>/<new-commit>/<path>/SKILL.md \
  -o skills/<name>/SKILL.md
```

Then update the commit above, note any local changes you are deliberately keeping, and run
`./build.sh check`. Prefer carrying zero local changes; if you must keep one, put it in a
`comments:` key in the frontmatter so the next re-sync surfaces the conflict.
