# JOURNEY

Append-only engineering log for str8t. Raw material for two things: the
`/101-lesson` rules in `context/foundation/lessons.md`, and the
post-mortem-style talk described in `content/CFP.md`.

**Why this file exists.** `plan.md` records what we intended, git records
what we shipped. Neither records what *bit* us — the dead ends, the
assumption that turned out false, the workaround we're not proud of. Those
are the talk. They evaporate within a week if nobody writes them down the
day they happen.

## Rules

- **Append only.** New entries go at the bottom. Never edit or delete a past
  entry — if we later learn it was wrong, write a new entry saying so and
  link back. Being wrong on the record is the point.
- **Write it the day it happens**, not at the end of a phase. A friction
  point summarized a week later has already been sanded smooth.
- **Dead ends are entries.** Something we tried that didn't work is worth
  more here than something that worked first time.
- **Not a status report.** "Implemented phase 2" is not an entry. What
  surprised us during phase 2 is.
- A `Lesson candidate` line is a promise to run `/101-lesson` — not a
  substitute for it.

## Entry format

    ## YYYY-MM-DD — Short title
    **Context** — what we were trying to do.
    **Friction** — what actually happened, including the wrong turn.
    **Resolution** — what we did, or `unresolved` / `deferred`.
    **Lesson candidate** — the general rule, or `none`.

Omit a field only when it is genuinely empty. `Resolution: unresolved` is a
better entry than a missing field.

---

## 2026-08-17 — Repo is a template graft, and it shows

**Context** — first working session. Goal was to stand up the 101 toolkit
loop, an `AGENTS.md`, and this file, before any shaping happens.

**Friction** — the repo is not the clean greenfield the CFP implies. Only
`LICENSE` and `README.md` are tracked by git; everything else
(`devcontainer/`, `context/`, `content/`, `docs/`, `.claude/skills/`) is
untracked working state carried over from another project. Two concrete
consequences:

- `devcontainer/README.md` documents infrastructure that does not exist
  here — `deploy/`, `scripts/`, `.pre-commit-config.yaml`, `.mcp.json`,
  `.githooks/`, a Prisma/Vite/React Router app, and issue references to
  `kondi/shirabe.studio#63`. Read literally, it describes a different
  repository. An agent onboarding from it would confidently run commands
  that cannot work.
- There is no `.gitignore` at all — while `devcontainer/creds.yaml` (git
  password, Exa API key) and `devcontainer/kubeconfig.yaml` (a
  ServiceAccount token, minted with a 10-year default validity) both sit in
  the working tree. The README calls both "gitignored". They are not; the
  `.gitignore` that made that true lived in the repo this was grafted from.
  One `git add -A` publishes a long-lived cluster credential.

**Resolution** — added a `.gitignore` covering both paths before anything
else. `devcontainer/README.md` is left as-is for now and treated as
untrusted documentation: `AGENTS.md` was written from the files that
actually exist, not from that README. Reconciling or splitting it is
deferred to its own change.

**Lesson candidate** — inherited documentation is a claim, not a fact.
Before onboarding an agent onto a grafted repo, verify every path a README
cites still exists; the gap between "documented" and "present" is where the
agent's first confident wrong action comes from.

## 2026-08-17 — The straitjacket's first hole is the one nobody threatens

**Context** — the CFP frames the threat model as prompt injection escalating
to cluster writes, defended by read-only RBAC plus a Git/Argo CD write path.

**Friction** — the first real exposure found in the repo had nothing to do
with RBAC. The read-only `view` binding in `devcontainer/k8s/rbac.yaml`
holds fine; the credential that *authenticates* as that identity was sitting
unignored in a git working tree, next to a `git push` password with write
access to the very repository that is supposed to be the single source of
truth. The Git write path is the intended escape hatch from the straitjacket
— so a leaked git credential is a cluster-write primitive that never touches
`kubectl` and never trips a single RBAC check.

**Resolution** — `.gitignore` closes the immediate leak. The broader
question — what the blast radius of the *permitted* write path actually is,
and whether the Argo CD side needs its own guard — is deferred to shaping.

**Lesson candidate** — when you harden one path and leave exactly one way
out, that way out inherits the entire threat model. Audit the escape hatch
at least as hard as the wall.

## 2026-08-17 — Surveyed open-mercato/skills and open-mercato/cezar

**Context** — rather than reinvent the pipeline, evaluate two MIT upstreams
for reuse, against three boundaries: keep the pi.dev harness, integrate
Gitea-first with other forges as plugins, add the k8s/GitOps layer.
Cloned to `3rd_party/` (gitignored — reference checkouts, not vendored).

**Friction** — three things the survey turned up that change the plan:

- **The plugin seam we were going to design already exists twice, in two
  incompatible forms.** `skills` has a *tracker-provider* seam: no skill
  ever calls `gh`; skills name ~50 operations and one committed Markdown
  descriptor (`.ai/trackers/<name>.md`) says how to execute each. Gitea
  support there is one Markdown file, no code. `cezar` has a *forge-driver*
  seam: a TypeScript `ForgeDriver` interface in
  `packages/cezar/src/server/forge/types.ts`. Same concept, different
  substrate — a Gitea integration has to be written twice unless one of
  them is dropped.
- **cezar's forge seam is less pluggable than its own comments claim.**
  `index.ts` says "GitLab lands here later as one more row", but selection
  runs through `FORGE_HOSTS`, a hardcoded hostname table keyed on
  `github.com`. A self-hosted Gitea lives at an arbitrary hostname, so a
  host table cannot classify it — forge resolution has to become
  config-driven first. `ForgeKind` is also a literal `'github'` union, and
  `github.ts` is 112 KB. This is not a one-row change.
- **We now have three SDLC toolkits in play** — the 101 skills already
  installed, the 36 `om-*` skills, and cezar's own YAML workflows — for a
  project whose actual deliverable is a conference talk. cezar alone is
  ~97k LOC of TypeScript (54k of it cockpit UI in `packages/web`) on 50
  commits of history.

**Resolution** — nothing adopted yet; this is input to shaping. What is
settled: neither upstream contains a single mention of Kubernetes, kubectl
or Argo CD (grepped both trees). The GitOps straitjacket is genuinely ours
to build, which is the right shape — the reusable part is the pipeline, the
novel part is the talk's subject.

**Lesson candidate** — "it has a plugin seam" and "our case plugs into it"
are different claims. Read the seam's *selection* mechanism, not just its
interface: cezar's `ForgeDriver` is clean, and the hostname table upstream
of it is what actually blocks self-hosted forges.

## 2026-08-17 — Two toolkits, two phases, one boundary between them

**Context** — resolving the three open questions from the upstream survey.

**Resolution** — decided by the user:

- **The 101 toolkit is the bootstrap, not the steady state.** It does the
  spec-driven work of *building* the harness. Once the harness is deployed
  and running autonomous agents, the entry point becomes a Gitea issue
  tagged `#feature`, and the automation framework takes it from there. The
  `om-*` skills and cezar's workflows are what that steady state shifts to
  or models on — they already assume the SDD work is finished and the SDLC
  is purely git-based.
- **Forking cezar stays open**, specifically to avoid hand-building a GUI.
  Inspiration-only is the alternative; not decided.
- **Provider-agnostic is a day-one requirement**, not a later
  generalization. Gitea is the first implementation, explicitly a PoC —
  the reference implementation, not a special case.

**Friction** — two consequences that were not obvious when the questions
were asked:

- **The dogfooding loop is the injection surface.** "File a Gitea issue
  tagged `#feature` and the framework picks it up" means an issue body —
  untrusted text from anyone who can file one — becomes agent input, at
  exactly the moment no human is in the loop to catch an imperative fix.
  Phase A has a human at every 101 gate; Phase B has none. The
  straitjacket therefore matters *least* while we are building it and
  *most* once it works. This is the CFP's third bullet arriving as a
  concrete design constraint rather than a talk topic.
- **cezar has the missing organ.** `packages/cezar/src/automations/`
  polls `issue.opened` / `issue.labeled` / `issue.unlabeled` with label
  filters on an interval, and dispatches through a task template. That is
  precisely the `#feature`-tag trigger, already built — and, like the rest
  of it, GitHub-shaped and needing the same provider-agnostic treatment.
  It strengthens the fork case well beyond "we get a GUI".

**Lesson candidate** — when a design has a bootstrap phase and a steady
state, ask which phase each safety control actually protects. Controls
inherited from the phase with a human in the loop are the ones most likely
to be load-bearing, untested, and wrong in the phase without one.
