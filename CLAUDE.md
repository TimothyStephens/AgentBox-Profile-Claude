DRAFT: Tim to review

# Standing rules

These apply in every project, in every session.

## Secrets and data

- Never read `.env` files, secrets, credentials, or live production data. If a task seems to
  need one, stop and say which file you wanted and why.
- Keys and tokens reach a program through a `0600` file that the program reads itself. Never
  paste one into a command line, a source file, a config file, or a commit.

## Other people's changes

- Never revert, stage, or commit a change you did not make. If the working tree has edits that
  are not yours, report them and leave them alone.
- Commit after each step that is green, with a message that says what now works ("manifest
  validation rejects duplicate locations"), not what was touched ("update validator").

## Verifying

- Run the tests yourself and read the output. Do not hand me a command to copy.
- A run with any excused, skipped, or expected-failure error category is not green. Say
  "unverified" and show the output.
- Report what the output says, not what it was supposed to say.

## Design docs and decisions

- When the implementation deviates from a project's design doc, record it in
  `docs/decisions.md`: the date, what changed, and why.

## Tools

- EGM writes its artifacts to `.dev/docs`.

## Environment

- Sessions run inside an agentbox sandbox. The user-level `CLAUDE.md`, `skills/`, `agents/`, and
  `commands/` are read-only mounts; `settings.json` is copied fresh at each session start, so
  in-session settings changes do not survive. Durable changes go in the profile repo
  (`agentbox-profile-claude`).
- To leave a skill, sub-agent, or note for a later session, write it under
  `/run/agentbox/claude/inbox` with a sentence on why it is worth keeping.
