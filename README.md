# Agent Governance

**A control system for letting AI coding agents write production code — without letting them break it.**

I built a regulated e-signature platform alone in 70 days by having coding agents write nearly all of it. The platform is live: 3.7× the monthly contract volume of the system it replaced, and 99.97% of 1,625,586 requests served without a server error.

That did not happen because the agents were good. It happened because a stricter system decided whether what they wrote was allowed to ship.

This repository is that system, generalised: the hooks, the rules, the failure catalogue, and the harness that proves the guards can actually fail.

---

## The problem nobody's benchmark measures

A coding agent that writes a wrong function is a small problem. Your tests catch it.

The dangerous failures are different. In eight months of running agents against a live codebase I recorded **79 distinct ways they broke things** — and almost none of them were coding errors. They were **measurement errors**: a check that could not fail, a zero read as health, a grep that matched a comment, a regex that failed to compile and returned `null` into a file write.

A wrong edit gets reviewed. A wrong measurement gets *trusted*.

Ten of those 79 are documented in [`failures/`](failures/). Every one actually happened, on a system with paying customers. Each carries the mechanism and the rule that now prevents it.

---

## The five rules the system enforces

**1. Nothing is done until a command prints the evidence.**
"Tests pass" is not a claim an agent may make; it is a command whose output must appear in the same turn. Enforced by a Stop hook that blocks the turn if a completion word appears without a test run.

**2. The author never grades the author.**
Design, build, and adversarial review are three separate passes with a context boundary between them. The third exists only to prove the first two wrong. The same mind that produced a plan will produce the justification for it.

**3. A check that has never failed is not a check.**
Every guard is exercised by planting the exact defect it claims to catch and confirming it goes red. Each hook carries its own `--selftest`, and `install.sh` refuses to install if any guard passes a case it should have blocked.

**4. Two failed attempts mean the approach is wrong, not the parameters.**
Written into the rules the agent reads, because it is cheap to say and expensive to obey.

**5. Destructive operations are blocked at the tool boundary, not by instruction.**
An agent that has been *told* not to force-push will eventually force-push. A `PreToolUse` hook that exits non-zero cannot be talked out of it.

---

## What is in here

```
hooks/          PreToolUse / PostToolUse / Stop hooks — the enforcement layer
rules/          the doctrine an agent reads before it acts (start with verification.md)
failures/       ten dated, real failure modes, each with its guard
install.sh      copies the hooks in — after running every self-test and refusing if one fails
settings.example.json
```

| Hook | Fires on | What it refuses |
|---|---|---|
| `pre-bash-destructive-guard.sh` | Bash | force-push, history rewrite, recursive delete outside the worktree, production commands with no confirmation token |
| `pre-edit-protect-paths.sh` | Edit/Write | edits to lockfiles, CI config, secrets, and any path on the project's protected list |
| `stop-require-evidence.sh` | Stop | ending a turn that claims completion without a command having been run |
| `post-bash-audit.sh` | Bash | nothing — it records every command to an append-only log |

All hooks are POSIX shell with no dependencies, and each one **self-tests**: `./hooks/<name>.sh --selftest` asserts both that violations are caught and that ordinary commands are not. Current totals: 33 assertions on the destructive guard, 15 on path protection, 9 on the evidence gate.

Those self-tests found three real defects in the destructive guard before a line of it shipped — including a field separator that made every rule silently unreachable, so the guard was installed, reporting success, and matching nothing. That is the argument of this repository, demonstrated on itself.

---

## Install

```bash
git clone https://github.com/eArash/agent-governance
cd agent-governance
./install.sh /path/to/your/project
```

`install.sh` runs every guard's self-test FIRST and refuses to install if one fails, then copies the hooks and prints the `settings.json` fragment for you to merge by hand.

Then read [`rules/verification.md`](rules/verification.md) first. It is short, and it is the one that does most of the work.

---

## What this is not

It is not a benchmark, a framework, or a wrapper around a model. It is 367 lines of shell and a set of written rules. The value is not the code — it is the **catalogue of what actually goes wrong**, which took a live production system and eight months to collect.

If you are running agents against code that people pay to use, read [`failures/`](failures/) before you read anything else here. It will save you at least one incident.

---

## Who wrote this

Arash Banaeian — CTO at [elEMZA](https://elemza.com), an electronic and digital signature platform. I build systems that model the people who use them, and I ship them in weeks rather than quarters.

More: **[elemza.com/arash](https://elemza.com/arash)** · arash.bne@gmail.com

Available for 3–4 month builds and fractional CTO work.

## Licence

MIT. Use it, change it, ship it.
