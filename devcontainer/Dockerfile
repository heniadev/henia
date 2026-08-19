FROM node:22-slim

# System deps the agent legitimately needs inside the isolated workspace.
# iptables sets up the network firewall (entrypoint.sh); gosu drops root
# privileges cleanly after that setup, before anything touches the repo.
# jq: needed locally so `.pre-commit-config.yaml`'s
# `finalize-pre-commit-status-test` hook (deploy/tekton/ci-checks/
# finalize-pre-commit-status.test.sh) can actually run at commit time --
# that test asserts against real jq-produced JSON, matching the ci-checks
# image (deploy/tekton/ci-checks/Dockerfile) it also runs under in CI, so
# local and CI stay consistent.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    vim \
    iptables \
    gosu \
    python3 \
    python3-pip \
    jq \
    make \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# pre-commit: the git-hook framework this project enforces on every commit in
# every worktree (see devcontainer/README.md § pre-commit + .pre-commit-config.yaml).
# Baked at build time because the runtime user is non-root and sudo-less, so it
# can never pip-install later. Version pinned (not a moving target; pip resolves
# the hash from PyPI — not --require-hashes-verified like the droast/kubeconform
# binary blocks below, but pinned). --break-system-packages is acceptable here —
# this is a single-purpose, disposable image, not a shared host, and pre-commit
# is the only global pip package.
RUN python3 -m pip install --break-system-packages --no-cache-dir pre-commit==4.6.1

# kubectl: read-only cluster access (see devcontainer/k8s/). Deploys happen
# via git + Argo CD watching the repo, never via kubectl apply from here.
RUN curl -fsSLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# argocd CLI: inspect/observe Argo CD Application sync state (read-only
# identity — no argocd login credentials are baked in or provided here).
RUN curl -fsSLo /usr/local/bin/argocd \
    "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-$(dpkg --print-architecture)" \
    && chmod +x /usr/local/bin/argocd

# sops: decrypt/inspect sealed values in git-committed manifests the Argo CD
# GitOps flow relies on. No key material is baked into the image — a key
# would need to be provided the same way kubeconfig.yaml/creds.yaml are.
RUN SOPS_VERSION="$(curl -fsSL https://api.github.com/repos/getsops/sops/releases/latest \
      | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)" \
    && curl -fsSLo /usr/local/bin/sops \
    "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.$(dpkg --print-architecture)" \
    && chmod +x /usr/local/bin/sops

# tea: Gitea's CLI, for working with issues/PRs/releases on the git host
# directly (see Git credentials — same dedicated account, not baked in here).
RUN TEA_TAG="$(curl -fsSL https://gitea.com/api/v1/repos/gitea/tea/releases/latest \
      | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)" \
    && TEA_VERSION="${TEA_TAG#v}" \
    && curl -fsSLo /usr/local/bin/tea \
    "https://gitea.com/gitea/tea/releases/download/${TEA_TAG}/tea-${TEA_VERSION}-linux-$(dpkg --print-architecture)" \
    && chmod +x /usr/local/bin/tea

# droast (dockerfile-roast): lints/critiques Dockerfiles, including this one
# and the app's own. Pinned version + checksum verification (unlike the
# "latest" pattern above) — small, single-maintainer project, so trust it
# deliberately per-version rather than a moving target.
RUN DROAST_VERSION="1.4.0" \
    && case "$(dpkg --print-architecture)" in \
         amd64) DROAST_ARCH="x86_64" ;; \
         arm64) DROAST_ARCH="arm64" ;; \
         *) echo "unsupported architecture for droast: $(dpkg --print-architecture)" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /usr/local/bin/droast \
    "https://github.com/immanuwell/dockerfile-roast/releases/download/${DROAST_VERSION}/droast-linux-${DROAST_ARCH}" \
    && DROAST_HASH="$(curl -fsSL "https://github.com/immanuwell/dockerfile-roast/releases/download/${DROAST_VERSION}/sha256sums.txt" \
         | grep "droast-linux-${DROAST_ARCH}\$" | awk '{print $1}')" \
    && echo "${DROAST_HASH}  /usr/local/bin/droast" | sha256sum -c - \
    && chmod +x /usr/local/bin/droast

# kubeconform: offline Kubernetes manifest schema validation, invoked as a
# local pre-commit hook (scoped to deploy/ manifests; CRD-tolerant via
# -ignore-missing-schemas for Tekton/Argo CRDs). Pinned version + hardcoded
# per-arch sha256 (droast-style). Baked as a binary because upstream ships no
# pre-commit hook manifest and the runtime user is sudo-less — a repo:local
# system hook calling this binary is the correct integration (no Go/DinD).
RUN KUBECONFORM_VERSION="v0.6.7" \
    && case "$(dpkg --print-architecture)" in \
         amd64) KC_ARCH="amd64"; KC_SHA="95f14e87aa28c09d5941f11bd024c1d02fdc0303ccaa23f61cef67bc92619d73" ;; \
         arm64) KC_ARCH="arm64"; KC_SHA="dc82f79bb03c5479b1ae5fd4af221e4b5a3111f62bf01a2795d9c5c20fa96644" ;; \
         *) echo "unsupported architecture for kubeconform: $(dpkg --print-architecture)" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/kubeconform.tar.gz \
    "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-${KC_ARCH}.tar.gz" \
    && echo "${KC_SHA}  /tmp/kubeconform.tar.gz" > /tmp/kubeconform.sha256 \
    && sha256sum -c /tmp/kubeconform.sha256 \
    && tar -xzf /tmp/kubeconform.tar.gz -C /usr/local/bin kubeconform \
    && rm /tmp/kubeconform.tar.gz /tmp/kubeconform.sha256 \
    && chmod +x /usr/local/bin/kubeconform

# kustomize: standalone CLI (kubectl's built-in `kubectl kustomize` lacks
# exec-plugin/Helm-chart-inflator support, which KSOPS and the SeaweedFS
# Helm-chart kustomization under deploy/ both need). Pinned version +
# hardcoded per-arch sha256, cross-checked against upstream's checksums.txt
# (droast/kubeconform-style — deliberate per-version trust, not "latest").
RUN KUSTOMIZE_VERSION="v5.8.1" \
    && case "$(dpkg --print-architecture)" in \
         amd64) KZ_ARCH="amd64"; KZ_SHA="029a7f0f4e1932c52a0476cf02a0fd855c0bb85694b82c338fc648dcb53a819d" ;; \
         arm64) KZ_ARCH="arm64"; KZ_SHA="0953ea3e476f66d6ddfcd911d750f5167b9365aa9491b2326398e289fef2c142" ;; \
         *) echo "unsupported architecture for kustomize: $(dpkg --print-architecture)" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/kustomize.tar.gz \
    "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${KZ_ARCH}.tar.gz" \
    && echo "${KZ_SHA}  /tmp/kustomize.tar.gz" > /tmp/kustomize.sha256 \
    && sha256sum -c /tmp/kustomize.sha256 \
    && tar -xzf /tmp/kustomize.tar.gz -C /usr/local/bin kustomize \
    && rm /tmp/kustomize.tar.gz /tmp/kustomize.sha256 \
    && chmod +x /usr/local/bin/kustomize

# helm: standalone CLI, needed to `helm template` the SeaweedFS chart under
# deploy/storage/ (Kustomize's helmCharts: generator shells out to this
# binary). Pinned to the latest Helm v3.x line deliberately, not the newer
# v4 major that shipped upstream — the chart ecosystem (SeaweedFS included)
# still targets the Helm v3 chart API. Pinned version + hardcoded per-arch
# sha256 from Helm's own published checksum files.
RUN HELM_VERSION="v3.21.3" \
    && case "$(dpkg --print-architecture)" in \
         amd64) HELM_ARCH="amd64"; HELM_SHA="15e041a93a590dce8100f39385cd98c84a765c9e36aeeb9e2dc6ff9e4769e2e0" ;; \
         arm64) HELM_ARCH="arm64"; HELM_SHA="67f58155079ff9ffab98ba5c88daff0ed9b542f3a4732f5dd426dde7dd0f5244" ;; \
         *) echo "unsupported architecture for helm: $(dpkg --print-architecture)" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/helm.tar.gz \
    "https://get.helm.sh/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz" \
    && echo "${HELM_SHA}  /tmp/helm.tar.gz" > /tmp/helm.sha256 \
    && sha256sum -c /tmp/helm.sha256 \
    && tar -xzf /tmp/helm.tar.gz -C /tmp "linux-${HELM_ARCH}/helm" \
    && mv "/tmp/linux-${HELM_ARCH}/helm" /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz /tmp/helm.sha256 "/tmp/linux-${HELM_ARCH}" \
    && chmod +x /usr/local/bin/helm

# age: keypair generation/encryption backend for SOPS (deploy/.sops.yaml
# uses `age:` recipients, not PGP) — needed to generate/rotate the real key
# per deploy/argocd/cluster-prereqs/README.md, and to validate the
# SOPS<->KSOPS round-trip locally before trusting a live cluster sync.
# Pinned version + hardcoded per-arch sha256 (computed directly from the
# downloaded release asset — upstream doesn't publish a checksums.txt).
RUN AGE_VERSION="v1.3.1" \
    && case "$(dpkg --print-architecture)" in \
         amd64) AGE_ARCH="amd64"; AGE_SHA="bdc69c09cbdd6cf8b1f333d372a1f58247b3a33146406333e30c0f26e8f51377" ;; \
         arm64) AGE_ARCH="arm64"; AGE_SHA="c6878a324421b69e3e20b00ba17c04bc5c6dab0030cfe55bf8f68fa8d9e9093a" ;; \
         *) echo "unsupported architecture for age: $(dpkg --print-architecture)" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/age.tar.gz \
    "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-${AGE_ARCH}.tar.gz" \
    && echo "${AGE_SHA}  /tmp/age.tar.gz" > /tmp/age.sha256 \
    && sha256sum -c /tmp/age.sha256 \
    && tar -xzf /tmp/age.tar.gz -C /tmp age/age age/age-keygen \
    && mv /tmp/age/age /tmp/age/age-keygen /usr/local/bin/ \
    && rm -rf /tmp/age.tar.gz /tmp/age.sha256 /tmp/age \
    && chmod +x /usr/local/bin/age /usr/local/bin/age-keygen

# ksops: Kustomize exec plugin that decrypts SOPS-encrypted resources at
# `kustomize build` time (see
# deploy/argocd/cluster-prereqs/repo-server-ksops-patch.yaml for the
# matching in-cluster wiring). Installed as a plain binary AND placed at the
# exec-plugin path kustomize's --enable-exec looks up.
#
# Deliberately NOT under $HOME/.config: /home/agent is a named volume that
# shadows anything baked into the image at that path at runtime (see the
# PRE_COMMIT_HOME comment below — same constraint), so a plugin placed there
# at build time would silently vanish. XDG_CONFIG_HOME is redirected to a
# build-time-baked, non-volume path instead. Pinned version + hardcoded
# per-arch sha256 from upstream's checksums.txt.
#
# CAVEAT: this ENV is process-wide, so it redirects *every* XDG-respecting
# tool's config here — not just kustomize/ksops. In particular `tea` (Gitea
# CLI), which user-entrypoint.sh runs on every startup, then writes its config
# under ${XDG_CONFIG_HOME}/tea/ as the unprivileged runtime user. The trailing
# `chmod 0777 "${XDG_CONFIG_HOME}"` in the RUN below makes only the top-level
# dir world-writable so those tools can create their own subdirs; without it
# the root-owned 0755 dir makes tea fail with "unable to get or create config
# file" and aborts container startup. The ksops plugin subtree stays a+rX.
ENV XDG_CONFIG_HOME=/opt/xdg-config
RUN KSOPS_VERSION="v4.5.1" \
    && case "$(dpkg --print-architecture)" in \
         amd64) KS_ARCH="x86_64"; KS_SHA="9641e03a301bf2fc4b98d0e837a0351e1ca443ecd7a68b25e6af2149fbb2ef30" ;; \
         arm64) KS_ARCH="arm64"; KS_SHA="c7bb562cc2d580a1decc6c77a35e4d35575fb01ca003425726004ecd13dc1cb5" ;; \
         *) echo "unsupported architecture for ksops: $(dpkg --print-architecture)" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/ksops.tar.gz \
    "https://github.com/viaduct-ai/kustomize-sops/releases/download/${KSOPS_VERSION}/ksops_${KSOPS_VERSION#v}_Linux_${KS_ARCH}.tar.gz" \
    && echo "${KS_SHA}  /tmp/ksops.tar.gz" > /tmp/ksops.sha256 \
    && sha256sum -c /tmp/ksops.sha256 \
    && tar -xzf /tmp/ksops.tar.gz -C /tmp ksops \
    && mv /tmp/ksops /usr/local/bin/ksops \
    && chmod +x /usr/local/bin/ksops \
    && mkdir -p "${XDG_CONFIG_HOME}/kustomize/plugin/viaduct.ai/v1/ksops" \
    && cp /usr/local/bin/ksops "${XDG_CONFIG_HOME}/kustomize/plugin/viaduct.ai/v1/ksops/ksops" \
    && chmod -R a+rX "${XDG_CONFIG_HOME}" \
    && chmod 0777 "${XDG_CONFIG_HOME}" \
    && rm -f /tmp/ksops.tar.gz /tmp/ksops.sha256

# Go: the toolchain for Henia's own operator (context/changes/cluster-substrate).
# This image was deliberately toolchain-free — a control-plane container, not a
# build one — so this is a considered change, not a convenience: `kubebuilder
# create api` is re-run every time the API evolves, and doing that through a
# throwaway pod on the cluster would make routine work a ceremony.
#
# Pinned to the 1.26 line because kubebuilder v4.15.0 targets Go 1.26 and
# Kubernetes 1.36 (context/foundation/tech-stack.md). Version + per-arch sha256
# from go.dev's release index, droast/kubeconform-style.
RUN GO_VERSION="1.26.7" \
    && case "$(dpkg --print-architecture)" in \
         amd64) GO_ARCH="amd64"; GO_SHA="ffb5f8de10c62550dfddab66b36b57030721e0a44a3218e9e1181d7b59f121ca" ;; \
         arm64) GO_ARCH="arm64"; GO_SHA="5a4ec883379d51ee9ce1040d5e87f8d35e20387574dd8c947feb01eabc3c1b37" ;; \
         *) echo "unsupported architecture for go: $(dpkg --print-architecture)" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/go.tar.gz \
    "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
    && echo "${GO_SHA}  /tmp/go.tar.gz" > /tmp/go.sha256 \
    && sha256sum -c /tmp/go.sha256 \
    && tar -xzf /tmp/go.tar.gz -C /usr/local \
    && rm /tmp/go.tar.gz /tmp/go.sha256

# GOPATH/GOCACHE live under /home/agent, the persisted named volume — never in
# /workspace, or module downloads and build artefacts would land in the repo and
# show up as untracked files in every `git status`. Same volume-shadowing
# constraint as PRE_COMMIT_HOME below: these cannot be pre-warmed at build time.
ENV PATH="/usr/local/go/bin:/home/agent/go/bin:${PATH}"
ENV GOPATH=/home/agent/go
ENV GOCACHE=/home/agent/.cache/go-build

# kubebuilder: scaffolds and regenerates the operator project (PROJECT, api/,
# internal/controller/, config/). Pinned to v4.15.0 — the version the stack
# hand-off records, targeting Kubernetes 1.36 with controller-runtime v0.24.1.
# Version + per-arch sha256 from upstream's published checksums.txt.
RUN KUBEBUILDER_VERSION="v4.15.0" \
    && case "$(dpkg --print-architecture)" in \
         amd64) KB_ARCH="amd64"; KB_SHA="9632ba818c35e10d9664f19090972ee5d667bdffbf4b83c34e8374c5e846afa2" ;; \
         arm64) KB_ARCH="arm64"; KB_SHA="bd99723fc106502f64a3541b9c5b7079bc68961a76df4f465893e311b594d295" ;; \
         *) echo "unsupported architecture for kubebuilder: $(dpkg --print-architecture)" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/kubebuilder \
    "https://github.com/kubernetes-sigs/kubebuilder/releases/download/${KUBEBUILDER_VERSION}/kubebuilder_linux_${KB_ARCH}" \
    && echo "${KB_SHA}  /tmp/kubebuilder" > /tmp/kubebuilder.sha256 \
    && sha256sum -c /tmp/kubebuilder.sha256 \
    && mv /tmp/kubebuilder /usr/local/bin/kubebuilder \
    && rm -f /tmp/kubebuilder.sha256 \
    && chmod +x /usr/local/bin/kubebuilder

# Playwright/Chromium runtime libs: the devcontainer runs as a non-root,
# sudo-less user after entrypoint.sh drops privileges, so `npx playwright
# install-deps` (which needs apt/root) can never run at container-runtime —
# these must be baked in at image-build time instead, while we're still root.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libnspr4 \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libdbus-1-3 \
    libcups2 \
    libxcb1 \
    libxkbcommon0 \
    libasound2 \
    libgbm1 \
    libx11-6 \
    libxext6 \
    libcairo2 \
    libpango-1.0-0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libatspi2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# The container starts as root (entrypoint.sh needs NET_ADMIN/NET_RAW to set
# up the firewall) and drops to `--user`-equivalent via gosu before running
# anything from the repo. This directory must be writable by whatever
# arbitrary target UID gosu drops into at runtime, not just a UID baked in
# at build time.
RUN mkdir -p /home/agent /home/agent/.kube && chmod 0777 /home/agent /home/agent/.kube
ENV HOME=/home/agent
# pre-commit caches fetched hook repos here. Kept under the persisted
# /home/agent named volume so the cache survives container restarts — only a
# brand-new volume pays the one-time first-commit fetch (build-time pre-warming
# is impossible: the volume mount shadows anything baked under /home/agent).
ENV PRE_COMMIT_HOME=/home/agent/.cache/pre-commit
# This ariable tells executed tools that they should emit sparse output
# - saving context space in AI Agents.
ENV AI_AGENT=1

COPY entrypoint.sh /entrypoint.sh
COPY user-entrypoint.sh /usr/local/bin/user-entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/user-entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
