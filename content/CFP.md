Call for Papers (CFP) – English Version
Session Title
Str-AI-tjacket: A Tale of Marrying Agentic AI and Declarative GitOps

Abstract
It all started with a simple idea and a single prompt:

"I want to build a harness for agentic development on Kubernetes using a strict Read-Only RBAC role for kubectl, enforcing all writes declaratively through Git and ArgoCD. How do I stop the AI from 'forgetting' the declarative paradigm and going rogue with imperative fixes?"

As platform engineers and architects, we are told that AI agents will revolutionize operations. But when you put an LLM in front of a live Kubernetes cluster, reality hits hard. Give the agent an inch of imperative power, and it will quickly revert to kubectl edit or kubectl patch to fix a failing deployment, completely breaking the Single Source of Truth.

This talk is a transparent, post-mortem-style journey of building a secure, non-imperative development harness using the minimalist pi.dev engine. Instead of relying on fragile prompt engineering to keep the agent in check, we trapped it in an architectural "straitjacket": a strict Read-Only Kubernetes RBAC profile where the only way out is a Git commit reconciled via ArgoCD.

We will walk you through the technical friction points we hit and how we solved them:

The Server-Side Dry-Run Paradox: How do you let a Read-Only agent validate manifests against admission controllers (like Kyverno or OPA) without granting write permissions? (Spoiler: Welcome to Ephemeral-Driven Development via dynamic scratch-agentic-* namespaces).

The State Lag Dilemma: Bridging the gap between the sequential, fast-paced thinking of an LLM and the asynchronous reconciliation loops of ArgoCD using strict API hook systems.

OWASP Top 10 for CI/CD in the Age of AI: Hardening the harness against prompt injections that attempt cluster privilege escalation.

This is not a marketing pitch for a polished product. It’s an engineer-to-engineer retrospective on the boundaries of Kubernetes security when confronted with cognitive automation. We’ll share our code, our architectural scars, and open the floor to the community with the ultimate question: Knowing these constraints, how would you design the future of AI-driven platform engineering?

