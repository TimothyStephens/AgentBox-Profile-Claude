# Decisions

## 2026-11-10: `seed/` — keyless config agentbox reads beside the live profile, installed by deploy

- What: a `seed/` directory in the profile repo. `./build.sh deploy` copies each `seed/<name>` to
  `~/.config/agentbox/<agent>/<name>` when no live copy exists, mode 0600, and never overwrites one;
  `./build.sh status` prints a `seeds:` block naming every file agentbox looks for (`SEEDS` in
  `build.sh`: for OMP `models.yml config.yml mcp.json mags-codedev.yaml`, for Claude none) plus
  whatever `seed/` holds, each as `live = seed`, `DIFFERS`, `not live yet`, `live only` or
  `MISSING`. `check` allows `seed/`, requires flat files, and refuses a credential-shaped line
  (`apiKey`, `token`, `secret`, `password`, `authorization` with a real value; `apiKey` in
  `models.yml` with any value, which is agentbox's own rule). `build.sh` is still the same script in
  both repos; its per-profile lines are now the profile name, the live path and `SEEDS`.
- Why: a session on OMP without `~/.config/agentbox/omp/models.yml` runs on defaults and only says
  so in a warning at start; nothing in the profile's own tooling knew the file existed, and a new
  host had to learn it from agentbox's INSTALL.md. The seeds are keyless by agentbox's design, so
  a copy can live in the repo; `deploy` installing a missing one makes a fresh host complete, and
  never overwriting keeps a host-side edit safe. Committing `seed/` is the default so it travels
  with the repo; a `seed/` line in `.gitignore` makes it host-local instead, with `status` still
  reporting it.

## 2026-11-09: plugins.toml moves to agentbox's `[[plugin]]` format; `check` enforces the installer's rules

- What: `plugins.toml` was `name = "egm@egm"`, `marketplace = "<owner>/<repo>"`, `ref`. It is now
  `id`, `marketplace` (the catalog's own name), `source` (where it is cloned from) and `ref`, the
  format `agentbox/plugins.py` validates and the OMP profile already used. `tools/check.py` applies
  the same rules (all four keys required, an unknown key or an `[[npm]]`/`[[repo]]` section is an
  error, name charset and length limits, shorthand-or-https source, 40-hex ref) and
  `--list-plugins` prints `id source ref` as the OMP checker does.
- Why: `./build.sh install` on the host failed with `ab: plugins.toml: [[plugin]] #1: unknown key(s)
  name`. The two formats had been written independently (3 Nov here, 5 Nov in agentbox), and this
  repo's `check` passed a file the installer refused. The rules now live in one place, agentbox,
  and `check` mirrors them so a deploy cannot pass what the install will reject.
- How Claude Code loads it: a probe on 9 Nov (agentbox `docs/decisions.md`) found that Claude Code
  reads a marketplace in place when `settings.json` declares it with a `directory` source, and that
  a remote source in settings is not registered at startup. So the tree agentbox installs is only
  the pinned clone; the session generates the settings keys. See README, "How a plugin reaches a
  session".

## 2026-11-09: PARITY.md dropped; build.sh is the same script in both profile repos

- What: `PARITY.md`, the written parity contract with the sibling profile repo, was deleted from
  `agentbox-profile-claude` and `agentbox-profile-omp`. `build.sh` was ported from the Claude repo
  to the OMP repo verbatim; the two now differ only in the profile name, the live-path variable
  and how they call `tools/check.py`. The OMP `deploy` therefore clones the live profile on first
  run, matches the live clone by `origin` URL rather than root commit, and no longer checks for a
  detached HEAD.
- Why: the Claude repo's latest `build.sh` changes were to be synced to the OMP repo, and the
  parity discussion taken out of the README and `PARITY.md`, since the review that did the sync
  made the repos match. The shared parts are now listed in one paragraph of each README.
