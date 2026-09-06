# The operating system around the guards

> The hooks in this repository are the enforcement layer. They are the smallest part of what makes agents useful. This file is the rest of it.

Most teams that put coding agents on real code get a 30% speedup and a mess. The model is not the variable. Everything around it is, and it has to be engineered deliberately — one layer at a time, each layer earning its place by fixing a failure that actually happened.

These are the six layers, in the order they pay off.

---

## 1. Context — what the agent knows at the moment it acts

An agent is not stupid; it is uninformed at exactly the wrong moment. Three things fix that:

**An indexed map, not a folder.** A file that says where things live and, more importantly, which of them are load-bearing. An agent that has to discover your architecture will discover a plausible wrong one.

**Rules that load by path.** Doctrine attached to the code it governs, so touching the billing directory loads the billing rules and nothing else. A single enormous instruction file is read once, skimmed forever, and obeyed selectively.

**Memory that survives the session.** One index, one line per fact, each pointing at a file that holds the story. Written as *hooks*, never as summaries — a summary decays into a confident false claim, while a pointer either resolves or visibly breaks.

The measure of this layer: the next session starts where the last one ended, not from zero.

---

## 2. Task specification — brief it the way you would brief a contractor

Most agent failures are briefing failures wearing a technical costume.

A task that can be finished well states three things: **the scope**, **what is explicitly out of scope**, and **the evidence required before it may be called done**. That third one does most of the work, because it converts "make it better" into a checkable claim.

A useful habit: the agent restates the scope boundary in one sentence before it writes anything — *"I will do X. I will not do Y."* Half of all scope creep dies there, and the half that survives is visible.

---

## 3. Orchestration — an orchestra, not a chat window

Serial work with one agent wastes the one advantage agents have, which is that they are cheap and parallel. But parallel agents on one repository will overwrite each other within the hour.

What makes it work:

- **A file-ownership partition.** Every parallel track owns a disjoint set of paths, declared before anyone starts. Two agents that cannot touch the same file cannot corrupt each other's work.
- **A manager that does not build.** One session dispatches, verifies the evidence that comes back, and merges. The moment the manager starts writing code it stops verifying, and the whole structure collapses into one confused agent.
- **A registry.** Each running session announces itself and the files it is touching. Cheap, and the only thing that makes an overlap visible before it becomes a conflict.
- **Model matched to the work.** Judgement, production code and adversarial review get the strong model. Breadth-first reading and internet research get the cheap one. Choosing by default rather than by task is how the budget disappears without the quality arriving.

---

## 4. Review — by something that did not build it

The same mind that produced a plan will produce the justification for it. This is not a failing of models; it is true of people and it is why code review exists.

So the work runs in three passes with a boundary between them: **design**, **build**, and an **adversarial pass whose only job is to prove the first two wrong**. The third pass gets fresh context and no attachment to the decisions.

Two rules keep it honest:
- The design pass may not close until it has found a real defect **in its own plan**. "I found no problems" is the gate refusing to close, not passing.
- Every "done" must name what its evidence does **not** cover. A green suite does not prove the feature is reachable; HTTP 200 does not prove the page renders.

---

## 5. Instruments — build the tool, do not ask the model to squint

When you need to know something, write the thing that measures it. Over one platform this produced: a layout measurer that reports overflow, the right edge of a text range, and the smallest rendered font; a drift detector that compares the deployed tree against git file by file; a guard exerciser that plants each defect and confirms the catch; a model-based judge that scores output against a rubric where a static check cannot.

The pattern: **an instrument you can re-run beats a judgement you have to trust.** And every instrument needs a positive control, because the most convincing wrong answer in software is a green result from a tool that is measuring nothing.

---

## 6. Compounding — the part that actually matters

Speed and quality normally trade against each other. In this system they rise together, and the mechanism is simple:

> **Every mistake becomes a rule. Every rule that matters becomes a hook.**

A failure that is only remembered will happen again in six weeks. A failure written into a dated catalogue is avoided by whoever reads the catalogue. A failure converted into a hook cannot happen again at all — and costs nobody any attention from then on.

That is why the failure list in [`failures/`](../failures/) is the most valuable file here and the hooks are second. The list is where the learning lives; the hooks are the part that no longer needs to be learned.

---

## What this looked like in practice

One person, seventy days, from a one-page brief to a live regulated e-signature platform — qualified signature through a licensed certificate authority, identity verification, a form builder, a public API — carrying two years of migrated data. Against the platform it replaced, by month four: 3.7× the contracts, 2.9× the revenue, 99.97% of 1,625,586 requests without a server error.

The agents wrote most of the code. This is the system that decided what was allowed to ship.

It is also portable. It came from a chatbot, went to an AI tutor, then to a regulated platform, and it survived each move intact — because none of it is about the domain, and none of it is about which model you use this month.
