# Third-party content

Skills vendored into `skills/`. Plugins are not vendored — they are declared in `plugins.toml`
and installed by agentbox.

## show-me

- Source: https://github.com/humanlayer/skills — `plugins/show-me/skills/show-me`
- Commit: `4d69d20f6e9b57b4fcf0d501ccfb1be961f0f329`
- License: MIT (`skills/show-me/LICENSE`)
- Local changes: upstream's own note says local changes are described in a comment at the top of
  the skill's frontmatter. **No such comment is present in the vendored file**, so the changes
  are undocumented here. Tim to fill this in (see "Open" below).

## ub-mode

- Source: https://github.com/unclebob/ub-mode — `plugins/ub-mode/skills/ub-mode`
- Commit: `3da62bf3fcfd2034de41f30d920d2739e566171f`
- License: MIT (`skills/ub-mode/LICENSE`)
- Local changes: same as above — the frontmatter carries no comment describing the local
  changes, so they are undocumented here. Tim to fill this in.

## mags-manifest-design

- Source: https://github.com/TimothyStephens/MAGS-CodeDev —
  `mags-codedev-extension/skills/mags-manifest-design`
- Commit: `63e0271ae259e973123984fa065b6d00572a277a`
- License: Tim's own project
- Local changes: none

## Open

`show-me/SKILL.md` and `ub-mode/SKILL.md` were vendored with the instruction not to edit them,
and neither contains the frontmatter comment that was supposed to describe its local changes.
Either the comment was lost before these landed in `incoming/`, or the files are verbatim
upstream copies. Diffing against the pinned commits would settle it; the sandbox cannot reach
those paths. Until then the two "Local changes" entries above are unverified.
