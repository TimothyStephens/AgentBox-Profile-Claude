#!/usr/bin/env bash
# Tests for tools/check.py and build.sh's host-only guards.
#
#   ./tests/run.sh
#
# Offline. Needs no `ab`. Writes only inside a temporary directory.
#
# Each case copies tests/fixtures/good to a scratch dir, changes exactly one thing, and
# asserts what check says about it. The good fixture and this repo must both pass clean.
#
# Every check rule shared with agentbox-profile-omp has a pass case and a fail case, under the
# same case name in both profile repos:
#
#   shared: <rule> — pass|fail[ (detail)]   a rule both profile repos enforce. Same name in both;
#                                            the detail in parentheses may differ.
#   claude: ...                              a rule this harness forces. Has no sibling.
#
# The last case checks the promise: every "shared:" label here must exist in the sibling's run.sh.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GOOD="$REPO/tests/fixtures/good"
CHECK=(python3 "$REPO/tools/check.py")
SIBLING="$REPO/../agentbox-profile-omp/tests/run.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }

# fixture -> path to a fresh copy of the good fixture.
# Runs in a command substitution, so it must not rely on shell state surviving.
fixture() {
  local d
  d="$(mktemp -d "$TMP/case-XXXXXX")"
  cp -a "$GOOD/." "$d/"
  printf '%s\n' "$d"
}

# repo_copy NAME -> path to a copy of this repo (without .git) for build.sh cases that must break something.
repo_copy() {
  local d="$TMP/$1"
  mkdir -p "$d" && cp -a "$REPO/." "$d/" && rm -rf "$d/.git"
  printf '%s\n' "$d"
}

# expect_clean LABEL DIR -- exit 0 and no output at all
expect_clean() {
  local label="$1" dir="$2" out rc
  out="$("${CHECK[@]}" "$dir" 2>&1)"; rc=$?
  if (( rc != 0 )); then
    bad "$label" "expected exit 0, got $rc: $out"
  elif [[ -n "$out" ]]; then
    bad "$label" "expected no output, got: $out"
  else
    ok "$label"
  fi
}

# expect_error LABEL DIR SUBSTRING
expect_error() {
  local label="$1" dir="$2" want="$3" out rc
  out="$("${CHECK[@]}" "$dir" 2>&1)"; rc=$?
  if (( rc != 1 )); then
    bad "$label" "expected exit 1, got $rc. Output: $out"
  elif ! grep -qF -- "$want" <<<"$out"; then
    bad "$label" "output does not mention '$want'. Output: $out"
  else
    ok "$label"
  fi
}

# expect_warning LABEL DIR SUBSTRING -- a warning must not fail the run
expect_warning() {
  local label="$1" dir="$2" want="$3" out rc
  out="$("${CHECK[@]}" "$dir" 2>&1)"; rc=$?
  if (( rc != 0 )); then
    bad "$label" "a warning must not fail the run, got exit $rc. Output: $out"
  elif ! grep -qF -- "$want" <<<"$out"; then
    bad "$label" "output does not mention '$want'. Output: $out"
  else
    ok "$label"
  fi
}

# expect_exit LABEL WANT_RC WANT_SUBSTRING CMD... -- for build.sh
expect_exit() {
  local label="$1" want_rc="$2" want="$3"; shift 3
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if (( rc != want_rc )); then
    bad "$label" "expected exit $want_rc, got $rc. Output: $out"
  elif ! grep -qF -- "$want" <<<"$out"; then
    bad "$label" "output does not mention '$want'. Output: $out"
  else
    ok "$label"
  fi
}

echo "== baseline"
expect_clean "good fixture passes" "$GOOD"
expect_exit "shared: build.sh check exits 0 on this repository — pass" 0 "check: ok" \
  env -C "$REPO" ./build.sh check
d="$(repo_copy broken-repo)"; : > "$d/notes.txt"
expect_exit "shared: build.sh check exits 1 when check fails — fail" 1 "check: failed" \
  env -C "$d" ./build.sh check

# ---------------------------------------------------------------------------
# Shared rules. Same case names in both profile repos.
# ---------------------------------------------------------------------------

echo "== shared: only the documented top-level entries"
expect_clean "shared: only documented top-level entries — pass" "$(fixture)"
d="$(fixture)"; : > "$d/notes.txt"
expect_error "shared: only documented top-level entries — fail" "$d" "unexpected top-level entry"

echo "== shared: instruction file"
# The filename is an allowed difference: CLAUDE.md here, AGENTS.md in the sibling. The rule is the same.
d="$(fixture)"; printf '# Working rules\n\nRules.\n' > "$d/CLAUDE.md"
expect_clean "shared: instruction file present — pass" "$d"
d="$(fixture)"; rm "$d/CLAUDE.md"
expect_error "shared: instruction file present — fail" "$d" "CLAUDE.md: is required but missing"
d="$(fixture)"; seq 140 > "$d/CLAUDE.md"
expect_clean "shared: instruction file under 150 lines — pass" "$d"
d="$(fixture)"
{ echo "# Too long"; for i in $(seq 1 160); do echo "line $i"; done; } > "$d/CLAUDE.md"
expect_warning "shared: instruction file under 150 lines — fail" "$d" "warning: is 161 lines"

echo "== shared: skills one level deep"
expect_clean "shared: skills one level deep — pass" "$(fixture)"
d="$(fixture)"; mkdir -p "$d/skills/sample-skill/nested"
cp "$GOOD/skills/sample-skill/SKILL.md" "$d/skills/sample-skill/nested/SKILL.md"
expect_error "shared: skills one level deep — fail" "$d" "is a nested skill"
d="$(fixture)"; printf 'Supporting asset.\n' > "$d/skills/sample-skill/reference.md"
expect_clean "shared: skill directory holds SKILL.md — pass" "$d"
d="$(fixture)"; rm "$d/skills/sample-skill/SKILL.md"
expect_error "shared: skill directory holds SKILL.md — fail" "$d" "SKILL.md: is missing"
d="$(fixture)"; printf 'notes\n' > "$d/skills/sample-skill/notes.txt"
expect_clean "shared: no loose files in skills/ — pass" "$d"
d="$(fixture)"; printf 'loose\n' > "$d/skills/loose.md"
expect_error "shared: no loose files in skills/ — fail" "$d" \
  "skills/loose.md: is a plain file directly in skills/"

echo "== shared: load directories hold only loadable items"
# Documentation lives in docs/<dir>.md, so the load directories stay loadable-only. Nested
# items and supporting files beside a SKILL.md are loadable content and stay allowed.
d="$(fixture)"; mkdir -p "$d/commands/git"
printf -- '---\ndescription: Nested fixture command.\n---\n\nDo it.\n' \
  > "$d/commands/git/sync.md"
mkdir -p "$d/skills/sample-skill/references"
printf 'MIT\n' > "$d/skills/sample-skill/LICENSE"
printf 'Reference material.\n' > "$d/skills/sample-skill/references/notes.md"
expect_clean "shared: load directories hold only loadable items — pass" "$d"

# No README* at any depth, in any load directory, whatever its case.
# Labels are spelled out, not built from the loop variable, so the sibling cross-check can see them.
for dir in skills agents commands; do
  case "$dir" in
    skills) label="shared: README in skills/ — fail" ;;
    agents) label="shared: README in agents/ — fail" ;;
    commands) label="shared: README in commands/ — fail" ;;
  esac
  d="$(fixture)"; printf '# %s/\n' "$dir" > "$d/$dir/README.md"
  expect_error "$label" "$d" "$dir/README.md: is documentation in a load directory"
done
for dir in skills agents commands; do
  case "$dir" in
    skills) label="shared: lowercase readme in skills/ — fail" ;;
    agents) label="shared: lowercase readme in agents/ — fail" ;;
    commands) label="shared: lowercase readme in commands/ — fail" ;;
  esac
  d="$(fixture)"; printf '# %s/\n' "$dir" > "$d/$dir/readme.md"
  expect_error "$label" "$d" "$dir/readme.md: is documentation in a load directory"
done
d="$(fixture)"; mkdir -p "$d/commands/git"
printf '# nested\n' > "$d/commands/git/README.md"
expect_error "shared: nested README in a load directory — fail" \
  "$d" "commands/git/README.md: is documentation in a load directory"
d="$(fixture)"; printf '# nested\n' > "$d/skills/sample-skill/README.md"
expect_error "shared: README inside a skill directory — fail" "$d" \
  "skills/sample-skill/README.md: is documentation in a load directory"

d="$(fixture)"
printf -- '---\ndescription: A second command.\n---\n\nBody.\n' > "$d/commands/second.md"
expect_clean "shared: non-loadable file in a load directory — pass" "$d"
for dir in agents commands; do
  d="$(fixture)"; printf 'notes\n' > "$d/$dir/notes.txt"
  expect_error "shared: non-loadable file in a load directory — fail ($dir/)" "$d" \
    "$dir/notes.txt: is not a .md file"
done

# Every load directory except skills/ is optional: absent = empty.
d="$(fixture)"; rm -rf "$d/agents" "$d/commands"
expect_clean "shared: load directories other than skills/ are optional — pass" "$d"
d="$(fixture)"; rm -rf "$d/skills"
expect_error "shared: load directories other than skills/ are optional — fail" "$d" \
  "skills: is required but missing"

echo "== shared: skill name == dir name"
expect_clean "shared: skill name == dir name — pass" "$(fixture)"
d="$(fixture)"
printf -- '---\nname: other-name\ndescription: Use when testing.\n---\n\nBody.\n' \
  > "$d/skills/sample-skill/SKILL.md"
expect_error "shared: skill name == dir name — fail" "$d" "does not match directory name 'sample-skill'"

echo "== shared: skill name pattern"
d="$(fixture)"; mv "$d/skills/sample-skill" "$d/skills/0k-name"
printf -- '---\nname: 0k-name\ndescription: Use when testing.\n---\n\nBody.\n' \
  > "$d/skills/0k-name/SKILL.md"
expect_clean "shared: skill name pattern — pass" "$d"
d="$(fixture)"; mv "$d/skills/sample-skill" "$d/skills/Bad_Name"
printf -- '---\nname: Bad_Name\ndescription: Use when testing.\n---\n\nBody.\n' \
  > "$d/skills/Bad_Name/SKILL.md"
expect_error "shared: skill name pattern — fail" "$d" 'does not match ^[a-z0-9][a-z0-9-]{0,63}$'

echo "== shared: skill frontmatter"
expect_clean "shared: skill frontmatter required keys — pass" "$(fixture)"
d="$(fixture)"
printf -- '---\nname: sample-skill\n---\n\nBody.\n' > "$d/skills/sample-skill/SKILL.md"
expect_error "shared: skill frontmatter required keys — fail" "$d" "missing required key 'description'"
d="$(fixture)"; printf '# no frontmatter\n' > "$d/skills/sample-skill/SKILL.md"
expect_error "shared: skill frontmatter present — fail" "$d" "no YAML frontmatter"
d="$(fixture)"
printf -- '---\nname: sample-skill\ndescription: >\n  A folded block scalar.\n---\n\nBody.\n' \
  > "$d/skills/sample-skill/SKILL.md"
expect_clean "shared: frontmatter parses — pass" "$d"
d="$(fixture)"
printf -- '---\nname: sample-skill\ndescription: Unclosed.\n\nBody.\n' > "$d/skills/sample-skill/SKILL.md"
expect_error "shared: frontmatter parses — fail" "$d" "frontmatter is not closed with ---"
# Quoted scalars and trailing comments are YAML; `""` is an empty value, so a required key set to it is missing.
d="$(fixture)"
printf -- '---\nname: "sample-skill"\ndescription: '"'"'Use when testing: quoted.'"'"'\n---\n\nBody.\n' \
  > "$d/skills/sample-skill/SKILL.md"
expect_clean "shared: frontmatter parses — pass (quoted values)" "$d"
d="$(fixture)"
printf -- '---\nname: sample-skill # the directory name\ndescription: Use when testing.\n---\n\nBody.\n' \
  > "$d/skills/sample-skill/SKILL.md"
expect_clean "shared: frontmatter parses — pass (trailing comment)" "$d"
d="$(fixture)"
printf -- '---\nname: sample-skill\ndescription: ""\n---\n\nBody.\n' > "$d/skills/sample-skill/SKILL.md"
expect_error "shared: skill frontmatter required keys — fail (empty description)" "$d" \
  "missing required key 'description'"

echo "== shared: frontmatter keys"
# Every frontmatter key this harness documents, in one file. The key set itself is an
# allowed difference between the repos; that documented keys pass is not.
d="$(fixture)"
cat > "$d/skills/sample-skill/SKILL.md" <<'SKILL'
---
name: sample-skill
description: Use when the test suite needs every documented frontmatter key at once.
license: MIT
version: 0.1.0
metadata:
  author: fixture
allowed-tools: Read, Grep
disallowed-tools: WebFetch
tools: Read
model: opus
argument-hint: [path]
disable-model-invocation: true
user-invocable: false
hide: true
context: fork
agent: Explore
comments: A local convention, not a Claude Code key.
---

Body.
SKILL
expect_clean "shared: documented frontmatter keys — pass" "$d"
d="$(fixture)"
printf -- '---\nname: sample-skill\ndescription: Use when testing.\ncolour: blue\n---\n\nB.\n' \
  > "$d/skills/sample-skill/SKILL.md"
expect_warning "shared: unknown frontmatter key warns — fail" "$d" "undocumented key(s) 'colour'"

echo "== shared: no symlinks in tracked paths"
expect_clean "shared: no symlinks in tracked paths — pass" "$(fixture)"
d="$(fixture)"; ln -s CLAUDE.md "$d/skills/sample-skill/shortcut.md"
expect_error "shared: no symlinks in tracked paths — fail" "$d" "is a symlink"

echo "== shared: no files over 1 MB in tracked paths"
d="$(fixture)"; head -c 1048576 /dev/zero > "$d/skills/sample-skill/exactly-1mb.bin"
expect_clean "shared: no files over 1 MB in tracked paths — pass" "$d"
d="$(fixture)"; head -c 1100000 /dev/zero > "$d/skills/sample-skill/big.bin"
expect_error "shared: no files over 1 MB in tracked paths — fail" "$d" "over the 1 MB limit"

echo "== shared: secret-shaped names are errors anywhere, .dev/ included"
# Names that only look close pass: .envrc is not .env*, notid_rsa does not start with id_,
# cert.pem.md does not end in .pem, keyring.md does not end in .key, my-secrets is not secrets.
d="$(fixture)"; : > "$d/skills/sample-skill/.envrc"
expect_clean "shared: .env* is an error anywhere — pass" "$d"
d="$(fixture)"; : > "$d/skills/sample-skill/.env.local"
expect_error "shared: .env* is an error anywhere — fail" "$d" "looks like a secret or key file"
d="$(fixture)"; mkdir -p "$d/.dev/docs"; : > "$d/.dev/docs/.env"
expect_error "shared: .env* is an error in .dev — fail" "$d" ".dev/docs/.env"
d="$(fixture)"; : > "$d/skills/sample-skill/cert.pem.md"
expect_clean "shared: *.pem is an error anywhere — pass" "$d"
d="$(fixture)"; : > "$d/skills/sample-skill/server.pem"
expect_error "shared: *.pem is an error anywhere — fail" "$d" "looks like a secret or key file"
d="$(fixture)"; mkdir -p "$d/.dev"; : > "$d/.dev/key.pem"
expect_error "shared: *.pem is an error in .dev — fail" "$d" ".dev/key.pem"
d="$(fixture)"; : > "$d/skills/sample-skill/keyring.md"
expect_clean "shared: *.key is an error anywhere — pass" "$d"
d="$(fixture)"; : > "$d/skills/sample-skill/server.key"
expect_error "shared: *.key is an error anywhere — fail" "$d" "looks like a secret or key file"
d="$(fixture)"; mkdir -p "$d/.dev"; : > "$d/.dev/server.key"
expect_error "shared: *.key is an error in .dev — fail" "$d" ".dev/server.key"
d="$(fixture)"; : > "$d/skills/sample-skill/notid_rsa"
expect_clean "shared: id_* is an error anywhere — pass" "$d"
d="$(fixture)"; : > "$d/skills/sample-skill/id_ed25519"
expect_error "shared: id_* is an error anywhere — fail" "$d" "looks like a secret or key file"
d="$(fixture)"; mkdir -p "$d/.dev"; : > "$d/.dev/id_ed25519"
expect_error "shared: id_* is an error in .dev — fail" "$d" ".dev/id_ed25519"
d="$(fixture)"; mkdir -p "$d/skills/sample-skill/my-secrets"; : > "$d/skills/sample-skill/my-secrets/notes.md"
expect_clean "shared: secrets/ is an error anywhere — pass" "$d"
d="$(fixture)"; mkdir -p "$d/skills/sample-skill/secrets"; : > "$d/skills/sample-skill/secrets/notes.md"
expect_error "shared: secrets/ is an error anywhere — fail" "$d" "skills/sample-skill/secrets: is named secrets"
d="$(fixture)"; mkdir -p "$d/.dev/secrets"
expect_error "shared: secrets/ is an error in .dev — fail" "$d" ".dev/secrets: is named secrets"

echo "== shared: .dev is otherwise skipped"
d="$(fixture)"; mkdir -p "$d/.dev/show-me"
printf '<html></html>\n' > "$d/.dev/show-me/show-me-example.html"
expect_clean "shared: .dev/ is otherwise skipped — pass" "$d"
# The symlink and size rules are about what gets deployed, so .dev is exempt from them.
d="$(fixture)"; mkdir -p "$d/.dev/docs"
head -c 1100000 /dev/zero > "$d/.dev/docs/big.bin"
ln -s ../../CLAUDE.md "$d/.dev/docs/link.md"
expect_clean "shared: .dev/ is otherwise skipped — pass (symlink and large file)" "$d"
d="$(fixture)"; mkdir -p "$d/dev-notes"; printf 'x\n' > "$d/dev-notes/note.md"
expect_error "shared: .dev/ is otherwise skipped — fail" "$d" "dev-notes: unexpected top-level entry"
d="$(fixture)"; printf 'build\n' > "$d/.gitignore"
expect_error "claude: .dev must be gitignored — fail" "$d" "does not ignore .dev"

echo "== shared: Containerfile"
expect_clean "shared: Containerfile ARG BASE then FROM \${BASE} — pass" "$(fixture)"
d="$(fixture)"; sed -i '1s/.*/FROM debian:bookworm/' "$d/Containerfile"
expect_error "shared: Containerfile ARG BASE then FROM \${BASE} — fail" "$d" \
  "first instruction must be 'ARG BASE'"
d="$(fixture)"; sed -i '2s|.*|FROM debian:bookworm|' "$d/Containerfile"
expect_error "shared: Containerfile FROM is pinned to \${BASE} — fail" "$d" \
  "second instruction must be 'FROM \${BASE}'"
# Case-sensitive, as the launcher is: `ARG base` declares an argument FROM ${BASE} never reads.
d="$(fixture)"; sed -i '1s/.*/ARG base/' "$d/Containerfile"
expect_error "shared: Containerfile ARG BASE then FROM \${BASE} — fail (lowercase arg base)" "$d" \
  "first instruction must be 'ARG BASE'"
d="$(fixture)"; sed -i '2s|.*|FROM ${base}|' "$d/Containerfile"
expect_error "shared: Containerfile FROM is pinned to \${BASE} — fail (lowercase base)" "$d" \
  "second instruction must be 'FROM \${BASE}'"
d="$(fixture)"; rm "$d/Containerfile"
expect_clean "shared: Containerfile is optional — pass" "$d"

expect_clean "shared: Containerfile sets no USER/ENTRYPOINT/CMD — pass" "$(fixture)"
d="$(fixture)"; printf 'USER root\n' >> "$d/Containerfile"
expect_error "shared: Containerfile sets no USER/ENTRYPOINT/CMD — fail" "$d" "must not set USER"
d="$(fixture)"; printf 'ENTRYPOINT ["/bin/sh"]\n' >> "$d/Containerfile"
expect_error "shared: Containerfile sets no ENTRYPOINT — fail" "$d" "must not set ENTRYPOINT"
d="$(fixture)"; printf 'CMD ["bash"]\n' >> "$d/Containerfile"
expect_error "shared: Containerfile sets no CMD — fail" "$d" "must not set CMD"

expect_clean "shared: Containerfile downloads are checksum-verified — pass" "$(fixture)"
d="$(fixture)"
printf 'RUN curl -fsSL -o /tmp/x https://example.invalid/x.tgz\n' >> "$d/Containerfile"
expect_error "shared: Containerfile downloads are checksum-verified — fail" "$d" \
  "without a sha256 checksum"
d="$(fixture)"
printf 'RUN curl -fsSL https://example.invalid/x.tgz -o /tmp/x; echo %s > /tmp/sum\n' \
  "95aaa8e89473f5421114f2787c13ae0ec6e11ebbd1a13a1bd6fcf63420f8073f" >> "$d/Containerfile"
expect_error "shared: Containerfile downloads are checksum-verified — fail (never verified)" "$d" \
  "never verifies it"
d="$(fixture)"; printf 'ADD https://example.invalid/x.tgz /tmp/x\n' >> "$d/Containerfile"
expect_error "shared: Containerfile downloads are checksum-verified — fail (ADD)" "$d" \
  "without a sha256 checksum"
# Only RUN and ADD fetch: a URL in ENV or LABEL downloads nothing.
d="$(fixture)"
printf 'ENV DOCS_URL=https://example.invalid/docs\nLABEL org.opencontainers.image.source=https://example.invalid/repo\n' \
  >> "$d/Containerfile"
expect_clean "shared: Containerfile downloads are checksum-verified — pass (URL in ENV)" "$d"

echo "== shared: plugins.toml format"
expect_clean "shared: plugins.toml format — pass" "$(fixture)"
d="$(fixture)"; printf 'name = [[\n' > "$d/plugins.toml"
expect_error "shared: plugins.toml format — fail" "$d" "is not valid TOML"
d="$(fixture)"; rm "$d/plugins.toml"
expect_error "shared: plugins.toml present — fail" "$d" "plugins.toml: is required but missing"
d="$(fixture)"; sed -i 's/^id = .*/id = "egm"/' "$d/plugins.toml"
expect_error "shared: plugin id is name@marketplace — fail" "$d" \
  "is not of the form 'plugin@marketplace'"
d="$(fixture)"; sed -i '/^marketplace/d' "$d/plugins.toml"
expect_error "shared: plugin keys required — fail (marketplace)" "$d" "is missing marketplace"
d="$(fixture)"; sed -i 's/^marketplace = .*/marketplace = "other"/' "$d/plugins.toml"
expect_error "shared: plugin id matches its marketplace — fail" "$d" \
  "marketplace is 'other' but the id says 'egm'"
d="$(fixture)"; sed -i '/^source/d' "$d/plugins.toml"
expect_error "shared: plugin keys required — fail" "$d" "is missing source"
d="$(fixture)"; sed -i '/^ref/d' "$d/plugins.toml"
expect_error "shared: plugin keys required — fail (ref)" "$d" "is missing ref"
# source: GitHub shorthand or a plain https URL, never a local path or a URL with credentials.
d="$(fixture)"
sed -i 's|^source = .*|source = "https://github.com/google/elephant-goldfish-model.git"|' "$d/plugins.toml"
expect_clean "shared: plugin source is shorthand or https — pass" "$d"
d="$(fixture)"; sed -i 's|^source = .*|source = "/tmp/egm"|' "$d/plugins.toml"
expect_error "shared: plugin source is shorthand or https — fail" "$d" "neither GitHub shorthand"
d="$(fixture)"; sed -i 's|^source = .*|source = "https://user:pw@github.com/google/egm.git"|' "$d/plugins.toml"
expect_error "shared: plugin source is shorthand or https — fail (credentials)" "$d" \
  "neither GitHub shorthand"
d="$(fixture)"; sed -i 's/^id = .*/id = "bad_name@egm"/' "$d/plugins.toml"
expect_error "shared: plugin name charset — fail" "$d" "invalid plugin name 'bad_name'"
d="$(fixture)"; printf 'name = "egm@egm"\n' >> "$d/plugins.toml"
expect_error "shared: plugin keys known — fail (the 9 Nov install failure)" "$d" \
  "has unknown key 'name'"
d="$(fixture)"; sed -i 's/^\[\[plugin\]\]/[[plugins]]/' "$d/plugins.toml"
expect_error "shared: plugins.toml unknown section — fail" "$d" "unknown section [[plugins]]"
d="$(fixture)"; printf '\n[[npm]]\nname = "pi-lens"\nversion = "4.4.9"\n' >> "$d/plugins.toml"
expect_error "claude: plugins.toml OMP-only section — fail" "$d" "[[npm]] is OMP-only"
d="$(fixture)"
sed -i 's/^ref = .*/ref = "0123456789abcdef0123456789abcdef01234567"/' "$d/plugins.toml"
expect_clean "shared: plugin ref is a pinned sha — pass" "$d"
d="$(fixture)"; sed -i 's/^ref = .*/ref = "464db03"/' "$d/plugins.toml"
expect_error "shared: plugin ref is a pinned sha — fail" "$d" \
  "is not a 40-character hex commit sha"
d="$(fixture)"; cat "$GOOD/plugins.toml" >> "$d/plugins.toml"
expect_error "shared: plugin id is unique — fail" "$d" "is declared twice"

echo "== shared: seed directory"
d="$(fixture)"; mkdir "$d/seed"
printf 'providers:\n  llama-cpp:\n    baseUrl: http://192.0.2.2:8080/v1\n' > "$d/seed/models.yml"
expect_clean "shared: seed/ holds keyless config — pass" "$d"
d="$(fixture)"; mkdir -p "$d/seed/sub"
expect_error "shared: seed/ with a subdirectory — fail" "$d" "seed/ holds files only"
d="$(fixture)"; mkdir "$d/seed"; printf 'mcp:\n  token: ghp_realvalue\n' > "$d/seed/config.yml"
expect_error "shared: seed/ file holding a credential — fail" "$d" "looks like a credential"
d="$(fixture)"; mkdir "$d/seed"; printf 'providers:\n  openai:\n    apiKey: none\n' > "$d/seed/models.yml"
expect_error "shared: seed/ models.yml with any apiKey — fail" "$d" 'apiKey` is refused in the model seed'
d="$(fixture)"; mkdir "$d/seed"; printf '{"env": {"TOKEN": "${X}"}}\n' > "$d/seed/mcp.json"
expect_clean "shared: seed/ env reference is not a credential — pass" "$d"
expect_exit "shared: build.sh status lists the seeds — pass" 0 "seeds:" \
  env -C "$REPO" AGENTBOX_CLAUDE_PROFILE="$TMP/no-such/profile" ./build.sh status

echo "== shared: build.sh exit codes"
for sub in deploy install all; do
  expect_exit "shared: build.sh $sub exits 2 inside a session — fail" 2 "host only" \
    env -C "$REPO" AGENTBOX_SESSION=test ./build.sh "$sub"
done
expect_exit "shared: build.sh exits 2 on an unknown command — fail" 2 "unknown command" \
  env -C "$REPO" ./build.sh frobnicate
expect_exit "shared: build.sh status exits 0 — pass" 0 "plugins:" \
  env -C "$REPO" ./build.sh status
expect_exit "shared: build.sh status reports a missing live profile as clonable — pass" 0 \
  "does not exist yet; ./build.sh deploy will clone" \
  env -C "$REPO" AGENTBOX_CLAUDE_PROFILE="$TMP/no-such-profile" ./build.sh status
# A plugins.toml that does not parse must not leave status reading as fine.
d="$(repo_copy broken-plugins)"; printf 'name = [[\n' > "$d/plugins.toml"
expect_exit "shared: build.sh status fails when plugins.toml does not parse — fail" 1 \
  "(plugins.toml does not parse)" \
  env -C "$d" AGENTBOX_CLAUDE_PROFILE="$TMP/no-such-profile" ./build.sh status

echo "== shared: build.sh deploy checks the live clone against this repo"
# deploy itself is host only, so scratch repositories stand in for origin, the live clone and this checkout
# and the functions are called directly from a sourced build.sh.
git_q() { git -c user.name=t -c user.email=t@t.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
deploy_scratch() {  # deploy_scratch DIR -> DIR/origin.git, DIR/repo and DIR/live, all at the same commit
  local d="$1"
  mkdir -p "$d" && git_q init --bare "$d/origin.git" && git_q clone "$d/origin.git" "$d/repo" \
    && printf 'one\n' > "$d/repo/f" && git_q -C "$d/repo" add f && git_q -C "$d/repo" commit -m one \
    && git_q -C "$d/repo" push origin HEAD && git_q clone "$d/origin.git" "$d/live"
}
d="$TMP/deploy-ok"; deploy_scratch "$d"
expect_exit "shared: build.sh deploy accepts a live clone at this repo's HEAD — pass" 0 "" \
  bash -c 'source "$1"; live_matches_repo "$2" "$3"' _ "$REPO/build.sh" "$d/live" "$d/repo"
d="$TMP/deploy-unpushed"; deploy_scratch "$d"
printf 'two\n' > "$d/repo/f"; git_q -C "$d/repo" commit -am two
expect_exit "shared: build.sh deploy refuses when this repo is unpushed — fail" 1 "push this repo first" \
  bash -c 'source "$1"; git -C "$2" pull --ff-only -q && live_matches_repo "$2" "$3"' _ \
  "$REPO/build.sh" "$d/live" "$d/repo"
d="$TMP/deploy-diverged"; deploy_scratch "$d"
printf 'live\n' > "$d/live/f"; git_q -C "$d/live" commit -am live-edit
expect_exit "shared: build.sh deploy treats a live clone with its own commits as diverged — fail" 1 "diverged" \
  bash -c 'source "$1"; LIVE="$2"; REPO="$3"; live_is_clean_clone || { printf "%s\n" "$REASON"; exit 1; }' _ \
  "$REPO/build.sh" "$d/live" "$d/repo"

# ---------------------------------------------------------------------------
# Harness-specific. These differ between the repos.
# ---------------------------------------------------------------------------

echo "== claude: settings.json"
d="$(fixture)"; printf '{ "broken": \n' > "$d/settings.json"
expect_error "claude: settings.json invalid JSON — fail" "$d" "is not valid JSON"
for key in ANTHROPIC_API_KEY GITHUB_TOKEN MY_SECRET DB_PASSWORD; do
  d="$(fixture)"
  printf '{ "env": { "%s": "xyzzy" } }\n' "$key" > "$d/settings.json"
  expect_error "claude: settings.json env $key — fail" "$d" "looks like a credential"
done

echo "== claude: agents and commands"
d="$(fixture)"
printf -- '---\nname: sample-agent\n---\n\nYou are a fixture.\n' > "$d/agents/sample-agent.md"
expect_error "claude: agent without description — fail" "$d" "missing required key 'description'"
d="$(fixture)"; printf 'You are a fixture.\n' > "$d/agents/sample-agent.md"
expect_error "claude: agent without frontmatter — fail" "$d" "no YAML frontmatter"
d="$(fixture)"; : > "$d/commands/sample-command.md"
expect_error "claude: empty command — fail" "$d" "sample-command.md: is empty"

# ---------------------------------------------------------------------------
# The parity promise: every "shared:" label in this file exists in the sibling repo's run.sh.
# Labels are compared without a trailing "(detail)". This run checks this file against the
# sibling; the sibling's own run checks the other direction.
# ---------------------------------------------------------------------------

echo "== shared: case labels match the sibling repo"
sibling_labels() {
  local label="shared: every shared case label exists in the sibling repo — pass"
  local missing=() stem
  if [[ ! -f "$SIBLING" ]]; then
    printf '  skip %s (no sibling checkout at %s)\n' "$label" "$SIBLING"
    return 0
  fi
  while IFS= read -r stem; do
    grep -qF -- "$stem" "$SIBLING" || missing+=("$stem")
  done < <(grep -o '"shared:[[:space:]][^"]*"' "$REPO/tests/run.sh" \
             | sed -e 's/^"//' -e 's/"$//' -e 's/ ([^()]*)$//' | sort -u)
  if (( ${#missing[@]} == 0 )); then
    ok "$label"
  else
    bad "$label" "missing in $SIBLING:"$'\n'"$(printf '         %s\n' "${missing[@]}")"
  fi
}
sibling_labels

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 )) || exit 1
