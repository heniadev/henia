---
project: "Henia"
version: 1
status: draft
created: 2026-08-18
context_type: greenfield
product_type: automation
target_scale:
  users: medium
  qps: medium
  data_volume: small
timeline_budget:
  mvp_weeks: 9
  hard_deadline: 2026-10-22
  after_hours_only: false
---

# Product Requirements — Henia

> **Recorded contract deviation.** This document knowingly names specific
> technologies in eight places, which the schema's technical-leak lint would
> normally reject. The names were kept by explicit decision on 2026-08-18:
> Henia is by design a cloud-native application on Kubernetes, is centred on
> git, and takes Gitea as its first supported git provider — these are product
> identity rather than deferrable stack choices. The affected phrases are listed
> in `## Open Questions`. Socratic block-quotes are exempt from the lint by the
> same decision: they record why a requirement was challenged, including which
> technology was being argued about, and the contract requires them verbatim.

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

**What it costs the architect personally** (resolved 2026-08-18, closing the
note carried since phase 3): **the SDLC lives in their head.** Nothing enforces
how work is supposed to flow, so every team drifts differently and the architect
re-establishes the same process by hand, repeatedly. Burned tokens are what the
budget owner feels; this is what the person named as the persona feels — and it
is the cost the transition-learning rule answers directly, which is why the
problem statement and the business rule describe the same person.

## Success Criteria

### Primary

**Henia builds Henia unattended** — the full eight-step loop runs on the
project's own repository with no person acting at any step except review. The
product is its own proof, and it matches the debt-as-slices practice: post-MVP
work already arrives as issues the framework picks up itself.

### Secondary

Facilitator-proposed from decisions already taken; correct freely.

- Each of the eight guardrails can be shown stopping something — a self-merge
  refused, a budget exhausted, an agent stopped, a pipeline-definition diff
  gated.
- Cost is visible per work item and per agent from real provider reporting
  rather than estimation (FR-320).
- The cycle closes: an observation becomes a finding, a person promotes it, and
  the resulting work reaches the cluster (FR-112 → FR-116 → FR-110).

### Guardrails

Things whose breakage is a regression even when the primary criterion is met.

- No agent approves or merges its own work (FR-210).
- No change reaches the cluster without passing review (FR-210, FR-110).
- No agent-authored change to working knowledge or the transition model bypasses
  review (FR-340, FR-415).
- Work on a single item never exceeds its declared attempt and spend bounds
  (FR-230).
- No credential is obtainable from inside a sandbox after the agent starts
  (FR-370).

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

**MVP boundary.** One implementation of each pluggable architecture — Gitea as
the first supported git provider, pi.dev for the agentic harness, knest for
inner loops — while remaining ready to expand: new providers can be written for
each seam.

> **Outer-loop integration dropped — 2026-08-18.** Tekton and Argo were locked
> as integration targets at the quality check and un-locked the same day. The
> user's reasoning: one is git-driven and the other fully declarative, so both
> are steered by delivering configuration to git — which Henia does anyway —
> and read-only sight of the running platform is enough to see the result.
> Configuration stays secured and versioned in git. Consequences: one fewer
> integration in the MVP, the "two engines" limitation retired, and the
> git-centred rule becomes literally true rather than nearly true.

> **Timeline acceptance — 2026-08-17.** Scope-cost disclosure fired on this
> flow: seven distinct actions before first value (threshold ~6) and five
> integrations required before the flow completes even once. The user
> consciously accepted the longer horizon (exit B) so the conference PoC
> demonstrates a working system rather than a narrowed slice. Hard deadline
> 2026-10-22, 66 days / 9.4 weeks from acceptance — to the stage, not to a
> code freeze. This is a gate, not a warning: scope is not raised again.

### US-01: A unit of work travels from git to the cluster with no human in the loop

- **Given** a repository whose specifications are already complete, and a unit
  of work waiting in it — either a requested feature or a pipeline run that
  failed —
- **When** the framework picks that unit of work up on its own,
- **Then** an agent runs sandboxed inside Kubernetes, changes and tests the code
  inside that sandbox, opens a PR, the PR passes the outer-loop checks, and the
  merged change reconciles into the cluster — without a human acting at any of
  those steps.

#### Acceptance Criteria

- No step in the sequence is initiated by a human.
- A failed outer-loop check re-enters intake as a new unit of work instead of
  ending the run.
- Nothing an agent produces leaves its sandbox before the PR is opened.

### US-02: An observation becomes work

Facilitator-derived from FR-112 to FR-117 and confirmed in scope 2026-08-18.

- **Given** a change that has reconciled into the cluster and is running,
- **When** the framework observes something in the running system that clears
  the significance threshold,
- **Then** it files a finding, and that finding waits for a person to promote it
  before any agent acts on it — unless it identifies a severe incident, in which
  case investigation starts immediately and what it produces is reviewed
  afterwards.

#### Acceptance Criteria

- Routine noise does not produce a finding.
- No ordinary finding becomes agent work without a person promoting it.
- A severe incident starts investigation without waiting, and nothing it
  produces merges without review.

### US-03: A reviewer's comments become changed code

Facilitator-derived from FR-420.

- **Given** an open pull request an agent has authored,
- **When** a person leaves review comments on it,
- **Then** the agent takes those comments up as work and the pull request
  changes, rather than the agent replying.

#### Acceptance Criteria

- The reviewer sees changed code, not an argument.
- The agent cannot approve or merge the result (FR-210).
- Every change made in response is attributable to the comment that caused it.

### US-04: Work is dropped without being forgotten

Facilitator-derived from FR-430.

- **Given** an open pull request an agent has authored,
- **When** a person decides the work should not proceed,
- **Then** the pull request is dropped and what led to that decision is kept
  rather than discarded.

#### Acceptance Criteria

- Dropping is a terminal state distinct from exhaustion (FR-230) and from being
  stopped (FR-240).
- The reasoning survives the pull request being closed.

### US-05: An oversized slice divides

Facilitator-derived from FR-440.

- **Given** a unit of work found to be too large to complete as one change,
- **When** it is divided,
- **Then** descendant units are created, each carrying its own budget, and the
  relationship between the parent and its descendants survives the queue and
  its triage.

#### Acceptance Criteria

- A descendant is traceable to its parent after both have moved through the
  queue.
- One lineage cannot divide more times than the cap allows.

## Functional Requirements

Derived by the facilitator from the phase 1–3 record at the user's instruction
(2026-08-17) — every capability below traces to something already stated in the
Vision, User Stories or Access Control sections; priorities are the
facilitator's proposal and are the user's to correct. Every requirement carries
exactly one Socratic challenge, with the single exception noted at FR-085.

### Work intake

- FR-010: The framework can pick up a unit of work from git autonomously, with
  no human initiating the run. Priority: must-have
  > Socratic: Counter-arguments considered — that pickup needs an explicit
  > spec-readiness gate, that an autonomous start is unshowable on stage, and
  > that agents outpace human review capacity. Resolution: none accepted.
  > Autonomous pickup is what makes Henia a framework rather than a CLI; the
  > objections are about the authorization of work items (FR-180), not about
  > autonomy. Stands as written.
- FR-020: The framework can treat a failed pipeline run as a unit of work in the
  same way it treats a requested feature. Priority: must-have
  > Socratic: Counter-argument accepted — pipelines fail from flaky tests,
  > expired credentials and broken runners at least as often as from real
  > defects, and an agent handed "the pipeline failed" will change code until
  > the symptom disappears, producing a green pipeline and a worse repository.
  > Resolution: accepted and answered by FR-025 — classification happens before
  > intake, so only a failure caused by the change becomes agent work.
- FR-025: The framework can distinguish a pipeline failure caused by the change
  from one caused by the environment; only the former becomes agent work, and
  the latter escalates to a human. Priority: must-have
  > Socratic: Counter-arguments considered — that flakiness is only visible
  > across runs so classification needs failure history it will not have on day
  > one, that failure triage is a product in its own right and will be built
  > badly in nine weeks, and that neither tuning direction is safe (escalate
  > everything and autonomy dies; permit too much and FR-020's problem
  > returns). Resolution: none accepted. Classification is the accepted price
  > of keeping FR-020. Stands as written.

### Agent execution — the inner loop

- FR-030: The framework can start an agent inside a Kubernetes-native sandbox.
  Priority: must-have
  > Socratic: Counter-arguments considered — that requiring a cluster kills
  > contributor adoption, that the young sandboxing candidates are a demo risk,
  > and that per-item sandbox startup cost is what the audience sees.
  > Resolution: none accepted. Cloud-native was locked as a product requirement
  > in phase 1 because the market gap is specifically cloud-native agentic
  > autonomy; weakening this dissolves the product. Stands as written.
- FR-040: An agent's workspace can persist for the life of the unit of work
  rather than being rebuilt per step. Priority: must-have
  > Socratic: Counter-arguments considered — that persistence is the ASI06
  > surface FR-170 commits to closing, that stuck items hold resources
  > indefinitely under FR-050's parallelism, and that accumulated state hides
  > non-reproducibility. Resolution: none accepted. Rebuilding per step makes
  > the inner loop unusably slow and forces the agent to re-derive context it
  > already holds, which is itself token burn. Stands as written; the ASI06
  > tension is handled by FR-170 treating work-item text as data rather than by
  > discarding the workspace.
- FR-050: The framework can run several agents at the same time, each in its own
  sandbox. Priority: must-have
  > Socratic: Counter-arguments considered — that concurrent agents produce
  > colliding changes with nothing arbitrating merge order, that parallelism
  > multiplies cost before one agent is proven end to end, and that one
  > complete run is a stronger conference story than three partial ones.
  > Resolution: none accepted. Parallel persistent agents are what distinguish
  > a cloud-native framework from a laptop tool, and FR-240 already governs
  > their lifecycle. This also settles the earlier hedge — parallelism is
  > must-have, not a stretch goal.
- FR-060: An agent can change and test code inside its sandbox before any of it
  leaves the sandbox, testing against substitutes rather than real services;
  anything that requires real credentials is verified in the outer loop.
  Priority: must-have
  > Socratic: Counter-arguments considered — that it fights FR-200's ban on
  > inner-loop secrets since real tests need the services those credentials
  > open, that sandbox environment fidelity costs more than the orchestrator
  > itself, and that it duplicates the outer-loop checks and will drift from
  > them. Resolution: none accepted. An agent that cannot test before opening a
  > PR pushes every failure into the slower, more expensive, human-visible
  > outer loop. **The FR-200 tension was resolved 2026-08-18 in FR-200's
  > favour**: the inner loop tests against local doubles and fixtures, and
  > anything needing real credentials is verified in the outer loop where
  > FR-080's pipeline holds them. FR-060 narrows to "tests what can be tested in
  > isolation", which also keeps the inner loop fast — load-bearing when agents
  > run continuously.

### Review and validation — the outer loop

- FR-070: An agent can open a pull request in the git provider. Priority:
  must-have
  > Socratic: Counter-arguments considered — that terminating every unit of work
  > at a review queue contradicts the autonomy claim, that building around the
  > PR hard-codes a forge concept against the provider-agnostic requirement, and
  > that agents flood the queue faster than humans drain it. Resolution: none
  > accepted. The PR is deliberately the human trust boundary — FR-210, FR-250
  > and the whole ASI09 answer attach to it, so removing it removes the
  > guardrails.
- FR-080: The framework delivers pipeline configuration to git; the pipeline
  engine reconciles from there on its own. The framework neither triggers checks
  nor runs them. Priority: must-have
- FR-085: The framework can read the state of the running platform without being
  able to change it, so it can see what has actually reconciled.
  Priority: must-have
  > Socratic: Not yet challenged — added during PRD generation on 2026-08-18,
  > after the Socratic round had closed. The one-challenge-per-requirement
  > invariant is broken here knowingly; run a challenge on it before planning.
  > Socratic: Counter-arguments considered — that FR-220's no-secrets property
  > is unenforceable in someone else's engine, that naming two engines doubles
  > integration cost before either is proven, and that Henia inherits whatever
  > configuration the adopter already has. Resolution: none accepted. Shipping
  > a runner would put Henia in competition with Argo and Tekton instead of on
  > top of them, contradicting the delegate-to-native-mechanisms position taken
  > throughout Access Control. Stands as written.
  > **Superseded 2026-08-18.** The user dropped both named engines as
  > integrations: one is git-driven and the other is fully declarative, so both
  > can be steered by delivering configuration to git, which Henia already does.
  > The framework therefore does not integrate with a pipeline engine at all —
  > it commits configuration and the engine reconciles itself, with FR-085
  > providing read-only sight of the result. This retires the
  > guardrails-unenforceable objection above (there is no borrowed engine to
  > enforce anything in), removes an integration from the MVP, and closes the
  > "two engines at MVP" limitation accepted at the quality check. It also makes
  > the git-centred business rule literally rather than nearly true.
- FR-090: PR-based checks can include linting, AI review, and shift-left
  security scanning. Priority: must-have
  > Socratic: Counter-arguments considered — that AI review of AI-written code
  > is a closed loop where correlated blind spots pass as independent review,
  > that shipping named check types contradicts FR-120's seam claim, and that a
  > scanner wired to an autonomous fixer produces security changes nobody has
  > understood. Resolution: none accepted. Shift-left security in the outer
  > loop is half of what "backed by OWASP guardrails" means to an audience.
  > Stands as written.
- FR-100: The framework can detect a failed check and re-enter intake with that
  failure as the next unit of work. Priority: must-have
  > Socratic: Counter-argument accepted — an agent repairing its own failing
  > check optimizes for the check passing, and it has write access to the code
  > the check reads; deleting the assertion is a valid solution to "the test
  > fails". Resolution: accepted and answered by FR-105 — the agent must state
  > the cause before the fix, so "I deleted the assertion" has to be declared
  > and is compared against the diff at review.
- FR-105: A pull request that repairs a failed check carries the agent's
  statement of what caused the failure, and review compares that statement
  against the actual diff. Priority: must-have *(extends FR-250; the ASI09
  answer applied to self-repair)*
  > Socratic: Counter-arguments considered — that it covers only repair PRs
  > while a first-attempt PR quietly weakening a test is the more common case,
  > that the explanation is written by the same agent whose work is in question
  > so a plausible alibi costs it nothing, and that a PR-template field cannot
  > manufacture the review attention it depends on. Resolution: none accepted.
  > Forcing a declared cause makes "I deleted the assertion" something the agent
  > must say out loud, and a stated cause can be checked against a diff
  > mechanically as well as by eye. Stands as written.

### Delivery and observation

- FR-110: A merged change can reconcile into the cluster. Priority: must-have
  > Socratic: No counter-argument accepted. Instead the user extended the flow
  > (2026-08-18): reconciliation is not the end of the cycle — observation is.
  > See FR-112 and FR-114.
- FR-112: The framework can observe the running system after a change
  reconciles and file what it observes as a finding. Its access to the observed
  system is read-only. Priority: must-have
  > Socratic: Counter-arguments accepted — that observation opens a second door
  > into intake which no human wrote and no authorization covers (ASI01), and
  > that observing production widens the framework's own blast radius against
  > FR-200. Resolution: both closed by the user, 2026-08-18 — telemetry is
  > treated as data (FR-113) and the framework's production access is read-only
  > (stated in the requirement itself).
- FR-113: Telemetry the framework reads is treated as data and never as
  instructions. Priority: must-have *(ASI01, the FR-170 rule applied to the
  observation intake path)*
  > Socratic: Counter-arguments considered — that hostile strings ride inside
  > legitimate telemetry (payloads in error messages, user input in stack
  > traces) so the boundary is at the wrong granularity, that "treated as data"
  > is not externally observable and so cannot be demonstrated or tested, and
  > that it should be one general rule over every intake path rather than one
  > per path. Resolution: none accepted. Stands as written.
- FR-114: Observations are gated so that obvious noise does not become a
  finding; only what clears a significance threshold is filed. Priority:
  must-have
  > Socratic: Counter-arguments considered — that this is FR-025's
  > classification problem again in a second domain, giving two thresholds to
  > tune in nine weeks; that a gate tuned for cleanliness also suppresses the
  > quiet first sign of a real incident; and that "obvious noise" is not
  > portable between systems, so a shipped default is invisibly wrong for every
  > adopter. Resolution: none accepted. The gate was named by the user when the
  > step was added — an ungated feed would flood intake and discredit the
  > observe loop immediately. Stands as written.
- FR-116: A filed finding becomes agent work only when a human promotes it.
  Priority: must-have
  > Socratic: Counter-argument accepted in part — the asymmetry against FR-020
  > (a failed pipeline enters intake unaided, a production finding does not)
  > needs a reason, and there are events where waiting for a human is the wrong
  > answer. Resolution: the human gate is kept as the default and FR-117 carves
  > out the severe case.
- FR-117: A finding identifying a severe incident — an outage or a near-outage —
  starts an investigation immediately, without waiting for a human to promote
  it; what the investigation produces is subject to post-mortem review.
  Priority: must-have
  > Socratic: Counter-arguments considered — that an outage is the worst moment
  > to add an autonomous actor beside humans already firefighting, that severity
  > classification is a third threshold to tune after FR-025 and FR-114 and the
  > one where error hurts most, and that the requirement does not say where
  > investigation stops and fixing begins. Resolution: none accepted. An outage
  > is precisely when a human is least available to promote a finding, and
  > post-mortem scrutiny is the accountability. Stands as written.

> **Flow extension — 2026-08-18, user's words.** "Once code is pushed to prod we
> should close SDLC cycle with *observe*." The seven-step flow recorded in
> phase 3 gains an eighth step: after reconciliation, Henia watches the running
> system and feeds findings back into intake, closing the cycle rather than
> ending it at deployment. The user framed the observability integration as
> "another PR" — whether that means inside the conference MVP or as a following
> slice is an open question put to them on 2026-08-18. Observability tooling
> named by the user is recorded in the tech-stack forward block.
>
> **Resolved 2026-08-18:** the observe step is in the conference MVP, but the
> cycle closes through a person — Henia files findings, a human promotes a
> finding to agent work (FR-116). Rationale: the closed-cycle story is on stage
> at a fraction of the risk, and FR-114's noise gate gets a human backstop while
> its threshold is still untuned.

### Extensibility

- FR-120: Each integration point — git provider, agentic harness, inner-loop
  runtime, outer-loop pipeline engine — can be replaced by an alternative
  implementation without changing the framework. A provider implementation is
  loaded only if the project's declaration names it; providers are never
  discovered at runtime. Priority: must-have
  > Socratic: Counter-arguments considered — that runtime-loaded providers are
  > ASI04 applied to Henia's own extensibility and no guardrail reaches them,
  > that one implementation per seam means abstraction cost paid before any
  > seam is exercised, and that four seams is four integration projects inside
  > nine weeks. Resolution: none accepted. Provider-agnostic was a day-one
  > requirement from before shaping, with Gitea as the reference implementation
  > rather than a special case. Stands as written. **The ASI04 exposure of the
  > seams was closed 2026-08-18** without a ninth guardrail: a provider loads
  > only when the project's declaration names it, so the loading path is
  > reviewable configuration rather than runtime discovery, and adding a
  > provider becomes a change someone approves.

### Identity and authority

- FR-130: An agent acts under its own git identity, which cannot force-push,
  delete branches, change the rules that protect a branch, or manage secrets.
  Priority: must-have
  > Socratic: Counter-argument accepted — an agent that must push branches, open
  > PRs, read check results and re-push fixes ends up holding most of a
  > developer's permissions anyway, so a general claim of being "narrower"
  > advertises a control that is not really there. Resolution: the vague
  > narrowing was replaced with named forbidden actions, which are concrete and
  > verifiable. Residual exposure acknowledged: the agent still holds write
  > wherever it holds it, and lateral reach is bounded only by FR-140 and
  > FR-150.
- FR-140: What an agent may do to a repository is decided by repository
  permissions — the same mechanism that governs developers. Priority: must-have
  > Socratic: Counter-arguments considered — that a permission designed for
  > humans who tire and hesitate is a different risk in the hands of an actor
  > that exercises it thousands of times without judgement, that forge
  > permission models are too coarse to express anything but write, and that
  > this duplicates FR-130. Resolution: none accepted. Settled in phase 2 as the
  > source of the agent's authority — git permissions, not a parallel system
  > Henia invents. Stands as written.
- FR-150: A CODEOWNERS-based restriction can be adopted where repository roles
  prove too coarse. Priority: nice-to-have
  > Socratic: Counter-arguments considered — that CODEOWNERS governs who
  > approves rather than what may be changed and so does not solve the
  > coarseness it was introduced for, that its priority is wrong if that
  > coarseness is real, and that it is a forge-specific convention that binds a
  > guardrail to particular providers. Resolution: none accepted. It was
  > recorded in phase 2 explicitly as a fallback, and nice-to-have is the honest
  > priority for a fallback. Stands as written.
- FR-160: A shipped GUI authenticates through a pluggable provider rather than a
  built-in identity system. Priority: nice-to-have
  > Socratic: No counter-argument accepted. Instead the user defined what the
  > GUI is for (2026-08-18), which turned an undecided component into a set of
  > capabilities — see the operation and cost visibility group below.

### Guardrails

Scope decided by the user on 2026-08-17: Henia implements all eight
framework-owned guardrails itself, because Henia's own design creates each of
the risks they close. The residual CI/CD risks — hardening of the SCM, pipeline
engine and registry the adopter already runs, human-level identity management,
and the adopter's own third-party sprawl — are published as an adopter checklist
rather than enforced by the framework. Each requirement below names the OWASP
entries it closes.

- FR-170: The text of a work item is treated as data and never as instructions;
  an agent's objective comes from the specification, not from the text that
  triggered the run. Priority: must-have
  *(ASI01 Agent Goal Hijack, ASI06 Memory & Context Poisoning)*
  > Socratic: Counter-arguments considered — that the specification is also text
  > written by whoever can write to the repository, making the spec/work-item
  > split a distinction in provenance rather than in kind; that taken strictly
  > the rule deletes the request the flow depends on, and taken loosely
  > constrains nothing; and that the property is not externally observable.
  > Resolution: none accepted. ASI01 is the top-ranked agentic risk and this is
  > the requirement that answers it. Stands as written.
- FR-180: Who may create a work item the framework will act on is decided by
  authorization, not by the presence of a label. Priority: must-have
  *(ASI01)*
  > Socratic: No counter-argument accepted; the user answered with a
  > consequence that must be made explicit instead (2026-08-18) — "with write
  > permissions to repository you allow controlling agents." Recorded as
  > FR-185. The open-source objection stands unresolved by design: a public
  > repository can still accept issues from anyone, but acting on one is an
  > authorization decision.
- FR-185: An adopting organization is told plainly what it is taking on: that
  granting write access to a repository grants the ability to direct that
  repository's agents, and which CI/CD risks Henia does not close and the
  organization must therefore cover itself. Priority: must-have
  *(one disclosure deliverable, merging what was FR-260 on the user's
  instruction, 2026-08-18; covers CICD-SEC-2, -7, -8 and the honest reading of
  FR-140's "git permissions decide")*
  > Socratic: Counter-arguments considered — that documentation ships last, so
  > three OWASP entries would rest on a file that may not exist at the
  > conference; that publishing what Henia does not protect reads to an audience
  > as an inventory of holes; and that it duplicated FR-260. Resolution: the
  > duplication was accepted and the two merged into this one deliverable. The
  > "ships last" risk is carried knowingly, and the priority is must-have rather
  > than nice-to-have precisely because of it.
- FR-190: An agent can reach only the network destinations explicitly allowed
  for its work item, and dependencies enter a sandbox only from sources the
  organization has approved. Priority: must-have
  *(ASI05 Unexpected Code Execution, CICD-SEC-3 Dependency Chain Abuse)*
  > Socratic: Counter-arguments considered — that an allowlist tight enough to
  > control is tight enough to degrade the agent, and it degrades silently
  > rather than erroring; that transitive package resolution means shipping a
  > proxy requirement to every adopter before step one; and that maintaining the
  > list converts a security property into permanent support load. Resolution:
  > none accepted. An autonomous agent with open egress is ASI05 unmitigated,
  > and automated dependency resolution with no human in the loop is CICD-SEC-3
  > at machine speed. Stands as written.
- FR-200: An agent's credentials are valid only for the duration of one work
  item and only for what that work item needs; production and pipeline secrets
  are never present in the inner loop. Priority: must-have
  *(ASI03 Identity & Privilege Abuse, CICD-SEC-5 Insufficient PBAC,
  CICD-SEC-6 Insufficient Credential Hygiene)*
  > Socratic: Counter-arguments considered — that "short-lived" is bound to the
  > life of a work item which FR-040 gives no bound, so a stuck item holds its
  > credential indefinitely; that the FR-060 tension remains unresolved with
  > both requirements at must-have; and that per-item credential issuance needs
  > infrastructure whose capabilities differ between providers. Resolution: none
  > accepted. It answers ASI03, CICD-SEC-5 and CICD-SEC-6 together and is what
  > makes FR-130's narrowing real rather than nominal. Stands as written; the
  > unbounded-lifetime point is partly met by FR-230's attempt and spend bounds
  > and by FR-240's expiry.
- FR-210: An agent cannot approve or merge its own work — the review gates that
  apply to a developer apply to an agent identity with no exception.
  Priority: must-have
  *(CICD-SEC-1 Insufficient Flow Control Mechanisms)*
  > Socratic: Counter-arguments considered — that "no exception" collides with
  > FR-117, since an automatically started incident investigation still waits
  > for review before anything lands; that it caps throughput on human review
  > permanently, moving the chore rather than removing it; and that enforcement
  > lives in the forge, so this is a promise about behavior rather than a
  > control Henia can guarantee. Resolution: none accepted. This is the single
  > line between autonomous and unreviewed-code-in-production. Stands as
  > written — and the FR-117 collision resolves in its favour: severe incidents
  > investigate without waiting, but nothing merges without review.
- FR-220: A change an agent proposes to the pipeline's own definition is
  privileged: it requires human review, and the checks that run on it hold no
  secrets. Priority: must-have
  *(CICD-SEC-4 Poisoned Pipeline Execution)*
  > Socratic: Counter-arguments considered — that the most common real fix for a
  > broken pipeline is a pipeline-definition change, so this makes the flagship
  > self-repair loop's main output need a human every time; that a check holding
  > no secrets cannot verify the change works, so the human approves something
  > nobody could test; and that the "touches the pipeline definition" boundary is
  > a path heuristic with doors in the walls (invoked scripts, image tags,
  > runner-installed dependencies). Resolution: none accepted. CICD-SEC-4 is an
  > agent editing the thing that judges it. Stands as written. **Conflict with
  > FR-025 resolved 2026-08-18:** the requirement is accepted as-is, because the
  > loop is reviewed rather than blocked — the agent still diagnoses, writes the
  > fix and opens the pull request, and only the merge waits for a person, which
  > FR-210 already makes true of everything else. The demonstration is a human
  > approving in seconds instead of debugging for an hour.
- FR-230: Work on a single item is bounded in attempts and in spend; on
  exhaustion the loop stops and hands back what it learned — what was tried,
  what failed, and the agent's current hypothesis — so a person resumes rather
  than restarts. Priority: must-have
  *(ASI08 Cascading Failures — also the direct answer to the burned-token cost
  named in the vision)*
  > Socratic: Counter-argument accepted — an attempt limit stops the agent
  > precisely at the difficult problems where autonomy is worth most, letting it
  > succeed only on easy ones; the demo then looks better than the product, and
  > the gap surfaces after adoption. Resolution: the bound is kept, but
  > exhaustion now hands back accumulated context instead of simply halting, so
  > the limit stops spend without discarding progress.
- FR-240: Any running agent can be stopped on demand, and every agent has a
  named owner and an expiry. Stopping leaves the branch, the sandbox and the
  queue entry in a stated, recoverable condition rather than simply terminating
  the agent. Priority: must-have
  *(ASI10 Rogue Agents)*
  > Socratic: Counter-argument accepted — killing an agent mid-work leaves a
  > branch, a sandbox and a queue entry in a partial state; stopping is the easy
  > half and leaving nothing broken behind is the half the requirement does not
  > state. Resolution: stopping now leaves a stated, recoverable condition, and
  > FR-330 lets a person resume or remove what a stopped agent left behind.
- FR-250: Every action is attributable to one agent run and to the work item
  that caused it, recorded in an append-only history; an agent-authored PR is
  visibly marked as such and is reviewed against its actual diff rather than the
  agent's description of it. Priority: must-have
  *(CICD-SEC-10 Insufficient Logging and Visibility, CICD-SEC-9 Improper
  Artifact Integrity Validation, ASI09 Human–Agent Trust Exploitation)*
  > Where it lives, decided 2026-08-18: Henia **emits** audit events rather than
  > storing them; the adopting organization's existing logging receives them.
  > The same delegate-to-native-mechanisms position taken for identity,
  > sandboxing and pipelines. Consequence accepted: FR-250's guarantee then
  > depends on infrastructure the adopter runs — the objection already recorded
  > against FR-080, now applying here too. This is what keeps Henia close to
  > stateless: everything vital is in git, telemetry is scraped, audit is
  > emitted.
  > Socratic: Counter-arguments considered — that it bundles four things
  > (attribution, immutability, PR labelling, and a review practice the
  > framework cannot enforce); that marking a PR as agent-authored may cue
  > reviewers to skim rather than scrutinise once volume rises, inverting its
  > own purpose; and that append-only history grows without bound and nobody has
  > decided who keeps it or for how long. Resolution: none accepted. Without
  > attribution, autonomy is unauditable. Stands as written.
*FR-260 was merged into FR-185 on 2026-08-18 at the user's instruction — the
residual-risk checklist and the write-access disclosure are one deliverable, not
two. The number is retired and not reused; its Socratic challenge is recorded
under FR-185.*

### Operation and cost visibility

Added 2026-08-18 when the user defined the purpose of the previously undecided
GUI. Most of these are operational capabilities rather than display: the limit,
the queue and the triage have to exist before anything can show them.
Priorities below are the facilitator's proposal.

- FR-270: The framework publishes its own operational telemetry for an external
  collector to read. Priority: must-have
  > Socratic: Counter-arguments considered — that its only stated consumer is
  > FR-310, which is nice-to-have, inverting the priority; that the adopter must
  > stand up a collector before seeing anything, putting another dependency in
  > front of first value; and that it makes Henia part of what FR-112 observes,
  > so the framework can generate work items about itself. Resolution: none
  > accepted. An autonomous system that cannot be watched from outside is not
  > operable. Stands as written.
- FR-280: The number of agents running at once is limited. Priority: must-have
  > Socratic: Counter-arguments considered — that a fixed ceiling undercuts the
  > elastic-scaling argument for the Kubernetes requirement locked in phase 1;
  > that what operators actually want to cap is spend, and agent count is a poor
  > proxy when FR-320 already knows the cost; and that this one requirement
  > generates three more (FR-290, FR-300, FR-310). Resolution: none accepted.
  > Unbounded concurrent agents is unbounded spend and unbounded blast radius —
  > ASI08 with no ceiling. Stands as written.
- FR-290: Work arriving beyond that limit waits in an overflow queue rather than
  being refused. Priority: must-have
  > Socratic: Counter-arguments considered — that queued work goes stale against
  > a moving codebase with nothing re-validating it before it runs; that
  > refusing would surface saturation instead of hiding it; and that the queue
  > has no bound of its own, so the concurrency cap merely relocates the
  > accumulation. Resolution: none accepted. Refusing work an authorized person
  > filed makes the framework unreliable in the ordinary case where the cap is
  > briefly exceeded. Stands as written.
- FR-300: The overflow queue is triaged rather than served strictly in arrival
  order, and the basis of the triage is visible. Priority: must-have
  > Socratic: Counter-arguments considered — that triage is a fourth tunable
  > judgement after FR-025, FR-114 and FR-117, each failing quietly in its own
  > way; that prioritisation without an ageing rule silently abandons the tail
  > rather than delaying it; and that a published ranking rule invites work
  > items written to score well rather than to describe the work. Resolution:
  > none accepted. A first-in-first-out queue would put a production incident
  > behind a routine feature, which FR-117 exists to prevent. Stands as written.
- FR-310: A person can see the current state at a glance — how many agents are
  running, what the limit is, what is waiting in the overflow queue, and how
  that queue is being triaged. Priority: nice-to-have
  > Socratic: Counter-arguments considered — that the priority is wrong because
  > a system with a limit, a queue and priced agents cannot be operated unseen
  > and FR-330 depends on somewhere to act from; that this view is what makes
  > the loop legible on stage and so may be the highest-value item in the build;
  > and that it is the first requirement demanding an interface rather than a
  > mechanism, pulling FR-160 in with it. Resolution: none accepted. The
  > underlying capabilities are what matter and FR-270 covers the operator case
  > machine-readably. Stands as written at nice-to-have.
- FR-320: Cost is attributable to a single work item and to a single running
  agent. Where the model provider reports actual cost it is used; otherwise cost
  is estimated from rates the operator supplies. Priority: must-have
  *(the direct answer to the burned-token cost named in the vision; pairs with
  FR-230's spend bound, which needs a cost figure to bound against)*
  > Socratic: Counter-arguments considered — that provider-reported and
  > rate-estimated cost are not comparable yet share one label, so FR-230 bounds
  > spend against a number whose meaning shifts; that per-item attribution is a
  > modelling decision presented as a measurement once retries, self-repair and
  > shared context are involved; and that cost visibility without a value
  > denominator measures spend rather than waste. Resolution: none accepted.
  > Burned tokens is the cost the vision names, and this makes it visible rather
  > than asserted. Stands as written.
- FR-330: What a stopped agent left behind can be resumed or removed by a
  person. Priority: must-have *(the operable half of FR-240)*
  > Socratic: Counter-arguments considered — that resuming restores the very
  > state that may have caused the stop, which is ASI06 by way of the recovery
  > path; that removal is irreversible and is the button people press when
  > unsure, making the cheap action the destructive one; and that it rests on
  > FR-310, a nice-to-have. Resolution: none accepted. It is the operable half
  > of the kill switch. Stands as written.

### Harness

Added 2026-08-18 after the user judged the harness under-designed — until this
point it existed only as a seam name in FR-120.

- FR-340: Agents share a store of working knowledge they can write to —
  plugins that shorten common work, lessons, and skills — so what one agent
  learns is available to the next. The store lives in the repository itself, so
  every change an agent makes to it passes the same review and attribution gates
  as a change to code. Priority: must-have
  > Socratic: Counter-argument accepted — plugins, lessons and skills are
  > artefacts, and a separate store would make the thing agents write most often
  > the one thing escaping every gate the guardrail set exists to enforce.
  > Resolution: the store lives in the repository. FR-210 (no self-merge),
  > FR-250 (attribution) and FR-105 (stated cause) now cover it for free, and
  > the ASI06 objection — that a skill is an instruction rather than data — is
  > answered by human review rather than by a new mechanism. The
  > wrong-lessons-compound objection is carried until FR-390, which closes it by
  > making a lesson a candidate that a person promotes into the specification
  > rather than a standing instruction nobody re-derives.
- FR-350: Working knowledge is scoped per repository, because different
  applications need different toolkits and different SDLC optimizations.
  Priority: must-have *(now a consequence of FR-340's placement rather than a
  separate mechanism)*
  > Socratic: Counter-arguments considered — that it forbids exactly the
  > inheritance the vision names as missing, since the most useful lessons are
  > the ones learned elsewhere; that a repository is a storage boundary being
  > used as a domain boundary, which fits neither monorepos nor multi-repo
  > systems; and that provider-shaped artefacts make FR-120's harness seam less
  > real, since switching providers discards everything accumulated.
  > Resolution: none accepted, and the scoping is intentional rather than a
  > limitation accepted reluctantly. In the user's words (2026-08-18): the point
  > is to protect the agent's context so that it holds only what serves the
  > project being worked on — polluting it with general advice would hinder the
  > agent rather than help it. The inheritance objection is answered by
  > declining the premise: general best practice belongs in the curated provider
  > list (FR-410) and in the specification, not in another project's accumulated
  > working knowledge.
- FR-360: When the upstream provider releases new capabilities, the framework
  opens a pull request against its own pinned version rather than updating
  silently — the upgrade passes the same review and checks as any other change,
  and carries the release's verified provenance so review sees both what changes
  and that it genuinely comes from upstream. Priority: must-have
  > Socratic: Counter-argument accepted — self-update is ASI04 by construction
  > and the single path that bypasses all eight guardrails at once: a poisoned
  > upstream release changes what every agent in every repository does, with no
  > pull request and no review. Resolution: the update path was turned into a
  > work item. The framework proposes its own upgrade and FR-210's no-self-merge
  > rule applies to it, so the back door becomes the product demonstrating
  > itself on its own repository. The reproducibility and attribution
  > objections are answered by the same change — the harness version is pinned
  > in the repository and every change to it is in the history. **Provenance
  > verification was added 2026-08-18** rather than deferred: the upgrade pull
  > request carries the release's verified provenance, so review is not asked to
  > detect a supply-chain compromise by reading a version number.
- FR-370: An agent receives the credentials it needs once, at start, from a
  broker that will not serve them again for the remainder of the run — so code
  executing later inside the sandbox cannot obtain them by asking.
  Priority: must-have *(CICD-SEC-6, ASI05; also the first real answer to the
  FR-060 vs FR-200 tension — the inner loop can hold what it needs at start
  without leaving it available to a compromised dependency)*
  > Socratic: Counter-arguments considered — that it narrows the window without
  > shutting it, since after the first read the secret sits in process memory,
  > the environment or git configuration where a hostile package reads it
  > without asking the broker again; that FR-040 puts no time bound on a work
  > item, so a long run outlives its token and is locked out of its own work;
  > and that a credential broker is Henia building what the platform already
  > provides, against the delegate-to-native-mechanisms position held since
  > phase 2. Resolution: none accepted. It is the first real answer to the
  > FR-060 / FR-200 deadlock. Stands as written — the residual exposure named in
  > the first objection is acknowledged and not closed.
- FR-380: A working set of external knowledge and telemetry tools ships with the
  harness, so an agent has them without per-project setup. Each such tool
  declares the destinations it needs, and installing it permits exactly those
  and nothing more. Priority: nice-to-have
  *(the user's phrasing was "might be bundled" — priority reflects the hedge)*
  > Socratic: Counter-arguments considered — that bundled third-party tools are
  > ASI04 and CICD-SEC-8 arriving with the framework's endorsement, inherited
  > rather than chosen; that external knowledge tools reach arbitrary hosts by
  > design, which is what FR-190's allowlist exists to prevent, so bundling
  > ships the exception on by default; and that a default tool set contradicts
  > FR-120's seam claim in the one area where an adopter most likely already has
  > a policy. Resolution: none accepted. An agent without research and telemetry
  > access re-derives what it could have looked up, which is the token burn the
  > vision targets. Stands as written at nice-to-have — with the endorsement
  > objection answered by FR-400 and FR-410 rather than by dropping the bundle.
- FR-390: A lesson an agent records is a candidate, not a standing instruction:
  it enters the project's specification only when a person promotes it there,
  and that promotion is a documented operational practice.
  Priority: must-have *(closes the wrong-lessons-compound objection carried from
  FR-340; also the point where the loop feeds the spec-driven development that
  phase 1 named as Henia's precondition)*
  > Socratic: Counter-arguments considered — that an unpromoted lesson still
  > steers agents in the window before promotion, making the gate decorative,
  > or else the store accumulates nothing without human action; that promotion
  > is unglamorous curation with no deadline and will lose to delivery work;
  > and that agents now pre-write changes to the specification that governs
  > them, which is ASI09 applied to the document defining correctness.
  > Resolution: none accepted. Stands as written.
- FR-400: A general-purpose tool available to agents is governed by stated rules
  that apply to any such tool, rather than being judged case by case.
  Priority: must-have
  > Socratic: Counter-arguments considered — that a documentation search, a code
  > index and a telemetry reader have too little in common for one rule set to
  > fit any of them well; that stating what a tool may do does not prevent it,
  > since nothing checks behavior at invocation as ASI02 asks; and that FR-190's
  > allowlist already governs what a tool may reach, so this is a second layer
  > on the same question. Resolution: none accepted. Judging each tool case by
  > case is CICD-SEC-8 by accretion. Stands as written.
- FR-410: The framework ships a curated starting list of tool providers, chosen
  as best practice for making agents more productive.
  Priority: nice-to-have *(tracks FR-380's priority — the list matters only if
  a bundle ships; FR-400's rules apply either way)*
  > Socratic: Counter-arguments considered — that a best-practice list is a
  > standing commitment which ages, and a stale one is worse than none because
  > it carries the project's endorsement with no named owner; that an
  > open-source project heading for the CNCF publishing recommended commercial
  > providers is making a market, and vendor pressure becomes a governance
  > problem before a technical one; and that the priority is wrong, since a list
  > is the reference implementation of FR-400's must-have rules. Resolution:
  > none accepted. A starting list is what spares every adopter from
  > rediscovering which tools make agents productive — the inheritable best
  > practice the vision says the market lacks. Stands as written at
  > nice-to-have.

> **Guardrail interactions raised by the facilitator, unresolved.** These four
> requirements land directly on OWASP entries the project has already committed
> to closing, and none of the existing guardrails reach them:
>
> - FR-340 is ASI06 in its strongest form. A store that agents write and later
>   agents read is persistent shared memory that steers future behavior — and a
>   skill or a lesson is not data, it *is* an instruction. FR-170 says work-item
>   text is never instructions; FR-340 creates a channel where agent-authored
>   text becomes exactly that. Writing a plugin is also an agent extending its
>   own tool surface, which is ASI02 and ASI04.
>   **Closed 2026-08-18** — the store lives in the repository, so every write to
>   it is a reviewed pull request.
> - FR-360 is ASI04 by construction. Self-update from upstream is the classic
>   supply-chain path, and OWASP's answer is signed releases with verified
>   provenance before loading — a requirement that does not exist yet.
>   **Closed 2026-08-18** — the upgrade arrives as a pull request against a
>   pinned version. Provenance verification was considered, not taken, and
>   remains open for the stack step.
> - FR-380 bundles third-party tools, which is ASI04 again plus CICD-SEC-8, and
>   external knowledge tools need network reach that FR-190's allowlist governs.
>   A telemetry tool in the bundle also feeds the agent telemetry directly,
>   which is the path FR-113 covers.
>   **Closed 2026-08-18** — FR-400 states general rules for general tools,
>   FR-410 makes the bundle a curated list rather than an accident, and each
>   tool now declares the destinations it needs so installing it permits exactly
>   those. The allowlist stays meaningful and the curated list becomes partly a
>   list of network commitments.
> - FR-370 is the one that closes rather than opens: it is a genuine answer to
>   CICD-SEC-6 and the strongest response yet to the FR-060/FR-200 conflict.

### Transitions

Added 2026-08-18 in phase 5. The business rule made the SDLC transition model
the centre of the product; these are the transitions it names that no earlier
requirement covered.

- FR-415: The framework starts from a conventional SDLC transition model and
  learns where a project departs from it; the resulting model is kept as a
  reviewed artefact in that project's repository. The learned model may add,
  reorder or refine transitions, but can never remove or weaken a gate the
  guardrails fix. Priority: must-have
  > Socratic: Counter-argument accepted — a new project has no history to learn
  > from, so the framework either ships a default (the fixed SDLC the
  > requirement rejected) or does nothing useful until enough work has passed
  > through, and the cold-start case is the adoption case. Resolution: a default
  > is shipped and what is learned is the deviation from it. This narrows the
  > business rule consciously: Henia does carry an SDLC, and the claim is that
  > the operative model is the project's wherever it differs. The other two
  > objections are carried — a learned model reproduces the team's existing
  > dysfunction along with its practice. **The precedence question was resolved
  > 2026-08-18: guardrails always win.** The learned model may add, reorder or
  > refine transitions but never remove or weaken a fixed gate — so a team whose
  > real process skips review simply cannot have that learned, by construction.
  > **The dysfunction objection was closed on the same basis, 2026-08-18:** the
  > model is a reviewed artefact and no deviation can weaken a fixed gate, so a
  > team that approves its own dysfunction into the model has made a decision
  > rather than suffered an accident — the standard applied everywhere else in
  > the design.
- FR-420: A person's review comments on a pull request become work the agent
  takes up. Priority: must-have
  > Socratic: Counter-arguments considered — that a review comment is free text
  > from anyone who can comment, making this the widest ASI01 surface in the
  > design on the artefact with the most participants; that reviewers write
  > questions, doubts and jokes as often as directives, and one who learns the
  > agent acts on all of them will stop commenting honestly; and that it turns
  > review into a second authoring channel, so the reviewer approves work shaped
  > by their own half-formed remarks. Resolution: none accepted. Human
  > suggestions shaping the pull request is one of the transitions named in the
  > business rule, and the most common one in practice. Stands as written — the
  > ASI01 exposure is acknowledged and is the largest one carried.
- FR-430: A pull request can be dropped when a person decides the work should
  not proceed, and what led to that decision is kept rather than discarded.
  Priority: must-have
  > Socratic: Counter-arguments considered — that "kept" does not say what
  > consumes it, so it either needs FR-390's promotion gate or is an archive
  > nobody reads; that recorded rejection reasons are systematically the
  > diplomatic ones rather than the true ones, so the framework learns from a
  > distorted record; and that nothing covers the agent concluding the work
  > should not proceed, a state FR-230's hand-back can already reach.
  > Resolution: none accepted. A terminal rejection state was missing from the
  > design, and discarding the reasoning is how the same wrong work gets
  > proposed again. Stands as written.
- FR-440: A unit of work found too large can be divided into descendant units,
  and the relationship between a parent and its descendants survives the queue
  and its triage. Each descendant receives a fresh budget, and the number of
  times a single lineage may be divided is capped. Priority: must-have
  > Socratic: Counter-arguments considered — that deciding where a slice divides
  > is architectural judgement, and a bad split yields descendants that each
  > pass review while together making no coherent change; that splitting
  > multiplies FR-230's per-item budget, so an exhausted item can be divided
  > into descendants that each get a fresh one; and that FR-300's triage has no
  > parent semantics, leaving a half-delivered family of descendants possible.
  > Resolution: none accepted. MVP-too-big was the anti-pattern that fired in
  > phase 3, and a framework that recognises an oversized slice and divides it
  > is the product answering a problem the project hit itself. Stands as
  > written. **Budget multiplication resolved 2026-08-18:** the reset is
  > deliberate — a split is evidence the original framing was wrong, so a fresh
  > budget is the correct response — and the escape hatch is closed by capping
  > how many times one lineage may divide. The cap is a fifth tunable threshold,
  > accepted knowingly.

### Instances and supervision

Added 2026-08-18 in phase 6, from the user's description of how Henia is
reached: it is not opened, it is installed and projects are declared into it.
The component names and the declaration mechanism are stack questions and are
recorded in the tech-stack forward block; these requirements state only what is
observable.

- FR-450: An instance of the framework runs its own main loop and may manage a
  single repository, several repositories, or a monorepo. How repositories are
  grouped into instances is decided by the person deploying, and further
  instances are created by declaration alone. Priority: must-have
  > Socratic: Counter-arguments considered — that a loop per project is idle
  > machinery for every quiet repository; that isolated instances each hold
  > their own limit and queue, so nothing arbitrates between projects competing
  > for the same cluster and organisation-wide spend has no ceiling; and that
  > per-project isolation multiplies everything individually misconfigurable.
  > Resolution: accepted in part — the requirement no longer mandates one
  > instance per project. Grouping is the deployer's decision, monorepos and
  > multi-repository instances are both supported, and running many instances is
  > made cheap rather than made necessary. The cross-instance spend ceiling is
  > decided 2026-08-18: bounds and pricing stay per-instance, and an
  > organization sums across instances itself using the metrics FR-270 and
  > FR-320 already publish. No new mechanism. The consequence is accepted
  > knowingly — the guarantee Henia offers is smaller than the problem its
  > vision names, and organization-wide spend is bounded by arithmetic the
  > adopter performs rather than by anything the framework enforces.
- FR-460: A project is brought under management by declaring its configuration;
  the framework creates and configures that project's instance from the
  declaration. Who may make that declaration is decided by the platform's own
  access control. Priority: must-have
  > Socratic: Counter-arguments considered — that declaring a project creates an
  > autonomous actor with repository write access and nothing controls who may
  > do so, which is a larger permission than FR-180's control over filing work;
  > that the declaration and the instance's learned behaviour (FR-415, FR-340)
  > drift into two sources of truth; and that it front-loads every setup
  > decision before any value is visible. Resolution: none accepted. A declared
  > configuration is reviewable, versionable and diffable, which is the position
  > the design takes everywhere else. **Who may declare a project, resolved
  > 2026-08-18:** delegated to the platform's own access control, the same
  > position taken for sandboxing and pipelines. Consequence recorded — the
  > permission sits with cluster administrators rather than with repository
  > owners, who are the ones who would notice a wrong answer.
- FR-470: A supervising layer manages the lifecycle of each instance. An
  instance is healthy when all of its components are running; restarts below
  that level are handled inside the instance's own main loop and are not the
  supervising layer's concern. Priority: must-have
  > Socratic: Counter-arguments considered — that nothing supervises the
  > supervisor, which is the highest-value target with no guardrail pointed at
  > it; that "healthy" would be satisfied by a loop that runs while making no
  > progress; and that supervisor-initiated restarts would bypass FR-240's
  > requirement to stop into a recoverable condition. Resolution: all three
  > answered by the user (2026-08-18) rather than by changing the design. The
  > supervising layer is itself supervised by the platform, consistent with the
  > delegate-to-native-mechanisms position held since phase 2. Health means all
  > components running — deliberately a liveness definition, not a progress
  > definition. Agent restarts stay inside the instance's main loop, so
  > FR-240's guarantee is not bypassed. This is an established architecture
  > used by comparable projects and is not being reinvented.

### Guardrails (continued)

Coverage already carried by earlier requirements: ASI05 and CICD-SEC-4 partly by
the sandbox (FR-030, FR-060); ASI03 partly by the agent's own git identity
(FR-130, FR-140); ASI08 partly by one sandbox per agent (FR-050). ASI02 Tool
Misuse and ASI04 Agentic Supply Chain Compromise apply to the harness, skills and
seam providers Henia itself loads — partly reached by FR-190 and FR-200, not yet
addressed for runtime-loaded providers.

> Pending, raised by the facilitator and unanswered: ASI07 Insecure Inter-Agent
> Communication disappears entirely if MVP agents run in parallel without
> communicating. If that is true it belongs in the non-goals as a deliberate risk
> reduction. Asked at the excluded-scope round.

**Sources ingested 2026-08-17:** OWASP Top 10 CI/CD Security Risks
(owasp.org/www-project-top-10-ci-cd-security-risks); OWASP Top 10 for Agentic
Applications 2026, published 2025-12-09 by the OWASP GenAI Security Project
(genai.owasp.org).

## Non-Functional Requirements

Externally observable properties, drawn from decisions already taken. Binary
properties where no number was established; no number was invented.

- A deployment's durable storage does not grow with the volume of work
  performed. Everything that accumulates is held in the repository or emitted
  to the adopting organization's own systems; what the framework itself holds
  is agent workspaces, sized by how many agents run at once rather than by how
  much work has been done.
- One project's instance ceasing to function does not stop another project's
  instance.
- The framework's operational state is observable from outside it, without
  access to its internals.
- A credential cannot be obtained from inside a sandbox after the agent has
  started.
- Every action an agent takes can be traced to the work item that caused it.

**Deliberately absent: any target for how quickly a work item begins to be
worked.** The user declined to state one on 2026-08-18. Recorded as a decision
rather than an oversight — the consequence is that `/101-tech-stack-selector`
has nothing to weigh notification approaches against, and the live demonstration
depends on timing nobody has committed to.

## Business Logic

**Henia learns the transition paths of the SDLC it is operating in — every point
where a unit of work changes form is a transition it must recognize and learn
from, including the ones where work is rejected or has to be split.**

The transitions the user named, 2026-08-18: an issue becoming a pull request;
human suggestions shaping what the pull request becomes; a pull request reaching
the point of being shippable; a pull request being dropped, with what led to
that becoming something to learn from; and a slice found too large being divided
into descendants.

The rule is what separates Henia from a queue with agents attached. A dispatcher
knows only the states its author gave it. Henia starts from a conventional set
and treats every project as a departure from it, so the operative model is the
project's wherever the two differ — which is why working knowledge is scoped per
repository (FR-350) rather than pooled.

The framework therefore does carry an SDLC, deliberately and visibly: a project
with no history has nothing to learn from, and the cold start is the adoption
case (FR-415). What the rule claims is not that Henia arrives empty, but that
what it arrives with is a starting position rather than a constraint.

A person encounters the rule at the points where it disagrees with them. When a
unit of work is split, they see descendants they did not create. When a pull
request is dropped, they see that the reasoning was kept rather than discarded.
When their review comments come back as changed code rather than as a reply,
they are seeing a transition Henia learned from watching the project, not one
that was configured.

Because the deviations are learned, the model is an artefact of the project: it
lives in the repository and every change to it is reviewed, under the same rule
as any other thing an agent writes (FR-340). The framework does not silently
revise the model it is working from.

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

## Non-Goals

Confirmed by the user on 2026-08-18. Each is a decision taken, not work
deferred.

- **Agents do not communicate with each other.** They run in parallel (FR-050)
  but never coordinate, delegate to, or message one another. This removes
  **ASI07 Insecure Inter-Agent Communication** from the risk surface by design
  rather than by omission — the only OWASP entry in either list that Henia
  closes by declining a capability instead of building a control.
- **Henia does not supply spec-driven maturity.** It requires the adopting
  organization to arrive with it, as settled in phase 1; the market already has
  mature educational resources for SDD. The framework feeds the specification
  back (FR-390) but does not teach the practice.
- **Henia does not harden the adopter's existing environment.** The security of
  the forge, pipeline engine and registry the organization already runs stays
  theirs — CICD-SEC-2, CICD-SEC-7 and CICD-SEC-8 — and FR-185 says so to them
  explicitly.
- **Working knowledge is not pooled across projects.** Per-repository scoping
  (FR-350) is intentional context protection, not a limitation awaiting a fix:
  general advice hinders an agent rather than helping it, and the 100× probe
  confirmed the isolation is what lets the transition rule scale.

Technology exclusions are deliberately absent from this list; stack-shaped
decisions live in the forward blocks.


## Open Questions

**None.** The shaping session's quality gate closed `clean`: fifteen gaps were
named with their consequences and all fifteen were filled rather than accepted,
so there is no gap marker anywhere in this document to mirror here.

Three items are carried knowingly and are recorded as decisions rather than as
gaps, because each was decided rather than left open:

- Cross-instance spend is bounded by arithmetic the adopting organization
  performs over published figures, not by anything the framework enforces. The
  guarantee is therefore smaller than the cost the vision names.
- The permission to bring a project under management sits with whoever
  administers the platform, rather than with the owners of the repository being
  managed — who are the people who would notice a wrong answer.
- No target exists for how quickly a work item begins to be worked. Declined
  deliberately; the consequence is that the stack step has nothing to weigh
  notification approaches against.

Two process notes, for the reviews that follow:

- **FR-085 has not been through a Socratic challenge.** It was added on
  2026-08-18 during generation, after the challenge round had closed. Every
  other requirement carries exactly one; this one carries none.
- **Deliberate technical-leak deviations**, kept by decision and listed so they
  are visible rather than hidden: `Kubernetes` in `## Vision & Problem
  Statement`, in the User Stories main path, in US-01, in FR-030 and in
  `## Access Control`; `Gitea`, `pi.dev` and `knest` in the User Stories MVP
  boundary; `CODEOWNERS` in FR-150 and `## Access Control`; and `broker` in
  FR-370, which names an enforcement mechanism where the matching
  non-functional requirement states the same property observably. Of these,
  `pi.dev` and `knest` are the two with no stated product-identity
  justification — they are seam implementations, and a later decision to move
  them into the forward block would cost this document nothing.
