#!/usr/bin/env python3
"""Offline validator for this Claude Code profile repo.

Usage:
    check.py [ROOT]              validate ROOT (default: the repo this file lives in)
    check.py --list-plugins ROOT print "name marketplace ref" for each declared plugin

Every problem is printed as "path: problem". Warnings are printed the same way with a
"warning: " prefix and do not affect the exit status.

Exit status: 0 = no errors, 1 = at least one error, 2 = usage error.

python3 >= 3.11, standard library only.
"""

from __future__ import annotations

import json
import re
import sys
import tomllib
from pathlib import Path

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

# Top-level entries this repo is allowed to contain.
TOP_LEVEL = {
    "CLAUDE.md",
    "settings.json",
    "skills",
    "agents",
    "commands",
    "docs",
    "plugins.toml",
    "Containerfile",
    "build.sh",
    "tools",
    "tests",
    "THIRD_PARTY.md",
    "PARITY.md",
    "README.md",
    # not part of the profile, but expected in a working tree
    ".git",
    ".gitignore",
    # Scratch space for EGM artifacts and show-me's HTML files, as in the Claude repo.
    # Gitignored and never deployed, so its contents are exempt from the symlink and size
    # rules -- but not from the secret-shaped-filename rule, which holds anywhere.
    ".dev",
}

# Not walked at all.
SKIP_DIRS = {".git"}

# Walked, but only the secret-shaped-filename rule applies: not a tracked path.
UNTRACKED_DIRS = {".dev"}

# Entries that must exist. Containerfile is optional (it is a personal tool layer), and so are
# agents/ and commands/: an empty load directory cannot be committed, and an absent one is
# indistinguishable from an empty one once agentbox has mounted it.
REQUIRED = [
    "CLAUDE.md",
    "settings.json",
    "skills",
    "plugins.toml",
    "build.sh",
    "tools/check.py",
    "tests",
    "THIRD_PARTY.md",
    "README.md",
]

# Directories agentbox mounts and the harness loads wholesale. Anything in them is loaded, so
# they hold only loadable items: documentation goes in docs/<dir>.md instead.
#   skills/  -- one directory per skill; a plain file directly inside it loads as nothing
#   agents/, commands/  -- one .md per item, nested directories namespacing them
SKILL_LOAD_DIR = "skills"
FLAT_LOAD_DIRS = ("agents", "commands")

SKILL_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")

# Frontmatter keys Claude Code and the official marketplace document for skills. An
# undocumented key only warns: Claude Code adds keys faster than this list can track, and a
# key this validator has not heard of is a reason to look, not a reason to block a deploy.
# Sources, both readable from a session at
# /run/agentbox/claude/plugins/marketplaces/claude-plugins-official:
#   claude-code-setup/skills/claude-automation-recommender/references/skills-reference.md
#     -> name, description, disable-model-invocation, user-invocable, allowed-tools,
#        context, agent
#   plugin-dev/skills/command-development/references/frontmatter-reference.md
#     -> model, argument-hint
#   keys used by shipped marketplace skills -> version, license, disallowed-tools, tools
SKILL_KEYS = {
    "name",
    "description",
    "license",
    "version",
    "metadata",
    "allowed-tools",
    "disallowed-tools",
    "tools",
    "model",
    "argument-hint",
    "disable-model-invocation",
    "user-invocable",
    "hide",
    "context",
    "agent",
    # Not a Claude Code key: a local convention for noting why a vendored skill differs from
    # upstream. THIRD_PARTY.md is the place for that, so nothing here uses it.
    "comments",
}

PLUGIN_NAME_RE = re.compile(r"^[^@\s]+@[^@\s]+$")
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"\b[0-9a-f]{64}\b")
URL_RE = re.compile(r"\bhttps?://")

SECRET_KEY_PARTS = ("KEY", "TOKEN", "SECRET", "PASSWORD")

# Files that must never be committed to the profile.
FORBIDDEN_FILE_RE = [
    re.compile(r"^\.env($|\.)"),
    re.compile(r"\.pem$"),
    re.compile(r"^id_"),
]

MAX_FILE_BYTES = 1024 * 1024
CLAUDE_MD_WARN_LINES = 150


# ---------------------------------------------------------------------------
# Problem collection
# ---------------------------------------------------------------------------


class Report:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.errors: list[tuple[str, str]] = []
        self.warnings: list[tuple[str, str]] = []

    def _rel(self, path: Path | str) -> str:
        if isinstance(path, str):
            return path
        try:
            return str(path.relative_to(self.root))
        except ValueError:
            return str(path)

    def error(self, path: Path | str, problem: str) -> None:
        self.errors.append((self._rel(path), problem))

    def warn(self, path: Path | str, problem: str) -> None:
        self.warnings.append((self._rel(path), f"warning: {problem}"))

    def print(self) -> int:
        for path, problem in self.errors + self.warnings:
            print(f"{path}: {problem}")
        return 1 if self.errors else 0


# ---------------------------------------------------------------------------
# Minimal YAML frontmatter parser
#
# Enough for skill and agent frontmatter: scalars, folded/literal block scalars,
# comments, blank lines. Anything it cannot parse is reported rather than guessed at.
# ---------------------------------------------------------------------------


def parse_frontmatter(text: str) -> tuple[dict[str, str] | None, str | None]:
    """Return (mapping, error). Exactly one of the two is None."""
    lines = text.splitlines()
    if not lines or lines[0].rstrip() != "---":
        return None, "no YAML frontmatter (file must start with ---)"
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].rstrip() == "---")
    except StopIteration:
        return None, "frontmatter is not closed with ---"

    out: dict[str, str] = {}
    i = 1
    while i < end:
        raw = lines[i]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            i += 1
            continue
        if raw[:1] in (" ", "\t"):
            return None, f"frontmatter line {i + 1} is indented but follows no key"
        if ":" not in raw:
            return None, f"frontmatter line {i + 1} is not 'key: value'"
        key, _, value = raw.partition(":")
        key = key.strip()
        value = value.strip()
        i += 1
        # A block scalar (`key: >`) or a nested mapping (`key:` with indented lines under it)
        # continues over the following indented lines. Flatten them into the value: these
        # checks only ask whether a key is present and, for scalars, what it says.
        if value in ("", ">", "|", ">-", "|-", ">+", "|+"):
            block: list[str] = []
            while i < end and (not lines[i].strip() or lines[i][:1] in (" ", "\t")):
                block.append(lines[i].strip())
                i += 1
            value = " ".join(p for p in block if p)
        if key in out:
            return None, f"frontmatter key {key!r} is set twice"
        out[key] = value
    return out, None


def read_text(path: Path, rep: Report) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        rep.error(path, "is not valid UTF-8")
    except OSError as exc:
        rep.error(path, f"cannot be read: {exc.strerror}")
    return None


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------


def check_layout(root: Path, rep: Report) -> None:
    for entry in sorted(root.iterdir(), key=lambda p: p.name):
        if entry.name not in TOP_LEVEL:
            rep.error(entry, "unexpected top-level entry (not part of the profile layout)")
    for required in REQUIRED:
        if not (root / required).exists():
            rep.error(required, "is required but missing")

    gitignore = root / ".gitignore"
    if not gitignore.exists():
        rep.error(".gitignore", "is missing (it must ignore .dev)")
    else:
        text = read_text(gitignore, rep) or ""
        entries = {line.strip().strip("/") for line in text.splitlines()}
        if ".dev" not in entries:
            rep.error(".gitignore", "does not ignore .dev (EGM artifact directory)")


def check_files(root: Path, rep: Report) -> None:
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        if rel.parts and rel.parts[0] in SKIP_DIRS:
            continue
        # A secret-shaped filename is an error wherever it is, .dev/ included: a key sitting
        # in scratch space is still a key sitting in the grant.
        if not path.is_dir() or path.is_symlink():
            for pattern in FORBIDDEN_FILE_RE:
                if pattern.search(path.name):
                    rep.error(path, "looks like a secret or key file and must not be here")
                    break
        # The remaining rules are about what gets deployed, so they skip untracked scratch.
        if rel.parts and rel.parts[0] in UNTRACKED_DIRS:
            continue
        if path.is_symlink():
            rep.error(path, "is a symlink (profile load paths are mounted read-only; "
                            "symlinks do not resolve the same way inside the sandbox)")
            continue
        if path.is_dir():
            continue
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size > MAX_FILE_BYTES:
            rep.error(path, f"is {size} bytes, over the 1 MB limit")


def check_claude_md(root: Path, rep: Report) -> None:
    path = root / "CLAUDE.md"
    if not path.is_file():
        return
    text = read_text(path, rep)
    if text is None:
        return
    lines = len(text.splitlines())
    if lines > CLAUDE_MD_WARN_LINES:
        rep.warn(path, f"is {lines} lines, over {CLAUDE_MD_WARN_LINES}; "
                       "it costs context in every session")


def check_settings(root: Path, rep: Report) -> None:
    path = root / "settings.json"
    if not path.is_file():
        return
    text = read_text(path, rep)
    if text is None:
        return
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        rep.error(path, f"is not valid JSON: {exc.msg} at line {exc.lineno} column {exc.colno}")
        return

    def walk(node: object) -> None:
        if isinstance(node, dict):
            env = node.get("env")
            if isinstance(env, dict):
                for key in env:
                    upper = str(key).upper()
                    for part in SECRET_KEY_PARTS:
                        if part in upper:
                            rep.error(
                                path,
                                f"env value for {key!r} looks like a credential "
                                f"(key contains {part}); keys belong in a 0600 file "
                                "outside the profile",
                            )
                            break
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(data)


def check_skills(root: Path, rep: Report) -> None:
    skills = root / "skills"
    if not skills.is_dir():
        return
    for entry in sorted(skills.iterdir(), key=lambda p: p.name):
        if not entry.is_dir():
            continue
        # Skills are one level deep: skills/<name>/SKILL.md. A SKILL.md any deeper is not
        # loaded, so it is a skill that silently does nothing.
        for nested in sorted(entry.rglob("SKILL.md")):
            if nested.parent != entry:
                rep.error(nested, "is a nested skill; skills are one level deep "
                                  "(skills/<name>/SKILL.md) and this one is not loaded")

        skill_md = entry / "SKILL.md"
        if not skill_md.is_file():
            rep.error(skill_md, "is missing (every skill directory needs a SKILL.md)")
            continue
        text = read_text(skill_md, rep)
        if text is None:
            continue
        front, err = parse_frontmatter(text)
        if front is None:
            rep.error(skill_md, err or "has unparseable frontmatter")
            continue
        for key in ("name", "description"):
            if not front.get(key):
                rep.error(skill_md, f"frontmatter is missing required key {key!r}")
        unknown = sorted(set(front) - SKILL_KEYS)
        if unknown:
            rep.warn(skill_md, "frontmatter has undocumented key(s) "
                               + ", ".join(repr(k) for k in unknown)
                               + "; check it is not a typo, then add it to SKILL_KEYS "
                                 "in tools/check.py")
        name = front.get("name", "")
        if name:
            if not SKILL_NAME_RE.match(name):
                rep.error(skill_md, f"frontmatter name {name!r} does not match "
                                    r"^[a-z0-9][a-z0-9-]{0,63}$")
            elif name != entry.name:
                rep.error(skill_md, f"frontmatter name {name!r} does not match "
                                    f"directory name {entry.name!r}")


def check_agents(root: Path, rep: Report) -> None:
    agents = root / "agents"
    if not agents.is_dir():
        return
    for path in sorted(agents.rglob("*.md")):
        text = read_text(path, rep)
        if text is None:
            continue
        front, err = parse_frontmatter(text)
        if front is None:
            rep.error(path, err or "has unparseable frontmatter")
            continue
        for key in ("name", "description"):
            if not front.get(key):
                rep.error(path, f"frontmatter is missing required key {key!r}")


def check_commands(root: Path, rep: Report) -> None:
    commands = root / "commands"
    if not commands.is_dir():
        return
    for path in sorted(commands.rglob("*.md")):
        text = read_text(path, rep)
        if text is None:
            continue
        if not text.strip():
            rep.error(path, "is empty")


def check_load_dirs(root: Path, rep: Report) -> None:
    """Load directories hold only loadable items.

    The harness loads whatever it finds in them, so a documentation file becomes a command or
    a skill. commands/README.md really did show up as /README. Documentation lives in
    docs/<dir>.md, which nothing mounts.
    """
    readme_problem = ("is documentation in a load directory, where the harness loads it as an "
                      "item; move it to docs/<dir>.md")

    skills = root / SKILL_LOAD_DIR
    if skills.is_dir():
        for entry in sorted(skills.iterdir(), key=lambda p: p.name):
            if entry.is_dir() and not entry.is_symlink():
                continue
            # Inside skills/<name>/ anything goes; directly in skills/ nothing is loadable.
            if entry.name.startswith("README"):
                rep.error(entry, readme_problem)
            else:
                rep.error(entry, "is a plain file directly in skills/, where nothing loads it; "
                                 "each skill needs its own skills/<name>/ directory")

    for name in FLAT_LOAD_DIRS:
        load_dir = root / name
        if not load_dir.is_dir():
            continue
        # Nested directories namespace items (commands/git/sync.md -> /git:sync), so a README
        # anywhere under here loads as an item.
        for path in sorted(load_dir.rglob("README*")):
            rep.error(path, readme_problem)
        for entry in sorted(load_dir.iterdir(), key=lambda p: p.name):
            if entry.is_dir() and not entry.is_symlink():
                continue
            if entry.name.startswith("README"):
                continue  # already reported above
            if entry.suffix != ".md":
                rep.error(entry, f"is not a .md file, so {name}/ cannot load it; "
                                 f"documentation goes in docs/{name}.md")


def load_plugins(root: Path) -> list[dict]:
    path = root / "plugins.toml"
    if not path.is_file():
        return []
    with path.open("rb") as handle:
        data = tomllib.load(handle)
    plugins = data.get("plugin", [])
    return [p for p in plugins if isinstance(p, dict)]


def check_plugins(root: Path, rep: Report) -> None:
    path = root / "plugins.toml"
    if not path.is_file():
        return
    try:
        plugins = load_plugins(root)
    except tomllib.TOMLDecodeError as exc:
        rep.error(path, f"is not valid TOML: {exc}")
        return
    seen: set[str] = set()
    for index, plugin in enumerate(plugins):
        where = f"[[plugin]] #{index + 1}"
        name = plugin.get("name")
        if not isinstance(name, str) or not name:
            rep.error(path, f"{where} is missing a name")
        elif not PLUGIN_NAME_RE.match(name):
            rep.error(path, f"{where} name {name!r} is not of the form 'plugin@marketplace'")
        elif name in seen:
            rep.error(path, f"{where} name {name!r} is declared twice")
        else:
            seen.add(name)
        label = name if isinstance(name, str) and name else where
        marketplace = plugin.get("marketplace")
        if not isinstance(marketplace, str) or not marketplace:
            rep.error(path, f"{label} is missing a marketplace")
        ref = plugin.get("ref")
        if not isinstance(ref, str) or not ref:
            rep.error(path, f"{label} is missing a ref; pin it to a 40-character commit sha")
        elif not HEX40_RE.match(ref):
            rep.error(path, f"{label} ref {ref!r} is not a 40-character hex commit sha")


def logical_lines(text: str) -> list[tuple[int, str]]:
    """Join backslash continuations. Returns (1-based start line, joined text)."""
    out: list[tuple[int, str]] = []
    buf: list[str] = []
    start = 1
    for number, line in enumerate(text.splitlines(), start=1):
        if not buf:
            start = number
        if line.rstrip().endswith("\\"):
            buf.append(line.rstrip()[:-1])
            continue
        buf.append(line)
        out.append((start, " ".join(buf)))
        buf = []
    if buf:
        out.append((start, " ".join(buf)))
    return out


def check_containerfile(root: Path, rep: Report) -> None:
    path = root / "Containerfile"
    if not path.is_file():
        return
    text = read_text(path, rep)
    if text is None:
        return

    joined = logical_lines(text)
    instructions = [
        (number, line.strip())
        for number, line in joined
        if line.strip() and not line.strip().startswith("#")
    ]
    if not instructions:
        rep.error(path, "has no instructions")
        return
    if not re.match(r"^ARG\s+BASE\s*$", instructions[0][1]):
        rep.error(path, f"line {instructions[0][0]}: first instruction must be 'ARG BASE', "
                        f"not {instructions[0][1]!r}")
    if len(instructions) < 2 or not re.match(r"^FROM\s+\$\{BASE\}\s*$", instructions[1][1]):
        found = instructions[1][1] if len(instructions) > 1 else "nothing"
        rep.error(path, f"second instruction must be 'FROM ${{BASE}}', not {found!r}")

    for number, line in instructions:
        verb = line.split(None, 1)[0].upper()
        if verb in ("USER", "ENTRYPOINT", "CMD"):
            rep.error(path, f"line {number}: must not set {verb} (agentbox owns it)")
        if URL_RE.search(line) and verb in ("RUN", "ADD"):
            if not SHA256_RE.search(line):
                rep.error(path, f"line {number}: downloads a URL without a sha256 checksum")
            elif "sha256sum" not in line and "shasum" not in line:
                rep.error(path, f"line {number}: has a sha256 digest but never verifies it "
                                "(pipe it through sha256sum -c -)")


CHECKS = (
    check_layout,
    check_files,
    check_claude_md,
    check_settings,
    check_load_dirs,
    check_skills,
    check_agents,
    check_commands,
    check_plugins,
    check_containerfile,
)


def main(argv: list[str]) -> int:
    args = argv[1:]
    list_plugins = False
    if args and args[0] == "--list-plugins":
        list_plugins = True
        args = args[1:]
    if args and args[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    if len(args) > 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    root = Path(args[0]).resolve() if args else Path(__file__).resolve().parent.parent
    if not root.is_dir():
        print(f"{root}: is not a directory", file=sys.stderr)
        return 2

    if list_plugins:
        try:
            for plugin in load_plugins(root):
                print(plugin.get("name", "?"), plugin.get("marketplace", "?"),
                      plugin.get("ref", "?"))
        except tomllib.TOMLDecodeError as exc:
            print(f"plugins.toml: is not valid TOML: {exc}", file=sys.stderr)
            return 1
        return 0

    rep = Report(root)
    for check in CHECKS:
        check(root, rep)
    return rep.print()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
