# agent-governance

Rules and hooks for running AI coding agents on a production codebase: what they may run, what they may edit, and what counts as evidence that work is finished.

Extracted from the engineering system of [elEMZA](https://elemza.com), a regulated electronic-signature platform in production since April 2026. Product-specific names have been removed; mechanisms and rules are unchanged.

## Contents

```
hooks/                  enforcement: PreToolUse, PostToolUse and Stop hooks (POSIX shell, no dependencies)
rules/verification.md   what counts as evidence of "done"
rules/operating-system.md  the layers around the hooks: context, task specification, review, instruments
failures/README.md      34 recorded failure modes, each with its mechanism and the rule that now prevents it
install.sh              runs every self-test, refuses to install on any failure, then copies the hooks
settings.example.json   hook registration fragment
```

| Hook | Event | Blocks | Self-test |
|---|---|---|---|
| `pre-bash-destructive-guard.sh` | Bash | force-push, history rewrite, recursive delete outside the worktree, unconfirmed production commands | 33 assertions |
| `pre-edit-protect-paths.sh` | Edit / Write | lockfiles, CI configuration, secrets, project-listed protected paths | 15 assertions |
| `stop-require-evidence.sh` | Stop | a completion claim in a turn where no command was run | 9 assertions |
| `post-bash-audit.sh` | Bash | nothing; appends every command to an audit log | n/a |

Each hook accepts `--selftest`, which checks that violations are caught and that ordinary commands pass. Hooks and installer total 367 lines.

## Rules

1. **Completion requires evidence in the same turn.** "Tests pass" must be the output of a command, not a sentence.
2. **Separate the author from the reviewer.** Design, build and adversarial review run as separate passes with a context boundary between them.
3. **Every guard is shown to fail.** Plant the defect the guard claims to catch and confirm it fires. A check that has never failed has not been tested.
4. **Two failed fixes mean the approach is wrong.** Change the approach, not the parameters.
5. **Destructive operations are blocked at the tool boundary.** An instruction can be ignored; a hook that exits non-zero cannot.

## Failure catalogue

Most entries in [`failures/`](failures/) are measurement errors rather than coding errors: a check that could not fail, a zero read as health, an exit code lost in a pipe, a regex that failed to compile and returned `null` into a file write. Each entry gives what happened, why existing checks missed it, and the rule adopted afterwards.

## Install

```bash
git clone https://github.com/eArash/agent-governance
cd agent-governance
./install.sh /path/to/your/project
```

The installer prints the `settings.json` fragment; merge it by hand. Read `rules/verification.md` first.

## Scope

A set of rules and shell hooks, not a framework or a model wrapper. The hooks target Claude Code's hook interface; the rules apply to any agent setup.

## Author

[Arash Banaeian](https://github.com/eArash) · [elemza.com/Arash](https://elemza.com/Arash)

## Licence

MIT
