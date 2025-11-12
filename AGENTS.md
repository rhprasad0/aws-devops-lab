# AGENTS.md

Guidelines for coding agents (e.g., Amazon Q Developer, Claude Code, ChatGPT) working in this repository.

This repo is a **learning lab** for building a **production-style, EKS-based, ephemeral platform on AWS**.
Primary user goal: **understand every piece** by building it step-by-step, not just "make it work".

**Timeline:** 16-20 weeks, part-time (12 hours/week on weekends)
**Budget:** $250/month maximum
**Learning approach:** Incremental, sustainable, with buffer weeks for consolidation

Agents MUST follow the rules below.

---

## 1. Philosophy

1. **Explain, don't obscure.**
   - Prefer small, readable changes over huge generated blobs.
   - Add comments when introducing new patterns or non-obvious settings.
   - Assume the human is learning: justify design choices briefly in PR descriptions or code comments.
   - **Explain WHY, not just WHAT**: e.g., "We use IRSA here instead of node IAM because it provides pod-level permissions isolation."

2. **Everything as code.**
   - All infra: Terraform.
   - All cluster components: Helm/manifests (optionally driven by a GitOps tool such as Argo CD or Flux).
   - No manual console-only changes. If you need it, model it in code.

3. **Ephemeral by default.**
   - This environment should be easy to **create, inspect, and destroy**.
   - The human should never be stuck with mystery resources or surprise bills.
   - Always include cost estimates and cleanup verification steps.

4. **Prod-parity, dev-scale.**
   - Use the **same tools** as production (EKS, ALB, IRSA, Karpenter, GitOps, etc.).
   - Use **minimal sizes & safe defaults** unless instructed otherwise.
   - **Cost-awareness is paramount**: default to smallest instance types, shortest retention periods, and ephemeral storage.

5. **Understand every piece.**
   - You write the Terraform/Helm yourself, stepwise.
   - No forking huge templates you don't understand.

6. **Sustainable learning pace.**
   - This is a marathon, not a sprint. The user is learning part-time over 16-20 weeks.
   - Respect buffer weeks for consolidation and catch-up.
   - Do not rush ahead or skip foundational steps.
   - Better to deeply understand 80% than superficially know 100%.

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
│  ├─ cost-check.sh       # query AWS Cost Explorer by tags
│  └─ (optional: janitor helpers)
├─ Makefile               # make up / make down / utility targets
├─ .cost-budget           # Track actual spending vs budget
├─ 16-20-WEEK-PLAN.md     # The detailed learning plan
└─ AGENTS.md              # This file
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
   - SQS/SNS/EventBridge, RDS/Aurora, etc. when called for in the 16-20 week plan.
   - **Always include cost estimates** for any new infrastructure in comments or output.

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

## 5. Cost Awareness (Budget: $250/month)

Agents MUST:

1. **Estimate costs before suggesting resources:**
   - EKS control plane: $0.10/hour
   - t3.small node: ~$0.02/hour
   - ALB: ~$0.0225/hour + LCU charges
   - NAT Gateway: $0.045/hour + data transfer (AVOID unless necessary)
   - Aurora Serverless v2: ~$0.12/ACU-hour (use 0.5-1 ACU for lab)
   - RDS t3.micro: ~$0.017/hour (cheaper alternative to Aurora)

2. **Always suggest smallest viable sizes:**
   - Nodes: t3.small, t4g.small, t3.medium (not t3.large+)
   - RDS: t3.micro, t4g.micro (Single-AZ for lab)
   - EBS: 20GB gp3 (not large volumes)
   - Retention: hours/days, not weeks/months

3. **Warn about persistent costs:**
   - NAT Gateways ($32/month each)
   - ALBs left running ($16/month each)
   - EBS volumes not deleted with instances
   - CloudWatch Logs with long retention

4. **Include cleanup verification:**
   - After `make down`, list steps to verify all resources are deleted
   - Suggest scripts to check for leaked resources by tags

---

## 6. Forbidden / Sensitive Actions

Agents MUST NOT:

1. **Silently create expensive or risky resources:**
   - **No NAT Gateway by default** (saves $32/month per AZ).
   - No Shield Advanced ($3000/month).
   - No large or multi-node OpenSearch domains for "just testing".
   - No large RDS/Aurora clusters beyond minimal dev/Serverless settings.
   - No global or organization-wide SCP/IAM changes beyond this lab's scope.
   - **Hard limit: No resource that costs >$5/day** without explicit approval and cost justification.

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

## 7. Design Preferences

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

## 8. Interaction Pattern

When the user asks an agent for help:

1. **Read** `README.md` to understand context and timeline.

2. **Identify** which week/step they're on:
   - If unclear, ask: "Which week are you working on?"
   - Check if they've completed prerequisites (e.g., Week 0 setup before Week 1)
   - Respect the learning sequence; don't suggest Week 10 tools for Week 2 problems

3. **Assess scope and cost:**
   - What's the time estimate for this task?
   - What's the cost impact? (e.g., "This adds ~$2/session for ALB")
   - Is this appropriate for their current week?

4. **Propose**:
   - The **smallest set** of Terraform/Helm/script changes needed
   - One component at a time (e.g., "First add the IAM role, then we'll add the controller")
   - Include verification steps

5. **Explain**:
   - WHY this approach (not just WHAT code)
   - What could go wrong and how to debug
   - Cost implications and cleanup steps
   - In comments or summary, what each block does

6. **Output**:
   - As patch-style code snippets or file contents the user can paste and review
   - Include testing commands
   - Include cleanup verification

7. **Follow up:**
   - Suggest next steps aligned with their current week
   - Remind about `make down` if resources were created
   - Suggest buffer week activities if they're moving too fast

**Agents should assume the user wants to READ and UNDERSTAND the diff, not blindly apply it.**

**Special case - Buffer weeks:**
If it's a buffer week (Week 7 or 13), suggest:
- Refactoring and code cleanup
- Documentation improvements
- Cost analysis
- Testing and experimentation
- Research for upcoming weeks
- Catching up if behind
- DO NOT push ahead to next functional week

---

## 9. Examples of Good Agent Behavior

**Example 1 - Week 1 VPC:**
> "Here's a small `vpc.tf` that adds a two-AZ VPC with tags and **no NAT Gateway** (saves $64/month). I'll explain each block in comments. The VPC will cost ~$0.50 per 6-hour session."

**Example 2 - Week 4 Load Balancer:**
> "You're on Week 4, let's add the AWS Load Balancer Controller. First, I'll create the IAM policy (here's the JSON so you can audit it). Then we'll install the Helm chart with minimal replicas. This adds ~$2.50/session for the ALB. Make sure to run `make down` after testing to delete the ALB."

**Example 3 - Week 7 Buffer:**
> "I see you've completed Week 6 ahead of schedule. Since Week 7 is a buffer week, I suggest: (1) Split your monolithic `main.tf` into `vpc.tf`, `eks.tf`, `iam.tf` for better organization, (2) Run `scripts/cost-check.sh` to review spending, (3) Update your README with what you've learned. Want help with any of these?"

**Example 4 - Cost awareness:**
> "Before we add Aurora Serverless v2, note that this will increase your session cost from $3 to $10-15. The plan schedules this for Week 15 when you're more comfortable with cost management. For Week 9, would you like to prototype with a simpler pattern first?"

**Example 5 - Prerequisites check:**
> "I see you want to add ExternalDNS (Week 5), but it looks like you haven't completed Week 4 (Load Balancer Controller) yet. The LB Controller is a prerequisite because you need Ingress resources for ExternalDNS to watch. Want to tackle Week 4 first?"

## 10. Examples of Bad Agent Behavior

**Bad Example 1 - Cost explosion:**
> "I created a full production platform with 3 NAT Gateways, multi-AZ OpenSearch, MSK cluster, and Shield Advanced. (Cost: ~$500/month - over budget!)"

**Bad Example 2 - Complexity dump:**
> "I forked a 5000-line Terraform monorepo and dropped it in; don't worry about the details. Just run it."

**Bad Example 3 - Dangerous changes:**
> "I edited your backend config and IAM roles. This might affect other AWS resources in your account, but it should be fine."

**Bad Example 4 - Breaks ephemerality:**
> "I removed `make down` and added stateful resources that require manual cleanup. You'll need to go to the console to delete these."

**Bad Example 5 - Skips learning steps:**
> "You're on Week 2, but I added observability, CI/CD, security policies, and multi-region DR all at once. Here are 2000 lines of code."

**Bad Example 6 - No cost estimate:**
> "I added these resources [long list]. Run terraform apply. (No mention of cost impact or cleanup steps.)"

**Bad Example 7 - Rushing past buffer weeks:**
> "It's Week 7 (buffer week) but let's skip ahead to Week 10 observability since you're doing well."

---

## 11. Week 0 is MANDATORY

**Before any infrastructure code is written**, agents must ensure Week 0 is complete:

1. ✅ AWS Budget created ($250/month with alerts at 50%, 80%, 100%)
2. ✅ Billing email alerts enabled
3. ✅ MFA enabled on root account
4. ✅ IAM user created with appropriate lab permissions
5. ✅ S3 bucket for Terraform state (with versioning)
6. ✅ DynamoDB table for state locking
7. ✅ Cost allocation tags activated in AWS console

**If a user asks for help with Week 1+ without mentioning Week 0:**
- Ask: "Have you completed Week 0 (AWS account setup, billing alerts, Terraform state backend)?"
- If no: "Let's do Week 0 first. It takes 4-6 hours but prevents surprise bills and state conflicts."
- If yes: Proceed with their request

**Why this matters:**
- Without billing alerts, the user could exceed budget unknowingly
- Without remote state, collaboration and recovery are impossible
- Without proper IAM, security is compromised
- Week 0 is the foundation; skipping it creates technical debt

---

## 12. Success Metrics for Agents

Good agents help users achieve:

✅ **Deep understanding** - User can explain every component from memory
✅ **Confidence** - User can debug issues independently
✅ **Cost control** - User stays within $250/month budget
✅ **Clean habits** - User always runs `make down`, checks for leaked resources
✅ **Production readiness** - Skills transfer directly to real-world AWS/K8s work
✅ **Sustainable pace** - User completes 16-20 weeks without burnout
✅ **Documentation** - Repo becomes personal reference with clear README, diagrams, runbooks

---

By following this guide, agents help the user:

- Learn AWS/EKS/DevOps patterns **deeply and sustainably**.
- Keep environments **ephemeral, safe, cost-controlled, and understandable**.
- Build skills at a **realistic part-time pace** without burnout.
- Grow this repo into a **trustworthy personal reference**, not an opaque scaffold.
- Develop **production-ready expertise** that transfers directly to professional work.

**Remember:** This is a 16-20 week learning journey, not a sprint. Respect the timeline, explain deeply, and prioritize understanding over completion speed.

## 13. Tooling Rules — Amazon Q + Context7 (Required)

### Intent
Keep Terraform **current and correct** by consulting Context7 before generating or modifying code.

### Required Workflow (enforced)
1) **Context7 preflight (mandatory)**
   - Query Context7 for:
     - Provider major/minor version(s) in use
     - Exact schema for each resource/data source (required/optional args, nested blocks)
     - Deprecations/renames since prior majors (e.g., v5→v6)
   - If Context7 returns anything that differs from cached patterns, **prefer Context7**.

2) **Plan the change**
   - Propose the smallest diff aligned to our repo layout (see §2 Repository Structure).
   - Include a 2–4 bullet “Changes vs older pattern” note.

3) **Generate output**
   - Produce minimal, runnable Terraform targeting **`infra/*.tf` only** (no recursion).
   - Add inline comments explaining non-obvious settings (see §1 Philosophy).
   - Include cost notes per §5 (control plane, nodes, ALB, NAT, etc.).

4) **Verify & clean up**
   - Include quick verification commands.
   - Remind about `make down` and leaked-resource checks by tags.

### Guardrails
- Do **not** read or cite caches under `.terraform/` or any hidden directories.
- Stay within the **learning week** flow (see §8 and §11). Ask which week if unclear.
- Keep IAM least-privilege and IRSA-first (see §7).

### Output Format (exact)
- **Header bullets**:
  - Provider/resource versions (from Context7)
  - Key diffs vs older patterns
  - Cost impact (very short)
- **Code block**: final Terraform
- **Post-code**: verification steps + cleanup reminder

### Quick Chat Snippets (copy/paste)
- “Use Context7 to fetch the schema for `aws_iam_role` (current provider). Show diffs vs v5, then write the minimal Terraform for `infra/iam.tf`.”
- “Validate `aws_lb_listener` args with Context7, then generate code. List any deprecated arguments we should avoid.”
- “Before writing, confirm provider constraints for this repo and suggest updates to `versions.tf` if needed.”
