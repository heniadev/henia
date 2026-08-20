#!/usr/bin/env bash
#
# Verify the cluster-substrate success criteria against the live cluster.
#
# Every check names the plan criterion it closes
# (context/changes/cluster-substrate/plan.md, ## Progress), so the output maps
# one-to-one onto the checkboxes. Run it, read the table, confirm.
#
# A check that cannot run says SKIP and why. SKIP is never PASS: a criterion
# that needs a credential, a Docker host or a write to the cluster stays
# visibly unclosed rather than quietly green.
#
# Environment:
#   HARBOR_URL   default http://harbor.tachiko.kondi.net
#   PROM_URL     default http://prometheus.tachiko.kondi.net
#   PROM_AUTH    user:password for the Prometheus ingress. Without it the
#                phase 7 checks SKIP. Read it from /root/prometheus-basic-auth.txt
#                on tachiko; pass it in the environment, never on the command line.
#
# Exit status: 0 if nothing failed, 1 otherwise.

set -uo pipefail

HARBOR_URL="${HARBOR_URL:-http://harbor.tachiko.kondi.net}"
PROM_URL="${PROM_URL:-http://prometheus.tachiko.kondi.net}"
PROM_AUTH="${PROM_AUTH:-}"
KUBECTL="${KUBECTL:-kubectl}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0 FAIL=0 SKIP=0
FAILED_IDS=() SKIPPED=()

if [[ -t 1 ]]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; N=""
fi

section() { printf '\n%s%s%s\n' "$B" "$1" "$N"; }
pass()    { PASS=$((PASS+1)); printf '  %sPASS%s  %-5s %s\n' "$G" "$N" "$1" "$2"; }
fail()    { FAIL=$((FAIL+1)); FAILED_IDS+=("$1"); printf '  %sFAIL%s  %-5s %s\n' "$R" "$N" "$1" "$2"
            [[ -n "${3:-}" ]] && printf '        %s\n' "$3"; }
skip()    { SKIP=$((SKIP+1)); SKIPPED+=("$1 — $3"); printf '  %sSKIP%s  %-5s %s\n' "$Y" "$N" "$1" "$2"
            printf '        %s\n' "$3"; }

# check <id> <description> <command...> — PASS on exit 0, FAIL otherwise.
check() {
  local id="$1" desc="$2"; shift 2
  local out
  if out="$("$@" 2>&1)"; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc" "${out%%$'\n'*}"
  fi
}

have_cluster=0
if $KUBECTL version >/dev/null 2>&1; then have_cluster=1; fi

# ---------------------------------------------------------------- phase 1 ----
section "Phase 1 — devcontainer Go toolchain"

if [[ "$(command -v go 2>/dev/null)" == /usr/local/go/bin/go ]] \
   && go version 2>/dev/null | grep -q 'go1\.26\.'; then
  pass "1.3" "go 1.26.x, from the image at /usr/local/go"
else
  fail "1.3" "go 1.26.x, from the image at /usr/local/go" \
       "got '$(command -v go || echo none)' / '$(go version 2>&1 || true)'"
fi

if kubebuilder version 2>/dev/null | grep -q 'v4\.15\.0'; then
  pass "1.4" "kubebuilder v4.15.0"
else
  fail "1.4" "kubebuilder v4.15.0" "$(kubebuilder version 2>&1 | head -1)"
fi

missing=""
for t in kubectl tea kustomize sops; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [[ -z "$missing" ]]; then
  pass "1.5" "kubectl, tea, kustomize, sops all resolve"
else
  fail "1.5" "kubectl, tea, kustomize, sops all resolve" "missing:$missing"
fi

# 1.1 and 1.2 were absent entirely until review round 2 (F7). The header above
# claims the output maps one-to-one onto the checkboxes; it mapped 41 of 43.
if command -v droast >/dev/null 2>&1; then
  if droast_out="$(droast devcontainer/Dockerfile 2>&1)"; then
    if grep -qE '[1-9][0-9]* error' <<<"$droast_out"; then
      fail "1.1" "droast reports no errors on devcontainer/Dockerfile" \
           "$(grep -m1 'Summary' <<<"$droast_out")"
    else
      pass "1.1" "droast reports no errors on devcontainer/Dockerfile"
    fi
  else
    fail "1.1" "droast reports no errors on devcontainer/Dockerfile" "droast exited non-zero"
  fi
else
  skip "1.1" "droast reports no errors on devcontainer/Dockerfile" "droast is not installed"
fi

# The pinned download URLs must still resolve. Network-dependent, so a failure
# to reach them is a SKIP; only a definite 4xx/5xx is a FAIL.
GO_URL="https://go.dev/dl/go1.26.7.linux-$(dpkg --print-architecture 2>/dev/null || echo amd64).tar.gz"
KB_URL="https://github.com/kubernetes-sigs/kubebuilder/releases/download/v4.15.0/kubebuilder_linux_$(dpkg --print-architecture 2>/dev/null || echo amd64)"
url_bad=""
url_unreachable=""
for u in "$GO_URL" "$KB_URL"; do
  c="$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 20 -I "$u" 2>/dev/null)" || c=""
  if [[ -z "$c" || "$c" == "000" ]]; then url_unreachable="$url_unreachable $u"
  elif [[ "$c" != "200" ]]; then url_bad="$url_bad $u($c)"; fi
done
if [[ -n "$url_bad" ]]; then
  fail "1.2" "the pinned Go 1.26 and kubebuilder v4.15.0 URLs resolve" "$url_bad"
elif [[ -n "$url_unreachable" ]]; then
  skip "1.2" "the pinned Go 1.26 and kubebuilder v4.15.0 URLs resolve" "no network reachability"
else
  pass "1.2" "the pinned Go 1.26 and kubebuilder v4.15.0 URLs resolve"
fi

skip "1.6" "clean-context image rebuild" \
     "needs a host with Docker: docker build --no-cache -t henia-devcontainer devcontainer/"

# ---------------------------------------------------------------- phase 2 ----
section "Phase 2 — operator scaffold"

check "2.1" "go build ./... succeeds"     go build ./...
check "2.2" "go vet ./... reports nothing" go vet ./...

CRD=config/crd/bases/henia.dev_herds.yaml
CG=""
for c in bin/controller-gen bin/controller-gen-v*; do
  [[ -x "$c" ]] && CG="$c" && break
done
if [[ -z "$CG" ]]; then
  skip "2.3" "regeneration produces no diff" "no controller-gen in bin/ — run 'make controller-gen'"
elif ! git diff --quiet -- api config 2>/dev/null; then
  skip "2.3" "regeneration produces no diff" "api/ or config/ already dirty; commit or stash first"
else
  # controller-gen's exit status is a result, not noise. Discarded, a binary
  # that exists and is executable but fails at runtime - wrong architecture,
  # missing loader, a renamed flag - regenerates nothing, leaves the tree
  # unchanged, and this check reports PASS having verified nothing. Review
  # round 2, finding F1; same class as the 2.7 rewrite below.
  cg_err=""
  "$CG" rbac:roleName=manager-role crd webhook paths="./..." \
        output:crd:artifacts:config=config/crd/bases >/dev/null 2>&1 \
    || cg_err="crd/rbac generation failed (exit $?)"
  if [[ -z "$cg_err" ]]; then
    "$CG" object:headerFile="hack/boilerplate.go.txt" paths="./..." >/dev/null 2>&1 \
      || cg_err="deepcopy generation failed (exit $?)"
  fi
  if [[ -n "$cg_err" ]]; then
    fail "2.3" "regeneration produces no diff" "$CG: $cg_err"
  elif git diff --quiet -- api config; then
    pass "2.3" "regeneration produces no diff"
  else
    fail "2.3" "regeneration produces no diff" \
         "the regenerated diff is in your working tree — inspect with 'git diff api config'"
  fi
fi

if grep -q 'group: henia.dev' "$CRD" && grep -q 'kind: Herd' "$CRD" \
   && grep -q 'name: v1alpha1' "$CRD"; then
  pass "2.4" "CRD declares henia.dev / v1alpha1 / Herd"
else
  fail "2.4" "CRD declares henia.dev / v1alpha1 / Herd" "checked $CRD"
fi

if grep -q 'categories:' "$CRD" && grep -q 'shortNames:' "$CRD"; then
  # The per-criterion SKIP sweep of round 1 (F4) missed this one: its cluster
  # dependency sits inside a check whose else-branch is `fail`, so a run
  # without a cluster reported FAIL for something it simply could not reach.
  # Round 2, F7.
  if [[ "$have_cluster" != 1 ]]; then
    skip "2.5" "CRD carries categories + shortName, 'kubectl get henia' resolves" \
         "markers are present; the resolution half needs cluster access"
  elif $KUBECTL get henia -A >/dev/null 2>&1; then
    pass "2.5" "CRD carries categories + shortName, 'kubectl get henia' resolves"
  else
    fail "2.5" "CRD carries categories + shortName, 'kubectl get henia' resolves" \
         "markers present but 'kubectl get henia' did not resolve"
  fi
else
  fail "2.5" "CRD carries categories + shortName" "markers missing from $CRD"
fi

if grep -q 'domain: henia.dev' PROJECT \
   && grep -q 'repo: git.tobiko.kondi.net/kondi/henia' PROJECT; then
  pass "2.6" "PROJECT records the domain and the private-host module path"
else
  fail "2.6" "PROJECT records the domain and the private-host module path"
fi

# The subdir-then-move must not have overwritten anything the repo owns. Only
# three files outside the scaffold were touched, and the Dockerfile edit was a
# single added line (make), not a replacement.
# Errors are NOT discarded here. With 2>/dev/null an unreachable commit - a
# shallow clone, rewritten history, the wrong repository - produced empty
# output and this check reported PASS having inspected nothing. Review
# finding F4: a check that cannot run must say so, never pass.
if ! scaffold="$(git show --name-only --format= 2604250 2>&1)"; then
  fail "2.7" "scaffold overwrote nothing the repo owns" \
       "commit 2604250 unreachable: ${scaffold%%$'\n'*}"
elif [[ -z "${scaffold//[[:space:]]/}" ]]; then
  # Exit 0 with no file list - a merge commit, an empty commit, a rewritten
  # tree - means nothing was inspected. Not reachable for 2604250 today, but
  # it is the same hole on the success path.
  fail "2.7" "scaffold overwrote nothing the repo owns" \
       "commit 2604250 listed no files; nothing was inspected"
else
  strays="$(grep -E '^(context|infra|devcontainer|docs|content)/' <<<"$scaffold" \
            | grep -vE '^(context/changes/cluster-substrate/(plan|change)\.md|devcontainer/Dockerfile)$')"
  if [[ -z "$strays" ]]; then
    pass "2.7" "scaffold overwrote nothing under context/ infra/ devcontainer/ docs/ content/"
  else
    fail "2.7" "scaffold overwrote nothing the repo owns" "unexpected: $(echo "$strays" | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------- phase 3 ----
section "Phase 3 — Harbor"

if [[ "$have_cluster" == 1 ]]; then
  notready="$($KUBECTL -n harbor get pods --no-headers 2>/dev/null \
              | awk '{split($2,a,"/"); if (a[1] != a[2] || $3 != "Running") print $1}')"
  if [[ -n "$($KUBECTL -n harbor get pods --no-headers 2>/dev/null)" && -z "$notready" ]]; then
    pass "3.1" "all Harbor pods Ready"
  else
    fail "3.1" "all Harbor pods Ready" "not ready: $(echo "$notready" | tr '\n' ' ')"
  fi
else
  skip "3.1" "all Harbor pods Ready" "no cluster access"
fi

# Unreachable is not unhealthy. Round 2, F7.
if health="$(curl -fsS --max-time 15 "$HARBOR_URL/api/v2.0/health" 2>/dev/null)"; then
  if grep -q '"status":"unhealthy"' <<<"$health"; then
    fail "3.2" "Harbor reports every component healthy" "${health:0:120}"
  else
    pass "3.2" "Harbor reports every component healthy"
  fi
else
  skip "3.2" "Harbor reports every component healthy" "$HARBOR_URL is unreachable"
fi

skip "3.3" "robot account authenticates"  "needs the robot credential (/root/harbor-robot.txt on tachiko)"
skip "3.4" "push and pull by digest"      "needs the robot credential and a container runtime"
skip "3.5" "registries.yaml on the host"  "needs root on tachiko: diff against infra/tachiko/etc/rancher/k3s/registries.yaml"

# Regression guard for 81c527e: Harbor must answer 200 over HTTP, not redirect
# to an HTTPS port that has no TLS and no firewall opening behind it.
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$HARBOR_URL/" 2>/dev/null)" || code=""
if [[ "$code" == "200" ]]; then
  pass "3.6" "Harbor UI answers 200 over HTTP, no ssl-redirect"
elif [[ -z "$code" || "$code" == "000" ]]; then
  skip "3.6" "Harbor UI answers 200 over HTTP, no ssl-redirect" "$HARBOR_URL is unreachable"
else
  fail "3.6" "Harbor UI answers 200 over HTTP, no ssl-redirect" \
       "got HTTP $code — has the chart's ssl-redirect come back?"
fi

# ---------------------------------------------------------------- phase 4 ----
section "Phase 4 — Tekton Pipelines"

if [[ "$have_cluster" == 1 ]]; then
  ok=1
  for d in tekton-pipelines-controller tekton-pipelines-webhook; do
    ready="$($KUBECTL -n tekton-pipelines get deploy "$d" \
             -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
    [[ "${ready:-0}" -ge 1 ]] || ok=0
  done
  [[ "$ok" == 1 ]] && pass "4.1" "controller and webhook Ready" \
                   || fail "4.1" "controller and webhook Ready"

  # Not 'kubectl get crd': the read-only identity has no cluster-scoped read on
  # apiextensions. Discovery answers the same question - are the types served.
  kinds="$($KUBECTL api-resources --api-group=tekton.dev --no-headers 2>/dev/null | awk '{print $NF}')"
  missing=""
  for k in Task Pipeline TaskRun PipelineRun; do
    grep -qx "$k" <<<"$kinds" || missing="$missing $k"
  done
  [[ -z "$missing" ]] && pass "4.2" "Task, Pipeline, TaskRun, PipelineRun CRDs registered" \
                      || fail "4.2" "Tekton CRDs registered" "missing:$missing"

  rel="$($KUBECTL -n tekton-pipelines get deploy tekton-pipelines-controller \
         -o jsonpath='{.metadata.labels.pipeline\.tekton\.dev/release}' 2>/dev/null)"
  if [[ "$rel" == "v1.15.0" ]]; then
    pass "4.3" "deployed release is v1.15.0"
    pass "4.4" "that is the current track, not the LTS line (LTS is v1.6.x)"
  else
    fail "4.3" "deployed release is v1.15.0" "got '${rel:-unknown}'"
    fail "4.4" "current track, not LTS" "release label reads '${rel:-unknown}'"
  fi
else
  # Every criterion gets its own SKIP. Emitting one per phase made the rest
  # vanish from both the table and the "stays unconfirmed" list - silently,
  # which is the one thing this script promises not to do. Review finding F4.
  skip "4.1" "controller and webhook Ready"     "no cluster access"
  skip "4.2" "Tekton CRDs registered"           "no cluster access"
  skip "4.3" "deployed release is v1.15.0"      "no cluster access"
  skip "4.4" "current track, not LTS"           "no cluster access"
fi

# ---------------------------------------------------------------- phase 5 ----
section "Phase 5 — build pipeline"

if [[ "$have_cluster" == 1 ]]; then
  succeeded="$($KUBECTL -n default get pipelinerun \
               -o jsonpath='{range .items[*]}{.status.conditions[0].reason}{"\n"}{end}' 2>/dev/null \
               | grep -c '^Succeeded$')"
  [[ "${succeeded:-0}" -ge 1 ]] \
    && pass "5.1" "a PipelineRun has completed end to end ($succeeded succeeded)" \
    || fail "5.1" "a PipelineRun has completed end to end"
else
  skip "5.1" "a PipelineRun has completed end to end" "no cluster access"
fi

skip "5.2" "built image present in Harbor" "needs a Harbor credential to list artifacts"

# Parsed, not grepped. The definition contains the words "privileged: true" in a
# comment explaining that the pod does NOT get it - a grep reads that as a hit,
# which is a check that fails on its own documentation.
if python3 -c '
import sys, yaml
def walk(n):
    if isinstance(n, dict):
        if n.get("privileged") is True: return True
        return any(walk(v) for v in n.values())
    if isinstance(n, list): return any(walk(v) for v in n)
    return False
# Every pipeline file, not just the first. devcontainer-verify.yaml gained a
# third Task and was never scanned by this guard. Round 2, F7.
docs = [d for f in sys.argv[1:] for d in yaml.safe_load_all(open(f)) if d]
sys.exit(1 if any(walk(d) for d in docs) else 0)
' deploy/tekton/*.yaml; then
  pass "5.3" "no privileged: true anywhere in the pipeline definition"
else
  fail "5.3" "no privileged: true in the pipeline definition"
fi

skip "5.4" "built image executes in a throwaway pod" "needs write access to the cluster"

# No secret VALUES in the committed pipeline — only Secret names.
# grep's exit codes are three-valued and the difference matters: 1 is "looked,
# found nothing", 2 is "could not look". Collapsing them let an unreadable or
# missing deploy/tekton/ report PASS having scanned nothing. Round 2, F1 sweep.
secret_hits="$(grep -rniE '^\s*(password|token|auth|\.dockerconfigjson):' deploy/tekton/ 2>&1)"
case $? in
  0) fail "5.5" "no secret values in the committed pipeline YAML" "${secret_hits%%$'\n'*}" ;;
  1) pass "5.5" "no secret values in the committed pipeline YAML; credentials arrive as Secret volumes" ;;
  *) fail "5.5" "no secret values in the committed pipeline YAML" \
          "could not scan deploy/tekton/: ${secret_hits%%$'\n'*}" ;;
esac

# ---------------------------------------------------------------- phase 6 ----
section "Phase 6 — operator deployment"

if [[ "$have_cluster" == 1 ]]; then
  avail="$($KUBECTL -n henia-system get deploy henia-controller-manager \
           -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)"
  [[ "$avail" == "True" ]] && pass "6.1" "Deployment reports Available" \
                           || fail "6.1" "Deployment reports Available" "got '${avail:-none}'"

  $KUBECTL explain herd >/dev/null 2>&1 \
    && pass "6.2" "Herd CRD registered, 'kubectl explain herd' resolves" \
    || fail "6.2" "'kubectl explain herd' resolves"

  if $KUBECTL -n henia-system logs deploy/henia-controller-manager --tail=200 2>/dev/null \
     | grep -q 'reconciling Herd'; then
    pass "6.3" "controller has logged a reconcile"
  else
    fail "6.3" "controller has logged a reconcile" \
         "no 'reconciling Herd' in the last 200 lines — the pod may have restarted since"
  fi

  skip "6.4" "deleted pod is replaced" "destructive; run 'kubectl -n henia-system delete pod -l control-plane=controller-manager' by hand"

  res="$($KUBECTL -n henia-system get deploy henia-controller-manager \
         -o jsonpath='{.spec.template.spec.containers[0].resources}' 2>/dev/null)"
  if grep -q 'limits' <<<"$res" && grep -q 'requests' <<<"$res"; then
    pass "6.5" "operator has resource requests and limits"
  else
    fail "6.5" "operator has resource requests and limits" "got '${res:-none}'"
  fi
else
  skip "6.1" "Deployment reports Available"          "no cluster access"
  skip "6.2" "'kubectl explain herd' resolves"       "no cluster access"
  skip "6.3" "controller has logged a reconcile"     "no cluster access"
  skip "6.4" "deleted pod is replaced"               "no cluster access"
  skip "6.5" "resource requests and limits"          "no cluster access"
fi

skip "6.6" "supervision convention still accurate" "a judgement: read context/foundation/supervision-convention.md"

# ---------------------------------------------------------------- phase 7 ----
section "Phase 7 — telemetry"

prom() { curl -fsS --max-time 20 -u "$PROM_AUTH" --get "$PROM_URL$1" "${@:2}"; }

if [[ -z "$PROM_AUTH" ]]; then
  skip "7.1" "operator is an up target"        "set PROM_AUTH=user:password"
  skip "7.2" "reconcile_total is non-empty"    "set PROM_AUTH=user:password"
  skip "7.3" "Go runtime metrics present"      "set PROM_AUTH=user:password"
  skip "7.4" "exactly one target, and it is up" "set PROM_AUTH=user:password"
else
  targets="$(prom /api/v1/targets --data-urlencode 'state=active' 2>/dev/null)"
  # Both halves counted by the same parser. Counting `total` with a grep over
  # raw JSON while counting `up` with a parser meant the two disagreed:
  # Prometheus emits the job label in discoveredLabels as well as labels, so
  # one healthy target could count as two. Review finding F4.
  counts="$(python3 - "$targets" <<'PY' 2>/dev/null
import json,sys
d=json.loads(sys.argv[1])
t=[x for x in d["data"]["activeTargets"] if x["labels"].get("job")=="henia-operator"]
print(len(t), sum(1 for x in t if x["health"]=="up"))
PY
)"
  total="${counts%% *}"; up="${counts##* }"
  if [[ "${up:-0}" -ge 1 ]]; then
    pass "7.1" "operator is an up target in Prometheus"
  else
    fail "7.1" "operator is an up target in Prometheus" "targets found: ${total:-0}, up: ${up:-0}"
  fi

  # 7.4 is the one a green 7.1 cannot see: an extra, permanently-down target
  # standing beside a healthy one. That is exactly how the :8081 health port
  # got scraped over https and stayed broken.
  if [[ "${total:-0}" == "1" && "${up:-0}" == "1" ]]; then
    pass "7.4" "exactly one henia-operator target, and it is up"
  else
    fail "7.4" "exactly one henia-operator target, and it is up" \
         "found ${total:-0} target(s), ${up:-0} up — is the :8081 health port back?"
  fi

  q() { prom /api/v1/query --data-urlencode "query=$1" 2>/dev/null; }
  if grep -q '"result":\[{' <<<"$(q 'controller_runtime_reconcile_total')"; then
    pass "7.2" "controller_runtime_reconcile_total is queryable and non-empty"
  else
    fail "7.2" "controller_runtime_reconcile_total is queryable and non-empty"
  fi
  if grep -q '"result":\[{' <<<"$(q 'go_goroutines{job="henia-operator"}')"; then
    pass "7.3" "Go runtime metrics present for the operator process"
  else
    fail "7.3" "Go runtime metrics present for the operator process"
  fi
fi

# ---------------------------------------------------------------- phase 8 ----
section "Phase 8 — read-back (as the identity this container holds)"

if [[ "$have_cluster" == 1 ]]; then
  $KUBECTL get herds -A >/dev/null 2>&1 \
    && pass "8.1" "identity lists Herd resources across namespaces" \
    || fail "8.1" "identity lists Herd resources across namespaces"

  denied=1
  for v in create delete patch; do
    [[ "$($KUBECTL auth can-i "$v" herds.henia.dev -A 2>/dev/null)" == "no" ]] || denied=0
  done
  [[ "$denied" == 1 ]] && pass "8.2" "create, delete and patch on Herd are all denied" \
                       || fail "8.2" "writes to Herd are denied"

  $KUBECTL -n henia-system get deploy henia-controller-manager >/dev/null 2>&1 \
    && $KUBECTL -n henia-system get pods >/dev/null 2>&1 \
    && pass "8.3" "identity reads the operator Deployment and its pods" \
    || fail "8.3" "identity reads the operator Deployment and its pods"

  [[ "$($KUBECTL auth can-i get secrets -A 2>/dev/null)" == "no" ]] \
    && pass "8.4" "reading Secret contents is still denied" \
    || fail "8.4" "reading Secret contents is still denied"
else
  skip "8.1" "identity lists Herd resources"      "no cluster access"
  skip "8.2" "writes to Herd are denied"          "no cluster access"
  skip "8.3" "identity reads the Deployment"      "no cluster access"
  skip "8.4" "Secret contents still denied"       "no cluster access"
fi

skip "8.5" "F-01's outcome agreed as satisfied" "a judgement, not a query"

# ------------------------------------------------------- drift guards --------
section "Drift guards — repository vs cluster (not plan criteria)"

if [[ "$have_cluster" == 1 ]]; then
  running="$($KUBECTL -n henia-system get deploy henia-controller-manager \
             -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
  tracked="$(kustomize build config/default 2>/dev/null \
             | grep -m1 'image: harbor-core' | awk '{print $2}')"
  if [[ -n "$running" && "$running" == "$tracked" ]]; then
    pass "D1" "config/ renders the image the cluster is running ($running)"
  else
    fail "D1" "config/ renders the image the cluster is running" \
         "cluster '$running' vs repository '$tracked'"
  fi

  live="$($KUBECTL -n monitoring get cm prometheus-server \
          -o jsonpath='{.data.prometheus\.yml}' 2>/dev/null)"
  if grep -q '__meta_kubernetes_endpoint_port_name' <<<"$live"; then
    pass "D2" "the live scrape config keeps only the metrics port"
  else
    fail "D2" "the live scrape config keeps only the metrics port" \
         "the fix in infra/tachiko/.../prometheus.yaml has not been applied on the host"
  fi
else
  skip "D1" "config/ renders the running image"        "no cluster access"
  skip "D2" "live scrape config keeps one port only"   "no cluster access"
fi

# ------------------------------------------------------------- summary -------
printf '\n%s%d passed, %d failed, %d skipped%s\n' "$B" "$PASS" "$FAIL" "$SKIP" "$N"

if (( SKIP )); then
  printf '\n%sSkipped — these stay unconfirmed:%s\n' "$B" "$N"
  for s in "${SKIPPED[@]}"; do printf '  %s\n' "$s"; done
fi

if (( FAIL )); then
  printf '\n%sFailed: %s%s\n' "$R" "${FAILED_IDS[*]}" "$N"
  exit 1
fi
exit 0
