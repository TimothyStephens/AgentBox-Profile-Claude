#!/usr/bin/env bash
# Build/deploy driver for Tim's Claude Code profile. See README.md.
#
#   ./build.sh check     offline validation of this repo          (anywhere)
#   ./build.sh status    live profile vs this repo, plugin pins   (anywhere)
#   ./build.sh deploy    fast-forward the live profile clone      (host only)
#   ./build.sh install   ab profile install + ab image build      (host only)
#   ./build.sh all       check, deploy, install; stop on failure  (host only)
#
# Exit status: 0 ok, 1 check failed, 2 refused (wrong place / usage), 3 ab cannot do it.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIVE="${AGENTBOX_CLAUDE_PROFILE:-$HOME/.config/agentbox/claude/profile}"

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# HOST ONLY: the live profile and `ab` live on the host, not in a session sandbox.
require_host() {
  local what="$1"
  if [[ -n "${AGENTBOX_SESSION:-}" || -e /run/agentbox ]]; then
    warn "build.sh $what: refusing to run inside an agentbox sandbox; this is host only."
    warn "  Run it from a terminal on the host, in a checkout of this repo."
    exit 2
  fi
}

# Where a fresh clone of this repo should come from.
clone_source() {
  local origin
  origin="$(git -C "$REPO" remote get-url origin 2>/dev/null)"
  if [[ -n "$origin" ]]; then printf '%s\n' "$origin"; else printf '%s\n' "$REPO"; fi
}

ab_has() {  # ab_has "profile install" -> 0 if that subcommand exists
  command -v ab >/dev/null 2>&1 || return 1
  # shellcheck disable=SC2086
  ab $1 --help >/dev/null 2>&1
}

# --- check -----------------------------------------------------------------

cmd_check() {
  say "== check: $REPO"
  python3 "$REPO/tools/check.py" "$REPO"
  local rc=$?
  if (( rc == 0 )); then say "check: ok"; else say "check: failed"; fi
  return $rc
}

# --- status ----------------------------------------------------------------

# Is $LIVE a clean clone of this repo? Sets REASON on failure.
REASON=""
live_is_clean_clone() {
  REASON=""
  if [[ ! -d "$LIVE" ]]; then
    REASON="does not exist"
    return 1
  fi
  if ! git -C "$LIVE" rev-parse --git-dir >/dev/null 2>&1; then
    REASON="is not a git repository"
    return 1
  fi
  local src origin
  src="$(clone_source)"
  origin="$(git -C "$LIVE" remote get-url origin 2>/dev/null)"
  if [[ -z "$origin" ]]; then
    REASON="has no origin remote"
    return 1
  fi
  if [[ "$origin" != "$src" ]]; then
    REASON="has origin $origin, expected $src"
    return 1
  fi
  if [[ -n "$(git -C "$LIVE" status --porcelain 2>/dev/null)" ]]; then
    REASON="has uncommitted local changes"
    return 1
  fi
  return 0
}

print_migration() {
  say ""
  say "One-time migration (run on the host, then ./build.sh deploy):"
  say "  mv $LIVE ${LIVE}.pre-repo"
  say "  git clone $(clone_source) $LIVE"
  say ""
  say "Keep profile.pre-repo until you have compared it against this repo; delete it then."
}

cmd_status() {
  local head live_head
  head="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo '(no commits)')"
  say "repo:  $REPO"
  say "  HEAD $head"

  say "live:  $LIVE"
  if live_is_clean_clone; then
    live_head="$(git -C "$LIVE" rev-parse HEAD)"
    say "  HEAD $live_head"
    if [[ "$live_head" == "$head" ]]; then
      say "  up to date with this repo"
    elif git -C "$REPO" merge-base --is-ancestor "$live_head" "$head" 2>/dev/null; then
      local behind
      behind="$(git -C "$REPO" rev-list --count "$live_head..$head" 2>/dev/null)"
      say "  $behind commit(s) behind this repo; ./build.sh deploy will fast-forward it"
    else
      say "  diverged from this repo (not an ancestor of HEAD)"
    fi
  else
    say "  not deployable: $REASON"
  fi

  say "plugins:"
  if [[ -f "$REPO/plugins.toml" ]]; then
    python3 "$REPO/tools/check.py" --list-plugins "$REPO" \
      | while read -r name marketplace ref; do
          say "  $name  $marketplace  ${ref:0:12}"
        done
  else
    say "  (no plugins.toml)"
  fi

  say "ab:"
  if ! command -v ab >/dev/null 2>&1; then
    say "  not on PATH (expected inside a session sandbox; needed on the host)"
  else
    say "  $(command -v ab)"
    if ab_has "profile install"; then say "  profile install: available"
    else say "  profile install: NOT available"; fi
    if ab_has "image build"; then say "  image build: available"
    else say "  image build: NOT available"; fi
  fi
  return 0
}

# --- deploy ----------------------------------------------------------------

cmd_deploy() {
  require_host deploy
  if ! live_is_clean_clone; then
    warn "build.sh deploy: refusing to touch $LIVE: it $REASON."
    warn "  deploy only fast-forwards a clean clone of this repo."
    print_migration >&2
    exit 2
  fi
  say "== deploy: git -C $LIVE pull --ff-only"
  git -C "$LIVE" pull --ff-only || return 1
  say "deploy: live profile is now at $(git -C "$LIVE" rev-parse --short HEAD)"
  say "deploy: new sessions pick it up; existing sessions keep the old settings.json"
  return 0
}

# --- install ---------------------------------------------------------------

cmd_install() {
  require_host install
  if ! command -v ab >/dev/null 2>&1; then
    warn "build.sh install: ab is not on PATH; cannot install plugins or build the image."
    exit 3
  fi
  if ! ab_has "profile install"; then
    warn "build.sh install: this ab has no 'profile install' command yet."
    exit 3
  fi
  say "== install: ab profile install claude"
  ab profile install claude || return 1

  if [[ -f "$REPO/Containerfile" ]]; then
    if ! ab_has "image build"; then
      warn "build.sh install: Containerfile present but this ab has no 'image build' command yet."
      exit 3
    fi
    say "== install: ab image build claude"
    ab image build claude || return 1
  else
    say "install: no Containerfile, skipping image build"
  fi
  say "install: ok"
  return 0
}

# --- all -------------------------------------------------------------------

cmd_all() {
  cmd_check   || return $?
  cmd_deploy  || return $?
  cmd_install || return $?
  say "all: ok"
  return 0
}

usage() {
  sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  check)   cmd_check ;;
  status)  cmd_status ;;
  deploy)  cmd_deploy ;;
  install) cmd_install ;;
  all)     cmd_all ;;
  ""|-h|--help|help) usage; [[ -z "${1:-}" ]] && exit 2 || exit 0 ;;
  *) warn "build.sh: unknown command '${1}'"; usage >&2; exit 2 ;;
esac
