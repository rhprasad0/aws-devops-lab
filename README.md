# 12-Week Production-Style AWS/EKS DevOps Learning Plan (Ephemeral Lab)

You: **Data engineer with GCP experience, moving into AWS/DevOps**, comfortable with containers, some Kubernetes & GitOps.  
Goal: Build a **production-grade, EKS-centric platform** *yourself* (no magic repos), using **ephemeral clusters** so you can confidently create, operate, and destroy real-world infra.

---

## Core Principles

1. **Everything as Code**  
   - Use Terraform for AWS infra (VPC, EKS, IAM, etc).  
   - Use Helm & GitOps (Argo CD or Flux) for Kubernetes apps.

2. **Ephemeral by Default**  
   - One command to bring up the full stack.  
   - One command to tear it all down.  
   - No manual console changes; if you click it, you codify it.

3. **Tags & TTL Everywhere**  
   - Tag all resources with: `project`, `env`, `owner`, `created_at`, `ttl_hours`.  
   - Optional: add a “janitor” Lambda later that deletes expired resources.

4. **Prod-Parity, Not Prod-Scale**  
   - Use the **same tools and patterns** as production (EKS, ALB, IRSA, Karpenter, GitOps, etc.).  
   - Keep node sizes, traffic, and retention small.

5. **Understand Every Piece**  
   - You write the Terraform/Helm yourself, stepwise.  
   - No forking huge templates you don’t understand.

---

## Repo Layout (You Build This Gradually)

In your own repo (e.g. `eks-ephemeral-lab`):

```text
eks-ephemeral-lab/
├─ infra/                 # Terraform for AWS infra + EKS
│  ├─ main.tf
│  ├─ variables.tf
│  ├─ outputs.tf
│  └─ (later: vpc.tf, eks.tf, iam.tf split if you like)
├─ k8s/                   # Helm charts / manifests for controllers & apps
│  ├─ ingress/
│  ├─ external-dns/
│  ├─ argocd/
│  ├─ sample-app/
│  └─ (etc)
├─ scripts/
│  ├─ up.sh
│  ├─ down.sh
│  ├─ kube.sh
│  └─ (optional: ttl-janitor.sh, force-clean-lbs.sh)
├─ Makefile
└─ README.md
```

You start minimal and add components as each week’s tasks demand.

---

## Ephemeral Cluster Commands

**Makefile (core idea):**

```makefile
AWS_REGION ?= us-east-1
ENV        ?= dev-ephemeral
OWNER      ?= your-name
TTL_HOURS  ?= 12

up:
	cd infra && terraform init -upgrade && terraform apply -auto-approve \
	  -var="region=$(AWS_REGION)" \
	  -var="env=$(ENV)" \
	  -var="owner=$(OWNER)" \
	  -var="ttl_hours=$(TTL_HOURS)"
	aws eks update-kubeconfig --name $(ENV)-eks --region $(AWS_REGION)
	kubectl get nodes

down:
	cd infra && terraform destroy -auto-approve
```

Usage:
- `make up` → full lab up.
- `make down` → everything destroyed.

You’ll refine this as you add components.

---

## Week 0 – Setup & Baseline

**Goals**
- Local tools installed.
- Remote state & tagging in place.
- First successful apply/destroy cycle.

**Tasks**
1. Install: `awscli`, `terraform`, `kubectl`, `helm`, `git`.
2. Create (manually, once): S3 bucket for state, DynamoDB table for locks.
3. In `infra/main.tf`:
   - Configure Terraform backend (S3 + DynamoDB).
   - Configure AWS provider with `default_tags` (project/env/owner/ttl_hours).
4. Run:
   - `terraform init`
   - `terraform apply` (with just provider and outputs)
   - `terraform destroy`

Understand: how remote state works, why tags matter, and that destroy is clean.

---

## Week 1 – VPC + First Ephemeral EKS Cluster

**Goals**
- Minimal VPC.
- Working EKS cluster with one small node group.
- Ephemeral lifecycle via `make up/down`.

**Infra**
- VPC: `/16` with 2 public + 2 private subnets.
- No NAT Gateway (yet) to keep it simple.
- EKS cluster:
  - Managed control plane.
  - 1 managed node group (`t3.small` or `t4g.small`).
  - IRSA enabled.

**Tasks**
1. Use `terraform-aws-modules/vpc` in `main.tf` to build VPC.
2. Use `terraform-aws-modules/eks` to create `env-eks` cluster in private subnets.
3. Add Makefile with `up`/`down` targets.
4. Run:
   - `make up`
   - `aws eks update-kubeconfig ...`
   - `kubectl get nodes`
   - `make down`

**You should understand**
- How EKS references subnets and security groups.
- That the entire cluster is disposable.

---

## Week 2 – GitOps-Ready Cluster & Basic Tooling

**Goals**
- Prepare the cluster for GitOps and platform add-ons.
- Still fully ephemeral.

**Add**
- Namespaces for `platform` and `apps`.
- ServiceAccount and RBAC patterns.
- (Option A) Argo CD installed via Helm (in `platform` namespace).
- (Option B) Flux installed similarly.

**Tasks**
1. Add Terraform `kubernetes` and/or `helm` providers (using EKS auth).
2. Install Argo CD:
   - Helm release from `argo/argo-cd` chart.
   - Values:
     - Minimal resource requests.
     - NodePort or ClusterIP (you’ll add ingress later).
3. Create a simple `Application` or `Kustomization` pointing to a local path (later to be a Git repo remote).

**You should understand**
- GitOps control loop concept.
- That Argo/Flux themselves are deployed + destroyed with `make down`.

---

## Week 3 – Ingress with AWS Load Balancer Controller

**Goals**
- Use AWS-native ingress (ALB) for services.
- Understand how Ingress → ALB mapping works.

**Add**
- AWS Load Balancer Controller via Helm.
- IAM Role for ServiceAccount (IRSA).
- Sample app exposed via Ingress.

**Tasks**
1. In Terraform:
   - Create IAM policy/role for LB Controller.
   - Annotate ServiceAccount for IRSA.
2. Install LB Controller.
3. Create `k8s/sample-app/`:
   - Deployment + Service + Ingress (with ALB annotations).
4. `make up`:
   - Wait for ALB.
   - Hit app via ALB DNS.
5. `make down`:
   - Confirm ALB and targets are removed.

**You should understand**
- ALB lifecycle and how K8s objects drive infra.
- Why IRSA is used instead of node-wide IAM.

---

## Week 4 – ExternalDNS, TLS, and Clean URLs

**Goals**
- Realistic DNS + HTTPS flow.
- Still ephemeral.

**Add**
- Route 53 hosted zone (e.g. `eks-lab.yourdomain.com`).
- ExternalDNS with restricted IAM.
- cert-manager + ACM (DNS-validated cert).

**Tasks**
1. Create a Route 53 zone via Terraform.
2. Install ExternalDNS:
   - IAM role via IRSA, limited to that zone.
3. Install cert-manager:
   - Issuer that uses DNS-01 via Route 53 (or ACM for public certs).
4. Update sample app Ingress:
   - Host: `app.<env>.eks-lab.yourdomain.com`
   - TLS enabled.

**You should understand**
- How DNS + certificates are automated in K8s.
- How all of this is tied to tags/env and is disposable.

---

## Week 5 – CI/CD Integration (Images, ECR, GitOps Sync)

**Goals**
- From git push → build → ECR → GitOps deploy.
- Production-style promotion *mechanics*.

**Add**
- ECR repo(s) via Terraform.
- GitHub Actions or CodeBuild pipeline:
  - Build & push image.
  - Update a manifest/Helm values that Argo/Flux syncs.
- Optional: Trivy scan in CI.

**Tasks**
1. Terraform:
   - One ECR repo per app.
2. CI:
   - On push: login to ECR, build image, push.
   - Update image tag used by `sample-app` chart/manifests.
3. Argo/Flux syncs the change into the cluster.

**You should understand**
- How application delivery is automated end-to-end.
- Where to enforce security (scan, sign, policies).

---

## Week 6 – Scaling & Karpenter (or Cluster Autoscaler)

**Goals**
- Automatic node scaling with realistic patterns.

**Add**
- Karpenter (preferred) or Cluster Autoscaler.
- Spot + On-Demand mix for nodes.

**Tasks**
1. Define minimal Provisioner(s) (e.g., allow `t3.small`, `t3.medium`, Spot).
2. Create a load test Job/Deployment to trigger scale-out.
3. Observe nodes appear/disappear based on unschedulable pods.

**You should understand**
- How scheduling and node provisioning integrate.
- Cost and reliability tradeoffs.

---

## Week 7 – Observability: Metrics, Logs, Traces

**Goals**
- See what’s happening in the cluster.

**Add**
- OpenTelemetry Collector DaemonSet.
- Metrics:
  - Either Prometheus in-cluster or Amazon Managed Prometheus.
- Dashboards:
  - Grafana (self-managed or Amazon Managed Grafana).
- Logs:
  - CloudWatch Logs or OpenSearch for structured logs.
- Traces:
  - X-Ray or OTEL to a backend.

**Tasks**
1. Add Helm charts for:
   - OTel collector
   - Metrics pipeline
2. Create:
   - One “Golden Signals” dashboard for sample app.
3. Configure a simple alert (error rate, latency, 5xx on ALB).

**You should understand**
- How telemetry flows from pods → collector → backends.
- Basic SLO/alerting concepts.

---

## Week 8 – Security & Policy

**Goals**
- Enforce good behavior in the cluster.

**Add**
- Kyverno or OPA Gatekeeper policies:
  - No `:latest` tags.
  - Require resource requests/limits.
  - Disallow privileged pods.
- Image scanning in CI.
- KMS-managed keys for Secrets Manager / EBS.

**Tasks**
1. Install policy engine via Helm.
2. Author at least 3 policies and watch them block bad manifests.
3. Hook Trivy or similar into CI for image scans.

**You should understand**
- Admission control.
- How to express guardrails as code.

---

## Week 9 – Stateful Services (Aurora/EFS)

**Goals**
- Connect apps to real managed state.

**Add**
- Aurora Serverless v2 (or small RDS).
- Optional EFS for shared storage.
- Secrets in Secrets Manager; apps use IRSA to fetch.

**Tasks**
1. Terraform:
   - Aurora cluster/subnets.
   - Secret for DB credentials.
2. App:
   - Read DSN from Secrets Manager/Env.
3. Confirm:
   - Migrations.
   - Basic read/write.

**You should understand**
- Network paths (subnets, SGs) for DB.
- Secure secret access from pods.

---

## Week 10 – Async Work: Queues & Events

**Goals**
- Build async and event-driven patterns.

**Add**
- SQS queue + DLQ.
- SNS or EventBridge for events.
- Worker Deployment consuming from SQS.

**Tasks**
1. Terraform SQS/SNS/EventBridge.
2. App pattern:
   - API writes a message.
   - Worker reads, processes, logs.
3. Add metrics:
   - Queue depth alarms.
   - DLQ notifications.

**You should understand**
- Decoupling services.
- Operational signals for backlogs.

---

## Week 11 – Resilience & Upgrades

**Goals**
- Practice failure handling and safe upgrades.

**Add**
- Fault Injection Simulator (FIS) experiments:
  - Kill nodes.
  - Add latency.
  - Disrupt AZ.
- EKS upgrade runbook:
  - New version.
  - Rolling nodegroup rotation.

**Tasks**
1. Write and run at least one FIS experiment.
2. Perform a simulated EKS minor version upgrade in your lab.
3. Validate:
   - Health checks.
   - Rollbacks.
   - No data loss.

**You should understand**
- Real-world failure modes.
- Safe upgrade practices.

---

## Week 12 – DR, Multi-Region Taste & Cost Awareness

**Goals**
- Basic DR story and a handle on costs.

**Add**
- S3 replication to a second region.
- Simple “shadow” stack in second region (even if partial).
- Route 53 health checks & failover routing (or weighted).
- Cost visibility:
  - AWS Budgets.
  - Tagged cost breakdown (by env, project).

**Tasks**
1. Build a minimal mirror of core infra in another region.
2. Run a manual or scripted failover of your sample app.
3. Review Cost Explorer by tags.

**You should understand**
- Multi-Region tradeoffs.
- How to explain your infra & cost model.

---

## Optional: TTL Janitor (After You’re Comfortable)

Once you’re solid with apply/destroy:

1. Create a small Terraform stack that:
   - Adds an EventBridge rule (e.g., every 30 min).
   - Invokes a Lambda.
2. Lambda:
   - Lists resources with `ttl_hours` and `created_at`.
   - Deletes any past their TTL (EKS, ALBs, EC2, etc).

This is a safety net, not a crutch. The main habit remains: **`make down` when done.**

---

## How to Use This Document

- Treat each week as:
  1. **Read** this section.
  2. **Implement** the minimal Terraform/Helm needed.
  3. **Run** `make up`, test features, then `make down`.
  4. **Commit** with clear messages & notes.
- Don’t rush to all the “fancy” parts. Make sure:
  - You can explain each resource.
  - You know how to debug when `apply`/`destroy` fail.
  - You can sketch the architecture on a whiteboard from memory.

By the end of 12 weeks, you can confidently say you’ve **designed, built, operated, and torn down a production-style AWS/EKS platform** with modern DevOps practices—and you’ll actually understand it.
