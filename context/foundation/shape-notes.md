---
project: "Henia"
context_type: greenfield
created: 2026-08-17
updated: 2026-08-17
product_type: null
target_scale:
  users: null
  qps: null
  data_volume: null
timeline_budget:
  mvp_weeks: 9
  hard_deadline: 2026-10-22
  after_hours_only: null
checkpoint:
  current_phase: 4
  phases_completed: [1, 2, 3]
  frs_drafted: 0
  quality_check_status: not-run
  gray_areas_resolved:
    - topic: "context type"
      decision: "Greenfield. The devcontainer harness and 101 toolkit were first adopted as a tracked baseline (commit 977fbeb) so guardrail regressions show up in a diff, then shaping proceeds as greenfield."
    - topic: "Kubernetes: product requirement or stack choice"
      decision: "Product requirement, not a deferrable platform choice. The gap being targeted is specifically that cloud-native agentic autonomy does not exist yet, so deferring k8s to the tech-stack step would discard the definition of the product. The facilitator's proposed split was overridden by the user."
    - topic: "SDD maturity: prerequisite or part of the product"
      decision: "Prerequisite. Henia requires the adopting organization to arrive with mature spec-driven development; the market already has mature educational resources for it. Optional later addition if time allows: an interactive Katacoda-style simulator teaching the 101 toolset."
    - topic: "source of the agent's authority"
      decision: "For repository access, the agent is just another git identity with a narrower role — its permissions are git permissions, the same mechanism developers use. Execution isolation and CI/CD are delegated to native platform mechanisms rather than to git."
    - topic: "MVP-too-big — scope-cost disclosure"
      decision: "Exit B taken on 2026-08-17: the longer horizon is consciously accepted. Seven actions before first value and five integrations before the flow completes once, accepted deliberately so the conference PoC is a working system rather than a slice. The facilitator stops raising scope from this point."
    - topic: "role of the devcontainer"
      decision: "Scaffolding, not product lineage. It exists so primary coding before dogfooding can run in YOLO mode safely; it is NOT to be ported to Kubernetes beyond the general idea of isolation. A facilitator suggestion to reuse it for the inner loop was withdrawn as wrong."
    - topic: "technical debt during the sprint"
      decision: "Corners cut are documented as separate slices rather than as regret, so they enter the backlog already shaped and can be worked by the autonomous flow itself. MVP accepts stitches; post-MVP varnishes."
    - topic: "project name"
      decision: "Renamed from str8t to Henia (Greek ἡνία, 'the reins') on 2026-08-17, chosen for the CNCF Greek-naming convention. Vetted clean on npm, PyPI, crates.io, henia.io/.dev/.sh/.net, no commercial use in technology, and no phonetic collision with the CNCF or CD Foundation landscape. GitHub org 'henia' is held by a dormant zero-repo user; suffixed handles are free and the project is Gitea-first. Trademark clearance still outstanding. The facilitator raised that Henia reads as a Polish female diminutive to a Polish-speaking audience; the user reaffirmed the choice and the objection is closed."
---

# Shape notes — Henia

## Vision & Problem Statement

Agentic SDLC is new; agentic autonomy is newer still. This is a proof of
concept intended to move teams forward and free them from day-to-day chores.

The pain is fragmentation across three planes that every organization now has
and which do not meet:

- workloads are migrating to cloud native;
- CI/CD is still detached from that migration;
- agentic workflows are IDE-based — vibe coding — detached from both.

Nobody has merged the three into a curated cloud-native workflow backed by
OWASP guardrails. The two named guardrail sources are the **OWASP Top 10
CI/CD Security Risks** and the **OWASP Top 10 for Agentic Applications**.

The governing analogy, in the user's words: **GitOps centered configuration
management on git; Henia's ambition is to do the same for agentic SDLC —
center it around git.**

Kubernetes is a strong product requirement rather than a platform decision to
be made later: the market is currently lacking cloud-native agentic autonomy,
and that absence is the opening.

**What it costs today.** People are using AI in a non-effective way, and
companies are burning tokens — real money. The cause named is not incompetence
but the absence of an inheritable market best practice: every team reinvents
the wheel and pays for the reinvention in spend.

**Ambition and positioning.** The market has an expanding set of proprietary
agent orchestrators; Henia is intended to be a solid open-source framework
people can build on. Once matured, and if the idea proves successful, the
ambition is to bring it under the CNCF incubator.

## User & Persona

The person is, depending on the size of the organization, a **Software /
Solution Architect** or a **DevOps team**.

**The moment** is a readiness threshold rather than a pain event: a company can
adopt Henia when its spec-driven development is mature — when someone has
already carefully designed the project and it is well specified. This project
is its own worked example of that precondition.

Henia **requires** that maturity and does not supply it; the market already has
mature educational resources for SDD.

> Facilitator note, unresolved and carried forward: burned tokens are felt most
> directly by whoever owns the budget, while the named persona is an architect
> or DevOps team. Phase 3 needs the architect's own version of the cost, not
> the budget owner's.

## User Stories

**Main path — the smallest complete flow that proves Henia works.** Derived by
the facilitator from the user's three capability clusters and confirmed by the
user's acceptance of its size (see the timeline acceptance below):

1. The framework picks up work from git autonomously — a feature, or a
   regression where the pipeline failed.
2. An agent starts, sandboxed inside Kubernetes, persistent, potentially
   alongside other agents running in parallel.
3. The agent works and tests its changes inside that sandbox — the **inner
   loop**.
4. It opens a PR.
5. PR-based checks run through CI/CD — linters, AI review, shift-left
   security — the **outer loop**.
6. If the pipeline fails, the framework picks that up too and fixes it,
   returning to step 1.
7. The merged change reconciles into the cluster.

**MVP boundary.** One implementation of each pluggable architecture — Gitea for
git, pi.dev for the agentic harness, knest for inner loops, Tekton and Argo for
outer loops — while remaining ready to expand: new providers can be written for
each seam.

> **Timeline acceptance — 2026-08-17.** Scope-cost disclosure fired on this
> flow: seven distinct actions before first value (threshold ~6) and five
> integrations required before the flow completes even once. The user
> consciously accepted the longer horizon (exit B) so the conference PoC
> demonstrates a working system rather than a narrowed slice. Hard deadline
> 2026-10-22, 66 days / 9.4 weeks from acceptance — to the stage, not to a
> code freeze. This is a gate, not a warning: scope is not raised again.

## Access Control

Authority is delegated to native mechanisms rather than implemented by Henia.
Three axes, three owners:

**Repositories — git permissions decide.** What a developer can do is decided
by their git permissions. The agent is **just another git identity** with a
narrower role, governed by the same mechanism rather than by a separate one.
If git permissions alone prove too coarse, a **CODEOWNERS** scheme may be
adopted; this is a fallback, not the primary design.

**Sandboxes — native Kubernetes mechanisms.** Execution isolation is delegated
to the platform's own sandboxing facilities rather than built by Henia.
Candidate projects are recorded in the tech-stack forward block.

**CI/CD — plug into existing pipeline engines** rather than shipping a runner.
Named engines are recorded in the tech-stack forward block.

**A separate GUI, if one ships, uses pluggable authentication** rather than a
built-in identity system.

> Facilitator note, confirmed pattern awaiting the user's explicit assent:
> across all three axes the position is the same — Henia wires existing
> mechanisms together instead of implementing its own authorization, sandbox,
> or runner. Likely to resurface in Phase 5.

## Forward: tech-stack

- **Kubernetes is locked as a product requirement**, per the user (2026-08-17),
  not an open choice for `/101-tech-stack-selector`. Recorded here so the
  stack step treats it as given. Note: `/101-prd`'s technical-leak lint will
  flag the technology name in the requirements sections — that is expected,
  and the decision to hold the line there is the user's to make consciously at
  generation time.
- **Sandboxing candidates**, user-named and explicitly open ("or similar"):
  `kubernetes-sigs/agent-sandbox`, `smartxworks/knest`.
- **CI/CD integration targets**, user-named: **Argo** and **Tekton**. Whether
  these are locked the way Kubernetes is, or still candidates, is an open
  question put to the user on 2026-08-17.
- Upstream reference checkouts surveyed before shaping, both MIT:
  `open-mercato/skills` (tracker-provider seam — abstract operations plus a
  per-provider Markdown descriptor) and `open-mercato/cezar` (agent-runner
  seam including an existing pi backend; `ForgeDriver` seam; issue-label
  polling automations). Kept in `3rd_party/`, gitignored, nothing adopted.

## Forward: technical-roadmap

- Optional, explicitly conditional on time: an **interactive simulator**
  (Katacoda-style) teaching the 101 toolset. Stated as "if time allows" — not
  scope, and not a commitment.
- Phase split stated by the user before shaping: the 101 toolkit is the
  **bootstrap** that builds the harness with a human at every gate; once
  deployed, the steady state is issue-driven — a Gitea issue tagged
  `#feature` picked up by the automation framework, modelled on or shifted to
  the `om-*` skills and cezar's workflows, which assume the SDD work is
  finished and the SDLC is purely git-based.
- Provider-agnostic is a day-one requirement, with **Gitea first as the PoC**
  implementation — the reference implementation, not a special case. The
  project's own remote is already Gitea
  (`git.tobiko.kondi.net/kondi/str8t.git`).
- Forking cezar remains open, primarily to avoid hand-building a GUI and to
  reuse its issue-label polling loop; inspiration-only is the alternative.
- **Debt-as-slices practice.** Corners cut while sprinting to the conference
  are written up as separate slices at the moment they are cut, not
  reconstructed afterwards, so post-MVP work arrives already shaped and can be
  worked by the autonomous flow itself. Watch-item raised by the facilitator
  and not yet resolved: the debt slices are only autonomously workable if the
  autonomy loop works, and the corners cut are most likely to be inside that
  same loop — so where the stitching lands matters more than how much of it
  there is.
- The devcontainer is explicitly **not** a prototype of the Kubernetes sandbox
  and is not to be ported; only the general idea of isolation carries over.
