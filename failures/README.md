# Ten ways a coding agent broke production

Every entry below actually happened, on a live platform with paying customers, between January and September 2026. They are drawn from a catalogue of 79.

They are ordered by how convincingly each one *looked fine*.

**The pattern across almost all of them: they were measurement errors, not coding errors.** The code was usually correct. What went wrong was believing a broken instrument — a check that could not fail, a zero read as health, a green from a tool that was measuring nothing. A wrong edit gets reviewed. A wrong measurement gets trusted.

---

## 1. Never write a transform result you have not checked

**What happened.** A bulk migration was run as an inline `php -r` one-liner through bash. The shell collapsed the escaping, PCRE read `\F` as an unsupported escape, the pattern **failed to compile**, and `preg_replace()` returned `null`. The next line wrote that `null` to disk. **Sixteen source files — five to thirty-seven kilobytes each — became zero bytes and were committed.**

**Why it survived review.** `php -l` reports *no syntax errors* on an empty file. The classes then report as "not found", which reads like a namespace problem, not a deletion.

**The rule.** Transform scripts live in a file, never an inline one-liner through a shell. Before writing, assert the result is non-null, non-empty, still contains the file's opening token, and has not shrunk by more than a plausible amount. Add `find . -name '*.ext' -size 0` to any bulk-edit workflow.

---

## 2. A guard that cannot fail is indistinguishable from a guard that passed

**What happened.** A content-safety probe reported "all 9 documents survive intact". Its negative control then revealed that the editor being tested **preserves unknown nodes untouched** — so the probe could not have detected loss at all. Nine green lines meant nothing.

**The rule.** Every assertion ships with a negative control: plant the failure and confirm the check reports it. A guard that has never been seen to fail is decoration. This is the single highest-value idea in this repository, and `bin/guard-exercise.sh` exists to make it cheap.

---

## 3. A zero is not evidence

**What happened.** After a deploy at 03:57, "0 errors today" was nearly reported as a clean result. It was 07:00 and the platform has no traffic before business hours. Every one of the previous eight days shows activity starting mid-morning. The honest statement was "no real user has exercised this yet". The actual proof arrived at 13:00, with 633 log lines and no errors.

**The rule.** Before reading an absence as health, ask what the number looks like when the thing is simply *not being used*. If "healthy" and "nobody tried" produce the same reading, you have not measured anything.

---

## 4. The instrument logged the alarm and dropped the evidence — and the obvious search keyed on the evidence

**What happened.** An admin panel had been taking 10–26 seconds per page for a day. The slow-request log had been recording it faithfully the entire time:

```
WARNING: [pool www] child 81, script '.../index.php' executing too slow (12.4 sec), logging
ERROR:   failed to ptrace(ATTACH) child 81: Operation not permitted
```

The container lacked `CAP_SYS_PTRACE`, so the logger wrote the **duration** and then could not dump the **stack**. The first search was for the marker that appears at the top of a stack dump — and it returned **0 across 30 hours**. That zero was one sentence away from being reported as "no request has been slow." The real answer was 94 slow requests that day against 3 the day before.

**The rule.** Search for the **alarm**, not for the payload the alarm usually carries. Before believing a zero from any log, find one known-true instance and confirm your pattern matches it. And when an instrument reports a partial failure of itself, that line *is* the finding — it tells you which half of the answer you are missing.

---

## 5. A pipe throws away the exit code — and `| tail` throws away the evidence too

**What happened.** An agent ran `npm run build 2>&1 | tail -15` in the background. The harness reported **"completed (exit code 0)"** and the agent believed the build had succeeded. It had not: the bundler had died and the output directory was never created. In a pipeline the reported status is the **last** command's, so `tail` succeeding masked the build failing.

Thirty minutes later the same agent ran the full test suite the same way and got 98 failures. Because of the pipe, the captured output was 3,237 bytes: the list of *which* tests failed had been discarded by its own command. The number 98 was compatible with two opposite conclusions — "my change broke the suite" and "my environment has no compiled assets" — and nothing in hand could distinguish them.

**The rule.** Never pipe a command whose exit code you intend to trust: `cmd > file 2>&1; echo "exit: $?"`, then read the file. Never pipe a test run through `head`/`tail` — the failure list is the entire value of a red run.

---

## 6. "Flaky" is a diagnosis you have to earn

**What happened.** A CI job went red and stayed red for two days while the same check reported 99/99 PASS locally on the same commit. An agent recorded it as environment-sensitive flakiness and moved on. Two later sessions read that note and skipped past a red check.

It was never flaky. It failed deterministically, for one reason: `git branch --show-current` prints an empty string and **exits 0** on a detached HEAD, and CI checks out a detached merge ref. The `|| echo main` fallback written to cover exactly this had never executed once, because `||` tests the exit status and the exit status was 0.

**The rule.** A command that succeeds with empty output defeats `cmd || fallback`. If absence of output is a real state, test the output, never the exit code. And reproduce outside CI before calling anything flaky — "passes on my machine, fails in CI, therefore flaky" is a conclusion that requires no evidence and is available for every environment-dependent bug.

---

## 7. Splitting on `\R` cuts UTF-8 in half, and a size check will never notice

**What happened.** A transform split a source file with `preg_split('/\R/', $source)`. Without the `/u` modifier, PCRE's `\R` matches the single byte `0x85` — which is not a line break in a UTF-8 file, it is an ordinary **continuation byte inside a multi-byte character**. The split cut seventeen non-ASCII characters in half and rejoined the halves with newlines, corrupting a user-facing error message.

Every check passed: the linter (the mangled bytes sat inside a valid string literal), the 441-test suite (no test asserted on that message), and the script's own guard — which checked the file had not *shrunk* by more than 2%. **The corruption added bytes.** A size floor cannot see damage that grows.

**The rule.** Split on `"\n"`, never `\R`, when text may be non-ASCII. A size check is not an integrity check: assert valid encoding, **zero replacement characters**, unchanged non-ASCII character count, unchanged line count, and byte growth equal to exactly the text you meant to insert.

---

## 8. Asserting the setting instead of the rendering

**What happened.** A UI defect was reported: two navigation columns eating 45% of the screen. The fix looked like one line — a framework property on the parent class. A test asserted the property. It passed. The full suite passed. It was deployed, verified as HTTP 200, and reported as fixed.

The framework never reads that property from the parent. Every page asks its own child class, and the five children still carried the default. **The line was dead code, and the test asserted exactly that dead line, so it could not have failed.** The user sent a second screenshot: the column was still there, pixel for pixel.

**The rule.** For anything whose only effect is visible in output, assert the **output** — rendered markup, the emitted header, the generated file. A property's value proves the property was set, never that anything reads it. Before trusting a framework setting, find the line that reads it.

---

## 9. A mutation harness that commits its mutants puts a planted defect one merge from production

**What happened.** An agent needed to prove its guards could fail, so it planted defects and ran the suite. The harness was killed by a timeout three times, and **twice it left the planted mutation committed with a clean `git status`** — the one state in which nothing looks wrong. One of those commits was pushed. Its payload was exactly what the guards existed to catch: a working call-to-action replaced with a hollow one, and a working link replaced with `href="#"`.

Later commits happened to restore both. That is luck, not a mechanism.

**The rule.** A mutation harness must never commit. Plant in the working tree, run, restore, and assert the restore — with the restore in a `finally`, because a timeout is the normal case for a harness, not the exception. After any session that plants defects, grep the branch **history**, not the tree: a committed mutation is invisible to `git status` and to a guard run at HEAD.

---

## 10. A feature can be fully built, fully tested, and have zero callers

**What happened.** A review of one subsystem turned up six capabilities that were built, mostly tested, and completely inert. The worst: an "exclude this customer from billing" control that was offered in the admin form, stored a row, and displayed an active badge — while the function that reads exclusions **was never called with that type**. Production had one active row of exactly that kind. An operator had pressed the button, received a green confirmation, and that customer kept being billed.

**The rule.** Before counting a capability as present, grep for its **callers**, not for itself: `grep -rn "methodName(" src/ | grep -v "<the file that defines it>"`. Zero is conclusive and takes seconds. A passing unit test proves the method works; it says nothing about whether anything invokes it. Write the caller in the same commit as the method, or do not write the method.

---

## Two more, from the week this repository was published

**11. A nowrap track grows the container, not the page — and the height check reads zero.**
Two lines of text were added to a print layout. They pushed a grid track 394 pixels past the page edge. `scrollHeight` reported **zero overflow** the entire time, because the track grew inside the grid rather than extending the page. Only a check that measured the right edge of a text `Range` against the content box saw it. *Know what your instrument cannot see.*

**12. A green from an instrument that was measuring nothing.**
A cleanup pass applied `ltrim($new, ".")` to a batch of CSS edits. It was written for one entry and stripped the leading dot from another, turning the selector `.page{` into `page{`. The page rule then matched nothing: no width, no height, no padding. The layout check came back **overflow 0, offenders 0, trailing 0** — a perfect green from a page that had collapsed to its own content. It was caught only because a sibling file reported 100px of unexplained white space and a direct probe showed `display: block`. *When a fix makes a number better than you expected, probe the mechanism before believing it.*

---

## How to use this file

Before you write a bulk edit, a guard, a measurement script, or a production command, find the matching entry and satisfy its rule. When your agents cause a new one, add it — with the date, what it actually broke, and the rule. An entry with no dated incident behind it does not belong here.
