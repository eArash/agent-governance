# 34 ways a coding agent broke production

Every entry below actually happened, on a live platform with paying customers, between January and September 2026. They are drawn from a private catalogue of 93.

They are ordered by how convincingly each one *looked fine*.

**The pattern across almost all of them: they were measurement errors, not coding errors.** The code was usually correct. What went wrong was believing a broken instrument - a check that could not fail, a zero read as health, a green from a tool that was measuring nothing. A wrong edit gets reviewed. A wrong measurement gets trusted.

---

## 1. Never write a transform result you have not checked

**What happened.** A bulk migration was run as an inline `php -r` one-liner through bash. The shell collapsed the escaping, PCRE read `\F` as an unsupported escape, the pattern **failed to compile**, and `preg_replace()` returned `null`. The next line wrote that `null` to disk. **Sixteen source files - five to thirty-seven kilobytes each - became zero bytes and were committed.**

**Why it survived review.** `php -l` reports *no syntax errors* on an empty file. The classes then report as "not found", which reads like a namespace problem, not a deletion.

**The rule.** Transform scripts live in a file, never an inline one-liner through a shell. Before writing, assert the result is non-null, non-empty, still contains the file's opening token, and has not shrunk by more than a plausible amount. Add `find . -name '*.ext' -size 0` to any bulk-edit workflow.

---

## 2. A guard that cannot fail is indistinguishable from a guard that passed

**What happened.** A content-safety probe reported "all 9 documents survive intact". Its negative control then revealed that the editor being tested **preserves unknown nodes untouched** - so the probe could not have detected loss at all. Nine green lines meant nothing.

**The rule.** Every assertion ships with a negative control: plant the failure and confirm the check reports it. A guard that has never been seen to fail is decoration. This is the single highest-value idea in this repository, and `bin/guard-exercise.sh` exists to make it cheap.

---

## 3. A zero is not evidence

**What happened.** After a deploy at 03:57, "0 errors today" was nearly reported as a clean result. It was 07:00 and the platform has no traffic before business hours. Every one of the previous eight days shows activity starting mid-morning. The honest statement was "no real user has exercised this yet". The actual proof arrived at 13:00, with 633 log lines and no errors.

**The rule.** Before reading an absence as health, ask what the number looks like when the thing is simply *not being used*. If "healthy" and "nobody tried" produce the same reading, you have not measured anything.

---

## 4. The instrument logged the alarm and dropped the evidence - and the obvious search keyed on the evidence

**What happened.** An admin panel had been taking 10-26 seconds per page for a day. The slow-request log had been recording it faithfully the entire time:

```
WARNING: [pool www] child 81, script '.../index.php' executing too slow (12.4 sec), logging
ERROR:   failed to ptrace(ATTACH) child 81: Operation not permitted
```

The container lacked `CAP_SYS_PTRACE`, so the logger wrote the **duration** and then could not dump the **stack**. The first search was for the marker that appears at the top of a stack dump - and it returned **0 across 30 hours**. That zero was one sentence away from being reported as "no request has been slow." The real answer was 94 slow requests that day against 3 the day before.

**The rule.** Search for the **alarm**, not for the payload the alarm usually carries. Before believing a zero from any log, find one known-true instance and confirm your pattern matches it. And when an instrument reports a partial failure of itself, that line *is* the finding - it tells you which half of the answer you are missing.

---

## 5. A pipe throws away the exit code - and `| tail` throws away the evidence too

**What happened.** An agent ran `npm run build 2>&1 | tail -15` in the background. The harness reported **"completed (exit code 0)"** and the agent believed the build had succeeded. It had not: the bundler had died and the output directory was never created. In a pipeline the reported status is the **last** command's, so `tail` succeeding masked the build failing.

Thirty minutes later the same agent ran the full test suite the same way and got 98 failures. Because of the pipe, the captured output was 3,237 bytes: the list of *which* tests failed had been discarded by its own command. The number 98 was compatible with two opposite conclusions - "my change broke the suite" and "my environment has no compiled assets" - and nothing in hand could distinguish them.

**The rule.** Never pipe a command whose exit code you intend to trust: `cmd > file 2>&1; echo "exit: $?"`, then read the file. Never pipe a test run through `head`/`tail` - the failure list is the entire value of a red run.

---

## 6. "Flaky" is a diagnosis you have to earn

**What happened.** A CI job went red and stayed red for two days while the same check reported 99/99 PASS locally on the same commit. An agent recorded it as environment-sensitive flakiness, noted it should be fixed separately, and moved on. Two later sessions read that note and skipped past a red check.

It was never flaky. It failed **deterministically, for one reason**: `git branch --show-current` prints an empty string and **exits 0** on a detached HEAD, and CI checks out a detached merge ref. The `|| echo main` fallback written to cover exactly this had never executed once, because `||` tests the exit status and the exit status was 0.

**Why it survived.** The local run and the CI run disagreed, and the local run was the one anybody looked at. "Passes on my machine, fails in CI, therefore flaky" is a conclusion that requires no evidence, and it is available for every environment-dependent bug.

**The rule.** A command that succeeds with empty output defeats `cmd || fallback`. If absence of output is a real state, test the output (`[ -z "$x" ]`), never the exit code. Reproduce outside CI before calling anything flaky - a bug you can reproduce on demand is not intermittent. And a permanently one-red suite is worse than a broken one, because "1 wrong" becomes the normal reading of the world and the next genuine failure looks identical to it.

---

## 7. Splitting on `\R` cuts UTF-8 in half, and a size check will never notice

**What happened.** A transform split a source file with `preg_split('/\R/', $source)`. Without the `/u` modifier, PCRE's `\R` matches the single byte `0x85` - which is not a line break in a UTF-8 file, it is an ordinary **continuation byte inside a multi-byte character**. The split cut seventeen non-ASCII characters in half and rejoined the halves with newlines, corrupting a user-facing error message.

Every check passed: the linter (the mangled bytes sat inside a valid string literal), the 441-test suite (no test asserted on that message), and the script's own guard - which checked the file had not *shrunk* by more than 2%. **The corruption added bytes.** A size floor cannot see damage that grows.

**The rule.** Split on `"\n"`, never `\R`, when text may be non-ASCII. A size check is not an integrity check: assert valid encoding, **zero replacement characters**, unchanged non-ASCII character count, unchanged line count, and byte growth equal to exactly the text you meant to insert.

---

## 8. Asserting the setting instead of the rendering

**What happened.** A UI defect was reported: two navigation columns eating 45% of the screen. The fix looked like one line - a framework property on the parent class. A test asserted the property. It passed. The full suite passed. It was deployed, verified as HTTP 200, and reported as fixed.

The framework never reads that property from the parent. Every page asks its own child class, and the five children still carried the default. **The line was dead code, and the test asserted exactly that dead line, so it could not have failed.** The user sent a second screenshot: the column was still there, pixel for pixel.

**The rule.** For anything whose only effect is visible in output, assert the **output** - rendered markup, the emitted header, the generated file. A property's value proves the property was set, never that anything reads it. Before trusting a framework setting, find the line that reads it.

---

## 9. A mutation harness that commits its mutants puts a planted defect one merge from production

**What happened.** An agent needed to prove its guards could fail, so it planted defects and ran the suite. The harness was killed by a timeout three times, and **twice it left the planted mutation committed with a clean `git status`** - the one state in which nothing looks wrong. One of those commits was pushed. Its payload was exactly what the guards existed to catch: a working call-to-action replaced with a hollow one, and a working link replaced with `href="#"`.

Later commits happened to restore both. That is luck, not a mechanism.

**The rule.** A mutation harness must never commit. Plant in the working tree, run, restore, and assert the restore - with the restore in a `finally`, because a timeout is the normal case for a harness, not the exception. After any session that plants defects, grep the branch **history**, not the tree: a committed mutation is invisible to `git status` and to a guard run at HEAD.

---

## 10. A feature can be fully built, fully tested, and have zero callers

**What happened.** A review of one subsystem turned up six capabilities that were built, mostly tested, and completely inert. The worst: an "exclude this customer from billing" control that was offered in the admin form, stored a row, and displayed an active badge - while the function that reads exclusions **was never called with that type**. Production had one active row of exactly that kind. An operator had pressed the button, received a green confirmation, and that customer kept being billed.

**The rule.** Before counting a capability as present, grep for its **callers**, not for itself: `grep -rn "methodName(" src/ | grep -v "<the file that defines it>"`. Zero is conclusive and takes seconds. A passing unit test proves the method works; it says nothing about whether anything invokes it. Write the caller in the same commit as the method, or do not write the method.

---

## 11. A nowrap track grows the container, not the page - and the height check reads zero

Two lines of text were added to a print layout. They pushed a grid track 394 pixels past the page edge. `scrollHeight` reported **zero overflow** the entire time, because the track grew inside the grid rather than extending the page. Only a check that measured the right edge of a text `Range` against the content box saw it. *Know what your instrument cannot see.*

---

## 12. A green from an instrument that was measuring nothing

A cleanup pass applied `ltrim($new, ".")` to a batch of CSS edits. It was written for one entry and stripped the leading dot from another, turning the selector `.page{` into `page{`. The page rule then matched nothing: no width, no height, no padding. The layout check came back **overflow 0, offenders 0, trailing 0** - a perfect green from a page that had collapsed to its own content. It was caught only because a sibling file reported 100px of unexplained white space and a direct probe showed `display: block`. *When a fix makes a number better than you expected, probe the mechanism before believing it.*

---

## 13. `git commit -m` executes backticks

**What happened.** A commit message containing a backtick-quoted shell command ran it, and the entire resolved output - including a credential - was embedded in the message. Caught before the push and amended.

**The rule.** `git commit -F -` with a quoted heredoc, always. After a push, a message cannot be amended without rewriting shared history.

---

## 14. The requested scope is the deliverable

**What happened.** Asked why a footer phone number had not been fixed, an agent fixed the phone number **and also** rewrote unrelated field labels it had noticed in passing. Nobody had asked for that. It was reverted.

**The rule.** Finding a real problem while doing something else earns a **sentence**, not a commit. Say what you found, finish what was asked, and let the owner decide.

---

## 15. A subagent's report is a snapshot, and snapshots go stale

**What happened.** A fifty-minute audit returned six BROKEN-NOW findings. Most had been fixed hours earlier - the agent had read the tree as it was when it started. A second agent's "the admin panel is down" turned out to be a race with edits being made in the same worktree while it ran, which the agent itself flagged.

**The rules.**
- Verify every subagent finding against the tree **as it is now** before acting or reporting.
- Do not run a long read-only audit against a worktree you are actively editing. Give it a copy, or wait.
- An agent honest enough to say "this might be a race" is doing its job - read those caveats.

---

## 16. The config file and the runtime disagreed, and the config file was the one that was wrong

**What happened.** A hot-patch had to ship one new class. Before restarting, the question was whether the autoloader would find it. The config said one thing, the generated loader file did not mention the setting at all - so both readings agreed the fallback would work. Both readings were correct about their files and **both were wrong about the machine**: the loader's own runtime flag, queryable directly, returned true. It had been generated with the flag on, and nothing in the two files that were read recorded that.

Had the container restarted on the wrong reading, every reference to the new class would have fatalled - during business hours, from a change whose whole purpose was to make the system faster.

**The rules.**
- **Ask the running system, not the file that configures it.** A config file describes intent at install time; a deployed artefact is the result of whatever flags were actually passed.
- **A control is what turns confusion into an answer.** A probe that returns false for the new class reads, alone, as "my probe is broken". Running the identical probe against a class known to be present, and one shipped in the same batch that already existed, proves the probe works and isolates the failure to *new* classes.
- **Hot-patching a new class is not the same operation as hot-patching an edited one.** An edited file is already in the classmap; a new one is not. Regenerate the classmap inside the container and re-verify, or the file is inert.
- **Verify before the restart, not after.** The old code kept serving from the bytecode cache the entire time the broken state sat on disk, which is what made the check free.

---

## 17. A read-only investigation is not read-only if it clears a cache

**What happened.** While diagnosing a slow page, an agent invalidated a health-check cache key six times in a few minutes to measure a cold build. That key is the only thing standing between a page render and a 22-second timeout wait. During that window a real user was browsing, and two of their page loads were aggravated by the measurement.

**Why it slipped through.** The probes were read-only queries and were reasoned about as read-only. Nothing was written, nothing was deleted - but *invalidating* shared state is a mutation with a latency cost, and on a short-lived cache the blast radius is every user who arrives before it refills.

**The rules.**
- A probe that clears, warms, expires or locks shared state is a WRITE. Count it as one when deciding whether it may run on production.
- If you must measure a cold path in production, measure it **once**, restore the warm value immediately, and say in the report which of your own numbers your measurement produced.
- Prefer measuring a copy of the value over invalidating the real one.

---

## 18. A screenshot is a crop, and the browser silently ignored the width it was given

**What happened.** A UI card was screenshotted headless at a fixed window size to check a mobile layout. The card came back clipped on the right - clipped with the new component and, in a control render, clipped without it too. That reads as a pre-existing defect on the highest-traffic page the product has.

There was no defect. The window-size flag is honoured for the screenshot capture but **ignored for a DOM dump**, and a proper viewport probe reported the *same* rendered width for three different requested widths. Three green results, none of them measured at the width asked for. The flag had already produced the misleading picture: the image is the requested width, but it is a **crop** of a render at the browser's own viewport. A component that fits perfectly at the real width looks amputated in the crop, and a component that genuinely overflows looks identical.

**The rules.**
- Render inside a same-origin iframe with an explicit width, and measure `clientWidth`, `scrollWidth` and each element's bounding box from the parent. An iframe is a real CSS viewport; a browser flag is a request the browser may decline.
- A viewport probe must report the width it actually got. If the number you asked for is not in the output, the run proved nothing.
- Screenshot and measurement are two different questions. "Does it look right" and "does it overflow" cannot be answered by the same artefact, because cropping makes them look the same.
- Check the control before believing a pre-existing defect. Rendering the page with the new component removed is what stopped this being reported as a bug in unrelated code.

---

## 19. "Out of memory" is a diagnosis that can never be refuted, so it stops the investigation

**What happened.** Eleven headless screenshots produced nothing, and the failure - "abnormal renderer termination" - was attributed to memory pressure. Five configurations were tried: different headless modes, unique data directories, a capped heap, a shrunk viewport. All died the same way. The visual check was recorded as not met, and the machine was blamed.

Three controls, run in two minutes the next day, refuted the whole thing: a trivial page from a local file rendered fine; the actual target page over HTTP died; the same target page from a local file rendered fine. Memory was never the constraint - something in the HTTP path was killing the renderer.

**Why it survived five attempts.** The harness piped the browser's stderr to `/dev/null`. The actual error message was never read once. Every "attempt" was a guess evaluated against a silent instrument.

**The rules.**
- A measuring tool must **keep stderr**. If you cannot see why it failed, you are not debugging, you are permuting.
- Before accepting a cause, run a positive control and vary one variable. "It's memory" / "it's the network" / "it's flaky" are unfalsifiable by construction: always available, never disproved, and therefore end the search.
- Stopping after five attempts was right. Stopping without ever reading the error was the bug.

---

## 20. Fifteen numbers are small enough that nobody checks the sum

**What happened.** A scoring document averages fifteen rubric factors, and that mean is the gate that decides whether work may close. It was written by hand, three times, and **all three were wrong** - the last error was exactly the width of the difference between clearing the gate and not.

**Why it survived.** Adding fifteen numbers looks too simple to be worth verifying. Every other claim in the document carried a command and its output; this one carried nothing, because it did not feel like a measurement. It felt like arithmetic. This happened in a document whose entire subject is *do not assert a number you have not measured*, written by the session that had spent the day cataloguing exactly that failure. Knowing about a trap does not protect you from it - only machinery does.

**The rules.**
- A number that lands in a document must come from something you can re-run.
- The re-run script's own first version was wrong too, in the same family: run against an unrelated table, it scraped fifteen rows from the wrong place and reported a confident wrong average instead of refusing. A row-count guard is not enough - you must also know *which table you counted*.
- The negative control is what caught it: running the tool where it should find nothing is worth as much as running it where it should find something.
---

## 21. A cleanup that cannot tell "dead" from "not mine" will delete someone else's live work

**What happened.** A CI runner had once lost a container to a killed local run, leaving source on the remote server - explicitly forbidden. The fix looked obvious: sweep orphans at the start of every run. It swept every container and volume matching the runner's naming pattern.

Two hours later a full suite ran 25 minutes, **finished**, printed its pass count - and then died fetching its own log: *no such container*. A second run had started while the first was still going, and its sweep had removed the first run's container out from under it. The naming pattern had been made unique *on purpose*, precisely so two runs could not collide - the comment saying so was three lines above the sweep that broke it.

**The rules.**
- "Orphan" means **dead**, not "not mine". Filter on exited/dangling status, and for anything keyed by a process id, check whether the owning process still exists before deleting.
- A cleanup is a destructive operation on shared state. Ask what it does when someone else is mid-flight, before writing it, not after.
- The concurrency guarantee was documented in the same file, immediately above the change. Reading the lines you are editing between is not optional.

---

## 22. A status sentence in a rules file is a claim, not a measurement

**What happened.** A governing doctrine file said a feature was "NOT deployed to production". It had shipped **seventeen days earlier**, and a deploy log recorded it under a heading nobody had cross-read. One `git merge-base --is-ancestor` settles the question in two seconds.

Underneath sat one conflation: **"deployed" and "reachable by users" are different facts.** The feature was deployed and gated behind a feature flag. Collapsing the two turned a settings flip into a phantom deploy, and made a shipped product look unbuilt. A second file carried the identical failure at the same moment, for a different subsystem - a doctrine document had already *flagged* that file's status claims as unreliable, and the file itself was never corrected. A warning about a wrong file is not a fix: the next reader reads the file, not the warning.

**The rules.**
- Before repeating any deploy status from a doc, measure it against the actual deployed artefact.
- Write status lines with a date and the evidence, never a bare adjective. A dateless "not deployed" cannot be aged, so it never expires and never gets re-checked.
- State the gate separately from the deploy. "Deployed, hidden behind a flag" is two facts; "not deployed" is neither of them.
- When you find a stale claim, fix the file that says it - not a warning somewhere else.

---

## 23. A discrepancy is a claim about TWO instruments, and I only checked one of them

**What happened.** Verifying another session's production table, three of its four rows reproduced to the digit and the fourth did not. Two explanations were tested and both refuted. On that basis the row was reported as someone else's defect - written up, committed, and told to the owner.

It was mine. The artefact stated, in its own text, that it counted two conditions together; the verifying query used only one of them. Adding the missing filter reproduced all three numbers exactly. The gap was entirely rows in a state the original author had accounted for and the verifier had not.

**Why the two refuted hypotheses made it worse.** Testing them felt like rigour, and both coming back negative felt like confirmation. Every hypothesis tested was about *their* measurement. Not one was about mine. Two failed explanations should have been the signal to turn the instrument around, and instead they were read as narrowing the case against the original author.

**The rules.**
- Before reporting someone's number as wrong, prove your instrument measures the same thing. Read their stated definition and reproduce it *exactly* before varying anything.
- N of M rows reproducing is itself evidence about the instrument. If most rows match under your filter and a few do not, the most likely difference is in those rows' data, not in the author's arithmetic.
- Refuting your hypotheses about the other party is not progress if you never formed one about yourself. Keep a slot in the list: "my query is wrong."

---

## 24. A tool that rejects its arguments returns a payload, not an exception

**What happened.** A grounding tool call was made unconditional, seeded before the model's turn with a hardcoded parameter name. The tool actually expected a different parameter name. It received an empty value and answered with a normal, well-formed error object. Nothing threw, nothing logged at error level, and the run completed - reaching production as an output missing exactly the citations the seeding step existed to guarantee. Three tools on the same belt used three different parameter names; any one hardcoded name is right for at most one of them.

**The rules.**
- When you invoke a tool programmatically that was designed for a model to call, read the argument name from the tool's own schema, never from memory.
- A tool contract that returns errors as data needs assertions on the *data*. An exception-free run proves nothing about a tool whose failure mode is a well-formed payload.
- The unit test that would have caught it did not exist because the seeding was tested against a fake tool that accepted anything. A fake more permissive than the real thing tests the fake.

---

## 25. A ledger that only records success cannot answer "did it fail?"

**What happened.** Asked why a job's expected output never appeared, the obvious query returned zero rows for that job type - zero attempts, zero failures, empty queue. A handover document confidently recorded: "the job was never dispatched."

It had been dispatched. It had run. It had failed three times on an authentication error, and the production log said so in one line. The job wrote a receipt on success and on one specific refusal path - and on its generic failure path it wrote nothing. So the ledger's answer to "did it fail?" and its answer to "was it ever attempted?" were the same empty set.

**The rules.**
- Every terminal path writes a receipt - success, refusal, *and* failure. A ledger with a success-only writer is a marketing record, not an audit record, and its emptiness means nothing.
- Before reading absence as "never attempted", ask what the record looks like when the thing attempted and failed. If the two are indistinguishable, go to a source that separates them - here, one grep over the production log, thirty seconds, decisive.
- A receipt must carry the id you will search by. A foreign key nobody populates is a join that always returns zero.

---

## 26. Two halves of one credential, resolved down two different ladders

**What happened.** A background service posted a correct API key to the wrong host, and had done so since the feature shipped. Two related calls shared one key; only the address differed. One resolution chain fell back through a generic environment variable that still held a placeholder from years earlier, because the real value had always lived in a database instead. The address resolved to a *non-empty, wrong* value at that fallback rung and stopped there; the key fell through further, to the database, and was correct. Each chain was individually correct. The pair was nonsense - a valid key sent to the wrong endpoint, silently, for as long as the feature had existed.

**Why nothing showed it.** Every surface - the settings page, the run history - displayed a fully configured endpoint, because each half *was* configured. The only fact that revealed it was the two halves compared *to each other*, and nothing anywhere performed that comparison.

**The rules.**
- Resolve paired credentials as a pair. Either an explicit override supplies both halves and is used whole, or fall back whole. A half-configured override is not an override.
- Never default one config key through another subsystem's environment variable - it silently imports that variable's history, including a placeholder nobody meant to set.
- A free authentication probe beats a paid one. A cheap unauthenticated call with the real key catches exactly this failure before it touches a paying feature.
- Print the discriminator even when everything looks fine - whether two related endpoints actually agree is the one fact nobody had, and the one worth showing.

---

## 27. A mutation must be valid code, or the red proves only that you broke the parser

**What happened.** New guards were falsified per the usual discipline - plant the defect, watch the test go red, restore. Two mutations came back with `Errors`, not `Failures`. One had removed a closing brace so the file no longer parsed; every test in the class errored before asserting anything. The other cut a template block across its own closing directive and broke the template the same way. Both looked red. Both would have been recorded as "the guard works" by anyone reading only the colour.

**The rules.**
- Lint the mutant before running the suite. If it does not parse, the run is void - you have measured your edit, not your guard.
- Read the word, not the colour: `Errors` mean the test could not run; `Failures` mean an assertion was evaluated and came out false. Only the second is evidence.
- Prefer a mutation that cannot break syntax: flip an operator, negate a condition, return a constant. Never delete a fragment that spans a brace or a template directive.

---

## 28. `open(path, 'w')` empties the file before your write is allowed to fail

**What happened.** A script appending one section to a large document opened it in write-truncate mode and then wrote a string containing an unpaired UTF-16 surrogate escape. The runtime refused to encode it and raised an error - but the open call had already **truncated the file to zero bytes**. The document had been committed minutes earlier, so version control restored it byte-for-byte; the same script against uncommitted work would have destroyed it outright.

**The rules.**
- Write to a temp file, verify it, then move it into place atomically. Truncation then only ever happens to the temp file.
- Verify before the move: the temp file round-trips from disk, it is not implausibly smaller than the original, and known content near the start and end is still present.
- Never spell a multi-codepoint character as a raw surrogate escape in a language whose native string type is UTF-16-shaped underneath; paste the character.
- Assert emptiness after every bulk write, unconditionally - it is the one check that would have caught this in the same command that broke it.

---

## 29. A pre-existing red is indistinguishable from a planted one - so the baseline must be green FIRST

**What happened.** A batch of planted defects was run through a suite to prove the guards could fail. Four of seven came back with the same unrelated test in the failure list, and each time that was read as "the plant worked." It had nothing to do with any of the plants - that test had been red on the clean tree for an hour, since before any mutation began. Nobody had actually looked at a green run at the current test count; the last green run anyone had seen was at a smaller count, from before a new test was added.

**The rules.**
- Run the suite green immediately before the first plant, on the same commit, and record the count. Without a green baseline at that exact count, mutation results are not evidence - they are a list of names.
- Every red must be attributable by mechanism. Before writing "plant X was caught by test Y", say in one clause how X reaches Y.
- Diff the red sets, don't just count them. A test that appears under *every* plant is almost never a well-targeted assertion - it is a constant, and it is almost always pre-existing.
---

## 30. A test fixture that reads the wall clock while the code under test reads a hard-coded date is a time bomb, and it detonates on a day nobody touched the code

**What happened.** A suite came back with one failure in a subsystem nobody had touched that day. The cheap wrong move was tempting - call it environmental, call it pre-existing, move on. Running it alone: still red. Running it against a clean checkout of the base branch, in a separate worktree: red there too, identically. That settled attribution in one command.

The mechanism: a test fixture recorded a real-world timestamp, then travelled into a hard-coded date window. The code under test compares that timestamp against the window boundary. While the real calendar date sat inside the hard-coded window, the comparison passed; the day the calendar moved past it, the comparison flipped, and a test that touched no code went red on its own.

**The rules.**
- A test may fix time or read time, never both. If any date in a test is hard-coded, every fixture that stamps a timestamp must be created *inside* the travelled time.
- Setting a hard-coded clock after a fixture has already been written is too late; order the setup so the clock is set first.
- "Probably pre-existing" is a claim about another commit, and it takes one throwaway worktree to settle as a fact rather than an assumption.

---

## 31. Five findings in one night, and four of them were my own instrument

**What happened.** An automated review of an AI document generator produced a stream of alarming results - templates missing prices, contradictory clauses, references to attachments that did not exist. Almost all of them were the measuring apparatus, not the product: the harness was scoring raw fragments as if they were finished documents, one detector compared human-readable labels against machine keys from two different maps, another flagged a formatting choice that was already correct. One finding - "61 of 130 display rules never fire" - was one sentence from being reported as a production emergency. It would have been believed: it was specific, quantified, and alarming. It was also completely wrong, for the label/key reason above.

**What actually broke the tie, every time:** something that *disagreed*. A single case that came back clean is what a scan where everything fails cannot survive; "why is that one different?" is the question that unravels a broken instrument.

**The rules.**
- A finding is a lead until confirmed by a second, independent route. A score says which file to open; it does not say what is wrong with it.
- Make your instrument say *why*, not just *how much*. A number-only judge would have been believed four times that night; the reasoning beside the number is what exposed the harness each time.
- A result where everything fails is a result to distrust. Real defects cluster; a uniform catastrophe is usually the measurement.
- Patch the instrument twice, then stop patching it - a heuristic that keeps producing new false positives is the wrong approach, not a tuning problem.
---

## 32. A function returned a set, the caller got something else, and `.Contains` bound to a different method

**What happened.** A cleanup script's helper function ended with `return $set`, where the runtime **unrolls an enumerable on return**. The caller never received the set object. With more than one element it received a plain array; with exactly one, a bare string. For two revisions this was invisible, because the caller only ever *read* the value - array containment and set containment happened to agree on every test case, and with exactly one element, string containment (substring matching) happened to agree too, purely by coincidence of the data shape.

It surfaced only when a later change became the first code to *mutate* the returned value - the first `.Add()` call threw, because you cannot add to a plain array. Had the logic only ever read the value, the substring-matching binding would still be sitting there, waiting for the first element that happened to be a prefix of another.

**The rules.**
- Wrap a returned collection so it survives the language's own unrolling behaviour on output - most languages that do this offer an explicit escape hatch.
- A method call is not a contract. The same call can compile and run against several unrelated types with different meanings, chosen silently at runtime. When the type matters, assert it.
- Code that only reads a value cannot detect that the value is the wrong type. What finds it is always the first *write* - so when you inherit a structure you did not build, exercise it once on purpose before trusting what it is.
---

## 33. A stray non-printing character passed every check because none of them looked at encoding

**What happened.** A shipped JavaScript asset ended up with one non-printing byte inside a string literal, in a spot where a plain space had been intended, introduced by an ordinary hand edit rather than a script. The syntax checker was satisfied (the byte is legal inside a string literal), the test suite was green, and the character does not render, so a normal diff review shows nothing unusual. It was found only because a later, unrelated edit's own text-matching check could not locate a string it expected to be there, and following up on that mismatch eventually showed the file was no longer being treated as plain text.

**The rules.**
- Check the encoding of any text file before it ships, not only whether it parses: valid UTF-8, zero replacement characters, zero non-printing bytes outside the expected set. A syntax check does not look at any of this.
- Prefer a written escape sequence over typing a non-printing character directly - an escape shows up in a diff; the character itself does not.
- Treat an unexplained mismatch from a text-matching check as a lead worth following, not a nuisance to loosen the pattern past.

*(The same mistake happened again an hour later, while writing up the incident: the note describing the fix contained one more instance of the very character it was warning about, in the sentence recommending the escape sequence instead. It was caught only because a routine encoding check now runs after every document write - a reminder that a mechanical check finds what careful reading does not.)*
---

## 34. `set -e` at the top of a tool-invoked command does not stop the command

**What happened.** A chain of patch to lint to commit steps began with `set -e`. A guarded step in the middle refused and exited non-zero, and the chain carried on regardless: the next step ran against a file that was never created, a subsequent check crashed, and a commit still ran. Nothing wrong was actually committed only because a later `git add` happened to fail on the missing path - luck, not a mechanism.

Measured directly: the identical `set -e; <command that exits 2>; echo reached` stops correctly inside a shell script invoked with `bash -c`, but prints `reached` when run as a single command through certain tool-execution harnesses. `set -e` also never covers a pipeline whose *last* command succeeds - a failing step piped into a command that itself exits 0 continues even under `bash -c`.

**The rules.**
- Do not rely on `set -e` inside a harness-invoked command. Guard every step explicitly and check its exit code, or put the chain in a script file and invoke that file directly.
- After any multi-step chain that commits, read the actual repository status before believing the chain did what its last printed line claimed.
- A guard that refuses correctly but does not stop the chain behind it has not protected anything.

---

## How to use this file

Before you write a bulk edit, a guard, a measurement script, or a production command, find the matching entry and satisfy its rule. When your agents cause a new one, add it - with the date, what it actually broke, and the rule. An entry with no dated incident behind it does not belong here.