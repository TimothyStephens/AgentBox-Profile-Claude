# Third-party content

Skills vendored into `skills/`. Plugins are not vendored — they are declared in `plugins.toml`
and installed by agentbox.

One section per skill, the heading being its name, then these fields in this order: source URL,
path within that repo, commit, license, local changes. The format is shared with the sibling
profile repo, so keep the field order when you add an entry.

Each entry below was verified by fetching the file from the pinned commit and diffing it against
the vendored copy, except where noted.

## show-me

- Source URL: https://github.com/humanlayer/skills
- Path: `plugins/show-me/skills/show-me`
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

- Source URL: https://github.com/unclebob/ub-mode
- Path: `SKILL.md`, at the repository root
- Commit: `3da62bf3fcfd2034de41f30d920d2739e566171f`
- License: MIT (`skills/ub-mode/LICENSE`, identical to upstream's root `LICENSE`)
- Local changes: one. Upstream is otherwise byte-identical at that commit.
  1. Added `disable-model-invocation: true` to the frontmatter, so the skill loads only when
     the user asks for it — which matches its own description, "Use when the user runs /ub-mode
     or asks for the reduced principles". Nothing else in the file changed. The key does not
     hide the skill: `/ub-mode` still appears in the menu, and Claude can no longer load it on
     its own. `hide: true` is the separate key that keeps a skill out of the menu.

## mags-manifest-design

- Source URL: https://github.com/TimothyStephens/MAGS-CodeDev
- Path: `skills/mags-manifest-design/SKILL.md`
- Commit: `d44fea8c5bf4021e3103ee9671a06940fc7f713c`
- License: none published upstream; the repository belongs to this profile's maintainer
- Local changes: none — `SKILL.md` is the vendored file copied unchanged. Not diffed against
  upstream: the repository is private and unreachable from a sandbox.

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
