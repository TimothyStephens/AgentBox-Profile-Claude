# Third-party content

Skills vendored into `skills/`. Plugins are not vendored — they are declared in `plugins.toml`
and installed by agentbox.

Each entry below was verified by fetching the file from the pinned commit and diffing it against
the vendored copy. Re-verify the same way after any re-sync.

## show-me

- Source: https://github.com/humanlayer/skills — `plugins/show-me/skills/show-me`
- Commit: `4d69d20f6e9b57b4fcf0d501ccfb1be961f0f329`
- License: MIT (`skills/show-me/LICENSE`, identical to upstream's root `LICENSE`)
- Local changes: two, both because sessions run in a sandbox with no display. Upstream is
  otherwise byte-identical at that commit.
  1. The HTML-artifact bullet ("For a visual UI, ...") used to end `Then open it for the user:`
     followed by a `Bash(open path/to/show-me-{description}.html)` block. macOS `open` does not
     exist in the sandbox and there is nothing to open onto. It now saves the file to
     `.dev/show-me/show-me-{description}.html` and hands the user that path instead.
  2. A paragraph was added under `### guidance` noting that the terminal renders Mermaid as
     source text, so the plain-text views are usually the better choice and a diagram that must
     be seen rendered belongs in the HTML file.

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

That overwrites local changes, so diff before you commit and re-apply the ones listed above:

```
git diff -- skills/<name>/SKILL.md
```

Then update the commit here, re-list the local changes you kept, and run `./build.sh check`.
Prefer carrying zero local changes. Record the ones you keep in this file and nowhere else —
the skills' frontmatter stays free of bookkeeping, so it keeps diffing cleanly against upstream.
