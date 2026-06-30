# MANIFESTO — From documents to shipped code

### Why a knowledge base is the foundation of agent-built software

---

## The thesis, in one line

**An agent fleet is only as good as the source of truth it shares.** Give a fleet of capable models a converted, mirrored, grep-able, provenance-tagged corpus — and turn its requirements into testable acceptance criteria — and you no longer have a clever demo. You have a repeatable way to build software.

Skip that, and you have a very expensive random number generator.

---

## The failure mode nobody warns you about

Point a state-of-the-art model at a folder of requirement documents and tell it to "build the app." Watch what happens.

**It thrashes its context.** The requirements live in `.docx`, `.pptx`, `.pdf`, `.xlsx`, and `.vsdx` files — some bilingual, some scanned. So the model re-opens, re-parses, and re-summarizes the same documents on every turn, burning its window on extraction instead of engineering. Half its attention is spent remembering what it already read.

**It hallucinates requirements.** When a document is hard to parse, the model fills the gap with the *statistically plausible* requirement — the one most apps have — not the one *this* document actually states. In a to-do app, nobody dies. In a custody system, a benefits engine, a clinical workflow, "plausible" is a defect with a person's name on it. And because there is no single addressable source, no one can later ask "which document said that?" and get an answer.

**The agents step on each other.** The moment you parallelize, agents editing a shared working tree swap `HEAD` mid-edit, clobber each other's appends, and leak commits onto the wrong branch. The speedup you bought with parallelism, you pay back with a day of untangling git.

These are not prompt problems. You cannot prompt your way out of a missing source of truth. They are **architecture** problems, and they have an architectural fix.

---

## What a knowledge base actually is

Not a vector store. Not "we embedded the PDFs." A knowledge base, in this framework, is a **converted markdown corpus engineered to be navigated by a machine that thinks in text**:

- **Converted** — every source format is rendered to markdown *once*, deterministically, by a real pipeline. Agents read the output, never the originals.
- **Mirrored** — the KB folder tree matches the source tree, so a human who knew the documents can still navigate, and an agent's path intuition transfers.
- **Grep-able** — and here is the load-bearing idea: **native requirement IDs are preserved verbatim as first-class headings and grep targets.** `ORG-CM-ACA-BR001`. `DC_007`. `FCS-CMD-PRC-1.1`. The requirement ID *is* the address. `rg -n "ORG-CM-ACA-BR001"` lands an agent on the exact governing text, every time, with zero ambiguity.
- **Provenance-tagged** — every converted document opens with a `> Source:` line back to its original. Every requirement an agent implements carries a `file:line` citation forward into the code and the commit. "Which doc said that?" stops being a question and becomes a `git blame`.
- **Mapped** — a master `INDEX.md` routes any reader to any area in one hop; per-area `_manifest.md` files record the conversion method and the quality caveats, so degraded-OCR content is treated as *verify-against-canonical*, not gospel.
- **Honest about staleness** — explicit Excluded lists and dedup rules mean an agent physically cannot cite a superseded `-OLD-` document and pass it off as current.

A KB built this way is not documentation *about* the system. It is the **coordinate system** the build runs on.

---

## Why we build it first, every time

Because the KB is what makes everything downstream possible:

**It makes briefs inline-by-default.** When the requirement is addressable by ID, the orchestrator can *inline the exact governing text* into a sub-agent's brief instead of telling it to "go read the docs." The agent starts working at tool-call one. No exploratory reading, no context thrash. The single most expensive habit in naive agent work — re-reading to re-orient — simply does not occur.

**It kills "which doc said that?"** Provenance is structural, not a discipline you hope people maintain. A reviewer reading the diff can follow the `file:line` citation straight to the source. An auditor can trace a line of code to the clause that demanded it. The chain from requirement to implementation is never broken because it was never optional.

**It turns requirements into verifiable units.** Once every requirement has a stable, addressable ID, you copy each one *verbatim* into an acceptance-criteria ledger, tag it by surface, and give it a delivery round. Now the requirement is no longer prose — it is a **unit of done that must map to a verification:** a passing automated test when it touches the protected core (state machine, RBAC, audit, snapshot, temporal/SLA, scoring), otherwise live-app verification (testing is opt-in — see PLAYBOOK §7). The KB is what lets the contract be exhaustive instead of aspirational. You cannot verify what you cannot address; the KB makes every requirement addressable.

The KB is the single source of truth. Everything else — the contract, the tickets, the seams, the gates — is downstream of it. Build it first or build on sand.

---

## How we build it

No magic. A pipeline plus conventions, both shipped in this kit (`toolkit/ingestion/`, `skills/corpus-ingestion/`):

**markitdown does the bulk.** Microsoft's MIT-licensed converter turns `.docx/.pptx/.pdf/.html` into markdown. Installed isolated and pinned — version 0.1.6 in a `pipx` venv on **Python 3.13** (3.14 has wheel gaps). One quirk we handle: it inlines embedded images as base64 `data:` URIs that bloat the file and poison grep, so we strip them in post-process.

**Custom extractors fill the gaps.** markitdown does not read `.vsdx` Visio diagrams and does not split `.xlsx` per-sheet cleanly — so the kit ships its own `vsdx_to_md.py` and `xlsx_to_md.py`. Process flows are **dual-captured**: the ordered step text you build logic from, *and* a rendered image that preserves the arrow topology and branch conditions the text loses.

**Conventions do the rest** — the mirrored tree, the verbatim IDs, the `> Source:` lines, the `INDEX.md` and `_manifest.md`, the Excluded and dedup rules. These are cheap to apply and they are the entire difference between "a folder of markdown" and "a source of truth."

Deterministic in, deterministic out. The KB is **regenerable**: to add a document you convert it into the mirroring folder and add an index row — you never hand-type a requirement, because a hand-typed requirement is a hallucination waiting to be cited.

---

## The bigger claim

Here is what the knowledge base unlocks, and why this is a framework and not a trick.

Once requirements are addressable and testable, **one operator can direct a fleet.** The operator sets the mission and owns the gates. The orchestrator composes self-contained briefs from the KB and runs the work in waves. Sub-agents work in isolated worktrees, each owning its own files, each appending one line to a handful of conflict-free seams, each committing its own branch and never pushing. The shared ticket queue is the *only* shared state, and it is append-only. The integrator merges under executable gates and is the single actor allowed to bump the contract version. A heavy QA pass runs the real app in real browsers — and is then *adversarially re-verified* so the report can be trusted.

None of that is improvisation. Every step is anchored to two artifacts: **the knowledge base** (what is true) and **the development contract** (what done means). Change the domain — swap the custody system for a billing platform — and the artifacts change while the machine does not. That is the definition of a framework.

The industry keeps asking whether AI can write software. Wrong question. AI can already write software. The real question is whether you can **direct a fleet of it without drowning in its output** — without hallucinated requirements, untraceable decisions, and branches that fight each other.

The answer is yes, and it starts the same way every serious engineering effort has always started: **by agreeing, precisely and in writing, on what we are building.** We just made that agreement machine-navigable, and handed it to the machines.

> Documents are where requirements go to be forgotten. A knowledge base is where they become code.

Build the knowledge base first. Everything else is downstream.
