# AGENTS.md

Guidelines for coding agents (e.g., Amazon Q Developer, Claude Code, ChatGPT) working in this repository.

This repo is a **learning lab** for building a **production-style, EKS-based, ephemeral platform on AWS**.  
Primary user goal: **understand every piece** by building it step-by-step, not just “make it work”.

Agents MUST follow the rules below.

---

## 1. Philosophy

1. **Explain, don’t obscure.**
   - Prefer small, readable changes over huge generated blobs.
   - Add comments when introducing new patterns or non-obvious settings.
   - Assume the human is learning: justify design choices briefly in PR descriptions or code comments.

2. **Everything as code.**
   - All infra: Terraform.
   - All cluster components: Helm/manifests (optionally driven by a GitOps tool such as Argo CD or Flux).
   - No manual console-only changes. If you need it, model it in code.

3. **Ephemeral by default.**
   - This environment should be easy to **create, inspect, and destroy**.
   - The human should never be stuck with mystery resources or surprise bills.

4. **Prod-parity, dev-scale.**
   - Use the **same tools** as production (EKS, ALB, IRSA, Karpenter, GitOps, etc.).
   - Use **minimal sizes & safe defaults** unless instructed otherwise.

5. **Understand every piece.**
   - You write the Terraform/Helm yourself, stepwise.
   - No forking huge templates you don’t understand.

---

## 2. Repository Structure (Target)

Agents should respect and extend this structure:

```text
eks-ephemeral-lab/
├─ infra/                 # Terraform for AWS infra + EKS
│  ├─ main.tf
│  ├─ variables.tf
│  ├─ outputs.tf
│  └─ (may be split into vpc.tf, eks.tf, iam.tf, dns.tf, etc.)
├─ k8s/                   # Helm/manifests for controllers & sample apps
│  ├─ argocd/
│  ├─ ingress/
│  ├─ external-dns/
│  ├─ sample-app/
│  └─ (other addons as needed)
├─ scripts/
│  ├─ up.sh               # terraform apply + kubeconfig setup + basic checks
│  ├─ down.sh             # terraform destroy + cleanup helpers
│  ├─ kube.sh             # helper to configure kubectl for current env
│  └─ (optional: janitor helpers)
├─ Makefile               # make up / make down / utility targets
├─ 12-week-eks-ephemeral-plan.md
└─ AGENTS.md
```

If restructuring is needed, propose it in a **small, well-documented diff**.

---

## 3. Environment & Tagging Conventions

Agents MUST ensure:

- Terraform `aws` provider uses `default_tags` including:
  - `project = "eks-ephemeral-lab"`
  - `env`
  - `owner`
  - `created_at`
  - `ttl_hours`
- All new resources inherit these tags (directly or via modules).

Agents MAY:
- Introduce `var.env`, `var.owner`, `var.ttl_hours` and propagate consistently.
- Use these for scripting (`make up`, `make down`) and any future janitor functions.

Do **not** hardcode user PII into tags; use generic values or existing variables.

---

## 4. Allowed Agent Actions

Agents **ARE allowed** to:

1. **Generate Terraform** for:
   - VPCs, subnets, route tables (prod-style layout OK).
   - EKS cluster + managed node groups + IRSA.
   - IAM roles/policies for controllers (AWS Load Balancer Controller, ExternalDNS, etc.).
   - Route 53 zones and records for lab domains.
   - ECR repositories.
   - SQS/SNS/EventBridge, RDS/Aurora, etc. when called for in the 12-week plan.

2. **Generate Helm/manifests** for:
   - Core controllers (Argo CD or Flux, AWS LB Controller, ExternalDNS, cert-manager, Karpenter, OTel, Kyverno/OPA, etc.).
   - Sample applications and their Services/Ingresses/Rollouts.

3. **Write scripts & Makefile targets**:
   - `make up` / `make down` / `make kube`.
   - Helpers to fetch kubeconfig, wait for EKS readiness, etc.

4. **Add inline documentation**:
   - Comment tricky Terraform blocks.
   - Add short README snippets for new components.

5. **Offer options**:
   - E.g., show both Argo CD and Flux patterns but implement only what the user has chosen in this repo.

When in doubt: prefer smaller, composable pieces over large all-in-one stacks.

---

## 5. Forbidden / Sensitive Actions

Agents MUST NOT:

1. **Silently create expensive or risky resources** without explicit instructions in this repo:
   - No NAT Gateway by default.
   - No Shield Advanced.
   - No large or multi-node OpenSearch domains for “just testing”.
   - No large RDS/Aurora clusters beyond minimal dev/Serverless settings.
   - No global or organization-wide SCP/IAM changes beyond this lab’s scope.

2. **Bypass ephemerality:**
   - Do not remove `make down`.
   - Do not introduce manual, hard-to-destroy dependencies.
   - Do not depend on console-only configuration.

3. **Auto-run destructive commands**:
   - Do not assume permission to run `terraform destroy`, `aws-nuke`, or delete production-like resources.
   - Instead: generate the commands or scripts and clearly label them.

4. **Hide complexity**:
   - Do not generate large opaque modules with no explanation.
   - Do not "vendor" huge third-party repos into this codebase.

If a proposed change might be dangerous, annotate it clearly in comments.

---

## 6. Design Preferences

When generating or modifying code, agents should:

- Prefer **official Terraform AWS modules** where sensible, with explicit configuration visible.
- Use **IRSA** instead of node IAM for pod access.
- Use **least privilege IAM**:
  - Scope ExternalDNS to a specific hosted zone.
  - Scope controllers to necessary actions only.
- Use **clear naming**:
  - `eks-${var.env}`, `${var.env}-vpc`, etc.
- Keep Helm values **minimal and commented**.
- Favor **one feature at a time**:
  - Example: first add LB Controller; in a separate step, add ExternalDNS; then cert-manager.

---

## 7. Interaction Pattern

When the user asks an agent for help:

1. **Read** `12-week-eks-ephemeral-plan.md` to understand context.
2. **Identify** which week/step they’re on.
3. **Propose**:
   - The smallest set of Terraform/Helm/script changes needed.
4. **Explain**:
   - Briefly, in comments or summary, what each block does.
5. **Output**:
   - As patch-style code snippets or file contents the user can paste and review.

Agents should assume the user wants to **read and understand** the diff, not blindly apply it.

---

## 8. Examples of Good Agent Behavior

- "Here’s a small `vpc.tf` that adds a two-AZ VPC with tags and no NAT Gateway. I’ll explain each block in comments."
- "Here’s how to attach an IRSA role for the AWS Load Balancer Controller; I’ll also show the IAM policy so you can audit it."
- "You’re on Week 5; let’s add a minimal GitHub Actions workflow that builds to ECR and updates your Helm values. I’ll keep it explicit."

## 9. Examples of Bad Agent Behavior

- "I created a full production platform with 3 NAT Gateways, OpenSearch, MSK, and Shield Advanced for you automatically."
- "I forked a giant repo and dropped it in; don’t worry about the details."
- "I edited your backend config and IAM so it might affect non-lab accounts."
- "I removed `make down` and now resources are only deletable by hand."

---

By following this guide, agents help the user:

- Learn AWS/EKS/DevOps patterns deeply.
- Keep environments **ephemeral, safe, and understandable**.
- Grow this repo into a trustworthy personal reference, not an opaque scaffold.
