---
starter_id: kubebuilder          # NOT IN THE REGISTRY — see the note below
project_name: henia-operator
hints:
  language_family: go
  team_size: solo
  deployment_target: kubernetes
  ci_provider: tekton            # off-enum, acknowledged deviation
  ci_default_flow: auto-deploy-on-merge
  bootstrapper_confidence: expected
  path_taken: custom
  quality_override: false
  self_check_answers:
    typed: true
    from_official_starter: true
    conventions: true
    docs_current: true
    can_judge_agent: true
  has_auth: true
  has_payments: false
  has_realtime: false
  has_ai: true
  has_background_jobs: true
---

## Why this stack

Henia is a Kubernetes operator, and Go is where that pattern lives:
controller-runtime, kubebuilder and every comparable CNCF project assume it,
which matters more than usual for a solo builder leaning on an agent that has
seen those conventions thousands of times. Kubebuilder was chosen over Operator
SDK and bare controller-runtime because it is the Kubernetes project's own
scaffold and generates a layout opinionated enough that non-idiomatic work is
visible on sight. All four agent-friendliness gates pass, so no compensation
convention is needed and no quality override was taken. Two hard exclusions
apply: pure Go with no CGO, keeping the operator image statically linked and
small; and no hosted service required for the framework to run, so an adopter
can run it entirely inside their own cluster. Two deliberate deviations are
recorded rather than hidden. First, the starter is absent from this toolkit's
registry — the `go` family and the `automation` product type are both uncovered,
and extending the registry was declined — so `/101-bootstrapper` will refuse
this identifier and scaffolding is manual until a card is added. Second,
`ci_provider` is Tekton, outside the contract's enum: Henia delivers pipeline
configuration to git and lets a declarative engine reconcile it, so running its
own pipeline that way is the product exercising its own design. Merges deploy
automatically, matching the requirement that a merged change reconciles with no
further human action.
