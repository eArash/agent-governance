# The verification rule

> Read this one first. It is short, and it does most of the work.

**No completion claim without fresh evidence in the same turn.**

"Tests pass", "fixed", "deployed", "the migration ran", "it works" — none of these are sentences an agent may write. Each is a command whose output must appear alongside it.

| Claim | What has to be in the turn |
|---|---|
| tests pass | the test command and its summary line |
| the migration ran | the migration status output |
| I edited file X | `git diff --stat -- X` |
| it is deployed | the deployed revision, read back from the running system |
| the guard works | the guard failing against a planted defect, then passing |

## Why this one rule and not twenty

Because the failure it prevents is the one that costs the most: an agent that *believes* a thing is done stops looking, and everything downstream is built on the belief. A wrong edit gets reviewed. A wrong belief gets trusted.

And because it is checkable. `stop-require-evidence.sh` blocks a turn that ends on a claim with no command behind it. A rule you can enforce beats five rules you can only hope for.

## The three corollaries that catch the rest

**1. Name what your evidence cannot prove.**
A passing unit test does not prove the user's path works. HTTP 200 does not prove the page renders. A green suite does not prove the feature is reachable. Every "done" states the gap it is leaving.

**2. A check that has never failed is not a check.**
Plant the defect it claims to catch and watch it go red. If it stays green, you have installed a decoration. Run this against every guard you write, on the day you write it — a guard is at its most trustworthy and least tested in the hour it is born.

**3. Cite only what you have read in this session.**
A file path, a function name, a line number, a commit hash — if it came from memory rather than from a read in this turn, say "I have not verified this". Confident citation of a file that does not exist is the most expensive sentence an agent produces, because it is indistinguishable from a correct one.

## What this costs

Time, and tokens. Both are cheaper than one incident, and much cheaper than the review culture that grows around an agent nobody can trust.
