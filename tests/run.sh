#!/usr/bin/env bash
# Tests for tools/check.py and build.sh's host-only guards.
#
#   ./tests/run.sh
#
# Offline. Needs no `ab`. Writes only inside a temporary directory.
#
# Each case copies tests/fixtures/good to a scratch dir, breaks exactly one rule, and
# asserts that check reports it. The good fixture and this repo must both pass clean.

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

# expect_clean LABEL DIR
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

# expect_warning LABEL DIR SUBSTRING  (a warning must not fail the run)
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

echo "== baseline"
expect_clean "good fixture passes" "$GOOD"

out="$(cd "$REPO" && ./build.sh check 2>&1)"; rc=$?
if (( rc == 0 )); then ok "./build.sh check passes on the repo"
else bad "./build.sh check passes on the repo" "exit $rc: $out"; fi

echo "== layout"
d="$(fixture)"; : > "$d/notes.txt"
expect_error "unexpected top-level entry" "$d" "unexpected top-level entry"

d="$(fixture)"; rm "$d/CLAUDE.md"
expect_error "CLAUDE.md missing" "$d" "CLAUDE.md: is required but missing"

d="$(fixture)"; printf 'build\n' > "$d/.gitignore"
expect_error ".dev not gitignored" "$d" "does not ignore .dev"

echo "== files"
d="$(fixture)"; ln -s CLAUDE.md "$d/skills/sample-skill/shortcut.md"
expect_error "symlink" "$d" "is a symlink"

d="$(fixture)"; head -c 1100000 /dev/zero > "$d/skills/sample-skill/big.bin"
expect_error "file over 1 MB" "$d" "over the 1 MB limit"

d="$(fixture)"; : > "$d/skills/sample-skill/.env.local"
expect_error ".env file" "$d" "looks like a secret or key file"

d="$(fixture)"; : > "$d/skills/sample-skill/server.pem"
expect_error ".pem file" "$d" "looks like a secret or key file"

d="$(fixture)"; : > "$d/skills/sample-skill/id_ed25519"
expect_error "id_* file" "$d" "looks like a secret or key file"

echo "== CLAUDE.md"
d="$(fixture)"
{ echo "# Too long"; for i in $(seq 1 160); do echo "line $i"; done; } > "$d/CLAUDE.md"
expect_warning "CLAUDE.md over 150 lines warns" "$d" "warning: is 161 lines"

echo "== settings.json"
d="$(fixture)"; printf '{ "broken": \n' > "$d/settings.json"
expect_error "settings.json invalid JSON" "$d" "is not valid JSON"

for key in ANTHROPIC_API_KEY GITHUB_TOKEN MY_SECRET DB_PASSWORD; do
  d="$(fixture)"
  printf '{ "env": { "%s": "xyzzy" } }\n' "$key" > "$d/settings.json"
  expect_error "settings.json env $key" "$d" "looks like a credential"
done

echo "== skills"
d="$(fixture)"; rm "$d/skills/sample-skill/SKILL.md"
expect_error "skill without SKILL.md" "$d" "SKILL.md: is missing"

d="$(fixture)"; printf '# no frontmatter\n' > "$d/skills/sample-skill/SKILL.md"
expect_error "skill without frontmatter" "$d" "no YAML frontmatter"

d="$(fixture)"
printf -- '---\nname: sample-skill\n---\n\nBody.\n' > "$d/skills/sample-skill/SKILL.md"
expect_error "skill without description" "$d" "missing required key 'description'"

d="$(fixture)"
printf -- '---\nname: other-name\ndescription: Use when testing.\n---\n\nBody.\n' \
  > "$d/skills/sample-skill/SKILL.md"
expect_error "skill name != dir name" "$d" "does not match directory name 'sample-skill'"

d="$(fixture)"; mv "$d/skills/sample-skill" "$d/skills/Bad_Name"
printf -- '---\nname: Bad_Name\ndescription: Use when testing.\n---\n\nBody.\n' \
  > "$d/skills/Bad_Name/SKILL.md"
expect_error "skill name bad characters" "$d" 'does not match ^[a-z0-9][a-z0-9-]{0,63}$'

# Every frontmatter key Claude Code / OMP document for skills, in one file.
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
expect_clean "documented frontmatter keys pass" "$d"

# An undocumented key warns; it must not fail the run.
d="$(fixture)"
printf -- '---\nname: sample-skill\ndescription: Use when testing.\ncolour: blue\n---\n\nB.\n' \
  > "$d/skills/sample-skill/SKILL.md"
expect_warning "undocumented frontmatter key warns" "$d" "undocumented key(s) 'colour'"

echo "== agents"
d="$(fixture)"
printf -- '---\nname: sample-agent\n---\n\nYou are a fixture.\n' \
  > "$d/agents/sample-agent.md"
expect_error "agent without description" "$d" "missing required key 'description'"

d="$(fixture)"; printf 'You are a fixture.\n' > "$d/agents/sample-agent.md"
expect_error "agent without frontmatter" "$d" "no YAML frontmatter"

echo "== commands"
d="$(fixture)"; : > "$d/commands/sample-command.md"
expect_error "empty command" "$d" "sample-command.md: is empty"

echo "== plugins.toml"
d="$(fixture)"; sed -i 's/^name = .*/name = "egm"/' "$d/plugins.toml"
expect_error "plugin name without @" "$d" "is not of the form 'plugin@marketplace'"

d="$(fixture)"; sed -i '/^marketplace/d' "$d/plugins.toml"
expect_error "plugin without marketplace" "$d" "is missing a marketplace"

d="$(fixture)"; sed -i 's/^ref = .*/ref = "464db03"/' "$d/plugins.toml"
expect_error "plugin ref not 40 hex" "$d" "is not a 40-character hex commit sha"

d="$(fixture)"; sed -i '/^ref/d' "$d/plugins.toml"
expect_error "plugin without ref" "$d" "is missing a ref"

d="$(fixture)"; cat "$GOOD/plugins.toml" >> "$d/plugins.toml"
expect_error "duplicate plugin" "$d" "is declared twice"

d="$(fixture)"; printf 'name = [[\n' > "$d/plugins.toml"
expect_error "plugins.toml invalid TOML" "$d" "is not valid TOML"

echo "== Containerfile"
d="$(fixture)"; sed -i '1s/.*/FROM debian:bookworm/' "$d/Containerfile"
expect_error "Containerfile without ARG BASE" "$d" "first instruction must be 'ARG BASE'"

d="$(fixture)"; sed -i '2s|.*|FROM debian:bookworm|' "$d/Containerfile"
expect_error "Containerfile not FROM \${BASE}" "$d" "second instruction must be 'FROM \${BASE}'"

for verb in "USER root" "ENTRYPOINT [\"/bin/sh\"]" "CMD [\"bash\"]"; do
  d="$(fixture)"; printf '%s\n' "$verb" >> "$d/Containerfile"
  expect_error "Containerfile sets ${verb%% *}" "$d" "must not set ${verb%% *}"
done

d="$(fixture)"
printf 'RUN curl -fsSL -o /tmp/x https://example.invalid/x.tgz\n' >> "$d/Containerfile"
expect_error "download without checksum" "$d" "without a sha256 checksum"

d="$(fixture)"
printf 'RUN curl -fsSL https://example.invalid/x.tgz -o /tmp/x; echo %s > /tmp/sum\n' \
  "95aaa8e89473f5421114f2787c13ae0ec6e11ebbd1a13a1bd6fcf63420f8073f" >> "$d/Containerfile"
expect_error "checksum never verified" "$d" "never verifies it"

echo "== host-only guards"
for sub in deploy install; do
  out="$(cd "$REPO" && AGENTBOX_SESSION=test ./build.sh "$sub" 2>&1)"; rc=$?
  if (( rc != 2 )); then
    bad "$sub refuses with AGENTBOX_SESSION set" "expected exit 2, got $rc: $out"
  elif ! grep -qF "host only" <<<"$out"; then
    bad "$sub refuses with AGENTBOX_SESSION set" "message does not say host only: $out"
  else
    ok "$sub refuses with AGENTBOX_SESSION set"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 )) || exit 1
