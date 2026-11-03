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
# PARITY.md requires every shared check rule to have a pass case and a fail case, with the
# same case names in both profile repos. Those are the "shared rules" section below; keep the
# names in step with agentbox-profile-omp. The "harness-specific" section is allowed to differ.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GOOD="$REPO/tests/fixtures/good"
CHECK=(python3 "$REPO/tools/check.py")

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
expect_exit "./build.sh check passes on the repo" 0 "check: ok" \
  env -C "$REPO" ./build.sh check

# ---------------------------------------------------------------------------
# Shared rules (PARITY.md). Same case names in both profile repos.
# ---------------------------------------------------------------------------

echo "== shared: skills one level deep"
expect_clean "skills one level deep: pass" "$(fixture)"
d="$(fixture)"; mkdir -p "$d/skills/sample-skill/nested"
cp "$GOOD/skills/sample-skill/SKILL.md" "$d/skills/sample-skill/nested/SKILL.md"
expect_error "skills one level deep: fail" "$d" "is a nested skill"

echo "== shared: skill name == dir name"
expect_clean "skill name == dir name: pass" "$(fixture)"
d="$(fixture)"
printf -- '---\nname: other-name\ndescription: Use when testing.\n---\n\nBody.\n' \
  > "$d/skills/sample-skill/SKILL.md"
expect_error "skill name == dir name: fail" "$d" "does not match directory name 'sample-skill'"

echo "== shared: skill name pattern"
d="$(fixture)"; mv "$d/skills/sample-skill" "$d/skills/0k-name"
printf -- '---\nname: 0k-name\ndescription: Use when testing.\n---\n\nBody.\n' \
  > "$d/skills/0k-name/SKILL.md"
expect_clean "skill name pattern: pass" "$d"
d="$(fixture)"; mv "$d/skills/sample-skill" "$d/skills/Bad_Name"
printf -- '---\nname: Bad_Name\ndescription: Use when testing.\n---\n\nBody.\n' \
  > "$d/skills/Bad_Name/SKILL.md"
expect_error "skill name pattern: fail" "$d" 'does not match ^[a-z0-9][a-z0-9-]{0,63}$'

echo "== shared: required skill frontmatter"
expect_clean "required skill frontmatter: pass" "$(fixture)"
d="$(fixture)"
printf -- '---\nname: sample-skill\n---\n\nBody.\n' > "$d/skills/sample-skill/SKILL.md"
expect_error "required skill frontmatter: fail" "$d" "missing required key 'description'"
d="$(fixture)"; printf '# no frontmatter\n' > "$d/skills/sample-skill/SKILL.md"
expect_error "required skill frontmatter: fail (no frontmatter)" "$d" "no YAML frontmatter"
d="$(fixture)"; rm "$d/skills/sample-skill/SKILL.md"
expect_error "required skill frontmatter: fail (no SKILL.md)" "$d" "SKILL.md: is missing"

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
expect_clean "documented frontmatter keys: pass" "$d"
d="$(fixture)"
printf -- '---\nname: sample-skill\ndescription: Use when testing.\ncolour: blue\n---\n\nB.\n' \
  > "$d/skills/sample-skill/SKILL.md"
expect_warning "unknown frontmatter key: warn" "$d" "undocumented key(s) 'colour'"

echo "== shared: no symlinks in tracked paths"
expect_clean "no symlinks in tracked paths: pass" "$(fixture)"
d="$(fixture)"; ln -s CLAUDE.md "$d/skills/sample-skill/shortcut.md"
expect_error "no symlinks in tracked paths: fail" "$d" "is a symlink"

echo "== shared: no files over 1 MB in tracked paths"
d="$(fixture)"; head -c 1048576 /dev/zero > "$d/skills/sample-skill/exactly-1mb.bin"
expect_clean "no files over 1 MB in tracked paths: pass" "$d"
d="$(fixture)"; head -c 1100000 /dev/zero > "$d/skills/sample-skill/big.bin"
expect_error "no files over 1 MB in tracked paths: fail" "$d" "over the 1 MB limit"

echo "== shared: secret-shaped filenames are errors anywhere"
# Names that only look close: .envrc is not .env*, notid_rsa does not start with id_.
d="$(fixture)"
: > "$d/skills/sample-skill/.envrc"; : > "$d/skills/sample-skill/notid_rsa"
: > "$d/skills/sample-skill/cert.pem.md"
expect_clean "secret-shaped filenames: pass" "$d"
d="$(fixture)"; : > "$d/skills/sample-skill/.env.local"
expect_error "secret-shaped filenames: fail (.env*)" "$d" "looks like a secret or key file"
d="$(fixture)"; : > "$d/skills/sample-skill/server.pem"
expect_error "secret-shaped filenames: fail (*.pem)" "$d" "looks like a secret or key file"
d="$(fixture)"; : > "$d/skills/sample-skill/id_ed25519"
expect_error "secret-shaped filenames: fail (id_*)" "$d" "looks like a secret or key file"
d="$(fixture)"; mkdir -p "$d/.dev/docs"; : > "$d/.dev/docs/.env"
expect_error "secret-shaped filenames: fail (inside .dev)" "$d" ".dev/docs/.env"

echo "== shared: .dev is otherwise skipped"
d="$(fixture)"; mkdir -p "$d/.dev/show-me"
printf '<html></html>\n' > "$d/.dev/show-me/show-me-example.html"
expect_clean ".dev is otherwise skipped: pass" "$d"
# The symlink and size rules are about what gets deployed, so .dev is exempt from them.
d="$(fixture)"; mkdir -p "$d/.dev/docs"
head -c 1100000 /dev/zero > "$d/.dev/docs/big.bin"
ln -s ../../CLAUDE.md "$d/.dev/docs/link.md"
expect_clean ".dev is otherwise skipped: pass (symlink and large file)" "$d"
d="$(fixture)"; printf 'build\n' > "$d/.gitignore"
expect_error ".dev is otherwise skipped: fail (not gitignored)" "$d" "does not ignore .dev"

echo "== shared: only the documented top-level entries"
expect_clean "only documented top-level entries: pass" "$(fixture)"
d="$(fixture)"; : > "$d/notes.txt"
expect_error "only documented top-level entries: fail" "$d" "unexpected top-level entry"

echo "== shared: Containerfile"
expect_clean "Containerfile base: pass" "$(fixture)"
d="$(fixture)"; sed -i '1s/.*/FROM debian:bookworm/' "$d/Containerfile"
expect_error "Containerfile base: fail (no ARG BASE)" "$d" "first instruction must be 'ARG BASE'"
d="$(fixture)"; sed -i '2s|.*|FROM debian:bookworm|' "$d/Containerfile"
expect_error "Containerfile base: fail (not FROM \${BASE})" "$d" \
  "second instruction must be 'FROM \${BASE}'"

expect_clean "Containerfile sets no USER/ENTRYPOINT/CMD: pass" "$(fixture)"
for verb in "USER root" "ENTRYPOINT [\"/bin/sh\"]" "CMD [\"bash\"]"; do
  d="$(fixture)"; printf '%s\n' "$verb" >> "$d/Containerfile"
  expect_error "Containerfile sets no USER/ENTRYPOINT/CMD: fail (${verb%% *})" "$d" \
    "must not set ${verb%% *}"
done

expect_clean "Containerfile downloads are checksum-verified: pass" "$(fixture)"
d="$(fixture)"
printf 'RUN curl -fsSL -o /tmp/x https://example.invalid/x.tgz\n' >> "$d/Containerfile"
expect_error "Containerfile downloads are checksum-verified: fail (no checksum)" "$d" \
  "without a sha256 checksum"
d="$(fixture)"
printf 'RUN curl -fsSL https://example.invalid/x.tgz -o /tmp/x; echo %s > /tmp/sum\n' \
  "95aaa8e89473f5421114f2787c13ae0ec6e11ebbd1a13a1bd6fcf63420f8073f" >> "$d/Containerfile"
expect_error "Containerfile downloads are checksum-verified: fail (never verified)" "$d" \
  "never verifies it"

echo "== shared: plugins.toml format"
expect_clean "plugins.toml format: pass" "$(fixture)"
d="$(fixture)"; sed -i 's/^name = .*/name = "egm"/' "$d/plugins.toml"
expect_error "plugins.toml format: fail (name not x@y)" "$d" \
  "is not of the form 'plugin@marketplace'"
d="$(fixture)"; sed -i '/^marketplace/d' "$d/plugins.toml"
expect_error "plugins.toml format: fail (no marketplace)" "$d" "is missing a marketplace"
d="$(fixture)"; sed -i '/^ref/d' "$d/plugins.toml"
expect_error "plugins.toml format: fail (no ref)" "$d" "is missing a ref"
d="$(fixture)"; sed -i 's/^ref = .*/ref = "464db03"/' "$d/plugins.toml"
expect_error "plugins.toml format: fail (ref not 40 hex)" "$d" \
  "is not a 40-character hex commit sha"
d="$(fixture)"; cat "$GOOD/plugins.toml" >> "$d/plugins.toml"
expect_error "plugins.toml format: fail (duplicate)" "$d" "is declared twice"
d="$(fixture)"; printf 'name = [[\n' > "$d/plugins.toml"
expect_error "plugins.toml format: fail (invalid TOML)" "$d" "is not valid TOML"

echo "== shared: build.sh exit codes"
expect_exit "build.sh: exit 2 refused (deploy inside a session)" 2 "host only" \
  env -C "$REPO" AGENTBOX_SESSION=test ./build.sh deploy
expect_exit "build.sh: exit 2 refused (install inside a session)" 2 "host only" \
  env -C "$REPO" AGENTBOX_SESSION=test ./build.sh install
expect_exit "build.sh: exit 2 refused (unknown command)" 2 "unknown command" \
  env -C "$REPO" ./build.sh frobnicate
expect_exit "build.sh: status runs anywhere" 0 "plugins:" \
  env -C "$REPO" ./build.sh status

# ---------------------------------------------------------------------------
# Harness-specific. PARITY.md allows these to differ between the repos.
# ---------------------------------------------------------------------------

echo "== harness: instruction file"
d="$(fixture)"; rm "$d/CLAUDE.md"
expect_error "instruction file missing" "$d" "CLAUDE.md: is required but missing"
d="$(fixture)"
{ echo "# Too long"; for i in $(seq 1 160); do echo "line $i"; done; } > "$d/CLAUDE.md"
expect_warning "instruction file over 150 lines warns" "$d" "warning: is 161 lines"

echo "== harness: settings.json"
d="$(fixture)"; printf '{ "broken": \n' > "$d/settings.json"
expect_error "settings.json invalid JSON" "$d" "is not valid JSON"
for key in ANTHROPIC_API_KEY GITHUB_TOKEN MY_SECRET DB_PASSWORD; do
  d="$(fixture)"
  printf '{ "env": { "%s": "xyzzy" } }\n' "$key" > "$d/settings.json"
  expect_error "settings.json env $key" "$d" "looks like a credential"
done

echo "== harness: agents and commands"
d="$(fixture)"
printf -- '---\nname: sample-agent\n---\n\nYou are a fixture.\n' > "$d/agents/sample-agent.md"
expect_error "agent without description" "$d" "missing required key 'description'"
d="$(fixture)"; printf 'You are a fixture.\n' > "$d/agents/sample-agent.md"
expect_error "agent without frontmatter" "$d" "no YAML frontmatter"
d="$(fixture)"; : > "$d/commands/sample-command.md"
expect_error "empty command" "$d" "sample-command.md: is empty"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 )) || exit 1
