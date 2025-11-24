# 16-20 Week Production-Style AWS/EKS DevOps Learning Plan (Ephemeral Lab)


## Security Baseline

This lab is intended to build production-style habits, including security by default. Before (or as soon as) you begin the weekly work, ensure the following are in place in your lab account/cluster:

- **Identity & access**
  - Root account is not used for day-to-day work; an IAM user or role with MFA is required.
  - IAM policies are created with least privilege in mind (no broad `"*:*"` policies except for short-lived experiments).
- **AWS security services**
  - **AWS Security Hub** is enabled in the primary lab region (us-east-1), using the AWS-managed security standards as a reference.
  - **Amazon GuardDuty** is enabled to surface suspicious activity in the account, with Kubernetes audit logs monitoring for EKS.
  - **AWS Config** is enabled with basic rules for S3 buckets, security groups, IAM roles/policies, and EKS clusters. Uses daily recording frequency to control costs.
- **Networking & data**
  - VPCs, subnets, and security groups avoid `0.0.0.0/0` inbound access except where explicitly documented (e.g., ALB HTTP/HTTPS).
  - Terraform state buckets and any other persistent data stores are private, encrypted, and tagged for ownership and TTL.
- **Kubernetes & workloads**
  - EKS clusters are created with IAM Roles for Service Accounts (IRSA) enabled, and new workloads that talk to AWS APIs should prefer IRSA over node roles.
  - Publicly exposed services are fronted by an ingress/ALB and, where possible, served over HTTPS using cert-manager and ACM/Let’s Encrypt.

Treat these as guardrails: future weeks assume they are present so you can focus on iterating toward a secure, observable, and maintainable platform instead of bolting security on later.

**Security Services Cost:** ~$3-5/month for minimal usage with daily Config recording and basic GuardDuty monitoring.

**Timeline:** Part-time weekends (6 hours/day = 12 hours/week)
**Budget:** ~$250/month
**Background:** Data engineer with GCP/Terraform/EKS experience, building production-grade AWS/DevOps skills

---

## Week 0 Progress

**Terraform Remote State Backend:**
- S3 Bucket: `ryan-eks-lab-tfstate` (us-east-1, versioning enabled)
- DynamoDB Table: `eks-lab-tfstate-lock` (for state locking)
- Created: 2025-11-08

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
   - Optional: add a "janitor" Lambda later that deletes expired resources.

4. **Prod-Parity, Not Prod-Scale**
   - Use the **same tools and patterns** as production.
   - Keep node sizes, traffic, and retention small.
   - Build with a "security by default" mindset across IAM, networking, CI/CD, and runtime.

5. **Understand Every Piece**
   - You write the Terraform/Helm yourself, stepwise.
   - No forking huge templates you don't understand.

---

## Repo Layout

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
│  └─ cost-check.sh
├─ Makefile
├─ .cost-budget          # Track spending
└─ README.md
```

---

## Week 0 – AWS Account Setup & Cost Controls

**Time:** 4-6 hours
**Goal:** Secure AWS account, set up billing alerts, prepare for safe experimentation

**Tasks**
1. **Billing & Budget:**
   - Create AWS Budget: $250/month with alerts at 50%, 80%, 100%
   - Enable Cost Explorer
   - Set up billing email alerts
   - Consider separate "lab" AWS account via AWS Organizations (optional but recommended)

2. **IAM Security:**
   - Enable MFA on root account
   - Create IAM user for yourself (if not already done) with MFA
   - Create IAM policy for lab work (VPC, EKS, EC2, RDS, Route53, IAM roles, etc.)
   - Consider using AWS CloudShell or dedicated lab profile

3. **Remote State Setup:**
   - Create S3 bucket for Terraform state: `<your-name>-eks-lab-tfstate`
   - Enable versioning on bucket
   - Create DynamoDB table for state locking: `eks-lab-tfstate-lock`
   - Document this in README

4. **Cost Tagging Strategy:**
   - Document your tagging convention
   - Set up AWS Cost Allocation Tags in console
   - Activate tags: `project`, `env`, `owner`, `ttl_hours`

5. **Security Baseline Services:**
   - Enable AWS Security Hub, GuardDuty, and AWS Config in your primary lab region.
   - Use default AWS-managed security standards in Security Hub as a reference, even if you don't remediate everything yet.
   - Confirm the Terraform state S3 bucket is private, encrypted, and only accessible by your lab IAM user/role.
   - Note these services and guardrails in the README under a "Security Baseline" subsection.

**Deliverable:**
- AWS account secured with MFA
- Billing alerts configured
- S3 + DynamoDB ready for Terraform
- Document everything in README

**Cost:** ~$1 (S3 + DynamoDB minimal usage)

---

## Week 1 – VPC Foundation & Tagging

**Time:** 8-10 hours
**Goal:** Production-style VPC with proper tagging, remote state working

**Tasks**
1. Set up Terraform backend in `infra/terraform.tf`:
   - Configure S3 backend with DynamoDB locking
   - Test `terraform init`

2. Create minimal VPC using `terraform-aws-modules/vpc`:
   - CIDR: `/16`
   - 2 public + 2 private subnets across 2 AZs
   - **No NAT Gateway yet** (save costs)
   - Proper subnet tags for EKS (you know these from your previous work)

3. Configure AWS provider with `default_tags`:
   ```hcl
   default_tags {
     tags = {
       project    = "eks-ephemeral-lab"
       env        = var.env
       owner      = var.owner
       created_at = timestamp()
       ttl_hours  = var.ttl_hours
     }
   }
   ```

4. Add variables: `env`, `owner`, `region`, `ttl_hours`

5. Create simple Makefile:
   ```makefile
   up:
       cd infra && terraform init && terraform apply

   down:
       cd infra && terraform destroy
   ```

6. Test full lifecycle:
   - `make up`
   - Verify VPC in console
   - Check tags
   - `make down`
   - Verify cleanup

**Understand:**
- Remote state locking behavior
- How default_tags propagate
- VPC subnet requirements for EKS


**Security Focus:**
- Avoid security groups with wide-open inbound rules; if you must use `0.0.0.0/0` for testing, restrict it to HTTP/HTTPS and document the justification.
- Design network boundaries consciously (public vs private subnets, NAT/no-NAT) and record how they reduce your exposed attack surface.
- Enable VPC Flow Logs (even with short retention) so you can later investigate suspicious traffic patterns.

**Cost:** ~$0.50 (S3, minimal VPC resources)

---
## Week 2 – First Ephemeral EKS Cluster

**Time:** 10-12 hours
**Goal:** Working EKS cluster you can create/destroy reliably

**Tasks**
1. Add EKS cluster using `terraform-aws-modules/eks`:
   - Cluster name: `${var.env}-eks`
   - Version: 1.31 (latest stable)
   - Private endpoint enabled
   - Public endpoint enabled (for your laptop access)
   - IRSA enabled (OIDC provider)

2. Add ONE managed node group:
   - Instance type: `t3.small` (or `t4g.small` for ARM)
   - Min: 1, Max: 2, Desired: 1
   - Use private subnets
   - Disk: 20GB gp3

3. Update Makefile:
   ```makefile
   up:
       cd infra && terraform init && terraform apply -auto-approve
       aws eks update-kubeconfig --name $(ENV)-eks --region $(REGION)
       kubectl get nodes
   ```

4. Add `scripts/up.sh` for safer interactive version (with confirmations)

5. Test ephemeral cycle:
   - `make up`
   - Verify nodes: `kubectl get nodes`
   - Deploy nginx: `kubectl run test --image=nginx`
   - `make down`
   - Verify complete cleanup in console

**Common Issues:**
- EKS control plane takes 10-15 minutes to create
- Node groups take 5-10 minutes
- Budget 20-25 minutes for full `up` cycle

**Understand:**
- EKS cluster architecture (control plane vs data plane)
- Why IRSA matters
- Node group vs self-managed nodes


**Security Focus:**
- Use IRSA as the default for any pod that talks to AWS APIs instead of relying on node IAM roles.
- Set up basic Kubernetes RBAC so you can experiment with read-only vs admin access and verify permissions with `kubectl auth can-i`.
- Think through EKS endpoint exposure: document how you would lock it down to private endpoint plus VPN/SSM in a real environment.

**Cost per 6-hour session:** ~$1.50 (EKS + 1 node)

---
## Week 3 – GitOps Foundation (Argo CD)

**Time:** 8-10 hours
**Goal:** Argo CD installed and managing its first application

**Tasks**
1. Add Terraform Kubernetes and Helm providers:
   ```hcl
   provider "kubernetes" {
     host                   = module.eks.cluster_endpoint
     cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
     exec {
       api_version = "client.authentication.k8s.io/v1beta1"
       command     = "aws"
       args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
     }
   }
   ```

2. Create `k8s/argocd/` directory with:
   - Namespace manifest
   - Helm values (minimal resource requests)
   - Option A: Install via Helm in Terraform
   - Option B: Install manually via Helm CLI (simpler for learning)

3. Access Argo CD UI:
   - Port-forward: `kubectl port-forward svc/argocd-server -n argocd 8080:443`
   - Get initial password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`

4. Create first Application:
   - Simple nginx deployment in `k8s/sample-app/`
   - Create Argo Application pointing to local git repo or directory

5. Test GitOps flow:
   - Change replica count in manifest
   - Commit, push
   - Watch Argo sync

**Understand:**
- GitOps reconciliation loop
- Argo Application CRD
- Difference between Argo CD and manual kubectl


**Security Focus:**
- Avoid long-lived `admin` usage in Argo CD; rotate the default password, create named users, and document how you'd integrate SSO in a real setup.
- Treat the GitOps repo as a security boundary: all cluster changes should flow through PRs and Git history, not ad-hoc `kubectl` changes.
- Use Argo CD Projects and namespaces to limit which apps can deploy where, even in this single-cluster lab.

**Cost:** Same as Week 2 (~$1.50/session)

---
## Week 4 – AWS Load Balancer Controller

**Time:** 10-12 hours
**Goal:** Expose services via AWS ALB, understand Ingress → ALB mapping

**Tasks**
1. Create IAM role for AWS LB Controller:
   - Download policy JSON from AWS docs
   - Create IAM role with IRSA trust relationship
   - Attach policy

2. Install AWS Load Balancer Controller:
   - Helm chart: `eks/aws-load-balancer-controller`
   - Set `clusterName`, `serviceAccount.annotations` for IRSA
   - Minimal replicas (1)

3. Create sample app in `k8s/sample-app/`:
   - Deployment (nginx or simple Go/Python app)
   - Service (NodePort or ClusterIP)
   - Ingress with annotations:
     ```yaml
     annotations:
       kubernetes.io/ingress.class: alb
       alb.ingress.kubernetes.io/scheme: internet-facing
       alb.ingress.kubernetes.io/target-type: ip
     ```

4. Test:
   - `kubectl apply -f k8s/sample-app/`
   - Wait for ALB creation (2-5 minutes)
   - Get ALB DNS: `kubectl get ingress`
   - Hit endpoint: `curl http://<alb-dns>`

5. Verify ephemeral cleanup:
   - `make down`
   - Check ALB is deleted (console or CLI)
   - **If ALB persists, add script to force-delete**

**Common Issues:**
- ALBs can survive Terraform destroy if not cleaned properly
- Target group health checks need correct config

**Understand:**
- How Ingress annotations map to ALB features
- IRSA for pod-to-AWS communication
- ALB target group health checks


**Security Focus:**
- Keep the ALB security group minimal: inbound only on required HTTP/HTTPS ports, outbound restricted to the VPC where possible.
- Ensure the controller's IRSA role has the least-privilege IAM policy recommended by AWS, not a wildcard admin role.
- Document how you would attach AWS WAF to your public ALBs to mitigate common web attacks in a production setting.

**Cost:** ~$2.50/session (ALB adds ~$0.15/hour)

---
## Week 5 – DNS Automation with ExternalDNS

**Time:** 8-10 hours
**Goal:** Automatic DNS record creation for Ingresses

**Tasks**
1. Create Route 53 hosted zone in Terraform:
   - Zone: `eks-lab.yourdomain.com` (or use subdomain)
   - Output nameservers
   - Update parent domain NS records (if applicable)

2. Create IAM role for ExternalDNS:
   - Policy: route53:ChangeResourceRecordSets (scoped to your zone)
   - IRSA trust relationship

3. Install ExternalDNS:
   - Helm chart or manifest
   - Configure to watch Ingress resources
   - Set `--domain-filter=eks-lab.yourdomain.com`
   - Minimal resources

4. Update sample app Ingress:
   - Add hostname: `app.dev.eks-lab.yourdomain.com`
   - **Note:** No ExternalDNS annotation needed - ExternalDNS automatically watches Ingress resources and uses the `host` field

5. Test:
   - Apply manifest
   - Wait 1-2 minutes for DNS propagation
   - Verify A record in Route 53 console
   - Hit URL: `curl http://app.dev.eks-lab.yourdomain.com`

**Understand:**
- How ExternalDNS watches K8s resources
- DNS propagation time
- IAM least privilege for single hosted zone
- **ExternalDNS Annotations:** The `external-dns.alpha.kubernetes.io/hostname` annotation is optional for Ingress resources. ExternalDNS automatically reads the `host` field from Ingress specs. Annotations are primarily used for Services or when overriding default behavior.


**Security Focus:**
- Scope the ExternalDNS IAM policy to the specific hosted zone ARN instead of allowing changes to all Route 53 zones.
- Use a dedicated lab subdomain (for example `eks-lab.example.com`) so any misconfiguration is isolated from your primary domains.
- Avoid wildcard records unless you need them, and record which services are intentionally exposed by DNS.

**Cost:** ~$3/session (Route 53: $0.50/zone/month + query costs)

---
## Week 6 – TLS with cert-manager

**Time:** 8-10 hours
**Goal:** Automatic HTTPS certificates

**Tasks**
1. Install cert-manager:
   - Helm chart from cert-manager.io
   - Install CRDs

2. Create ClusterIssuer:
   - Option A: Let's Encrypt with DNS-01 challenge (Route 53)
   - Option B: ACM certificate (simpler for AWS)
   - For learning: use Let's Encrypt DNS-01 with Route 53

3. Create Certificate resource:
   - Domain: `*.dev.eks-lab.yourdomain.com`
   - Or specific: `app.dev.eks-lab.yourdomain.com`

4. Update Ingress for TLS:
   ```yaml
   spec:
     tls:
       - hosts:
           - app.dev.eks-lab.yourdomain.com
         secretName: app-tls
   ```

5. Test:
   - `curl https://app.dev.eks-lab.yourdomain.com`
   - Verify valid certificate

**Understand:**
- Certificate lifecycle automation
- DNS-01 vs HTTP-01 challenges
- How cert-manager integrates with Ingress


**Security Focus:**
- Ensure all public endpoints are HTTPS-only and either redirect HTTP to HTTPS or remove insecure listeners entirely.
- Keep certificate and private key secrets in dedicated namespaces and treat them as sensitive data in your backup/restore plans.
- Run basic TLS checks (via curl or openssl) to validate certificate chains and hostname correctness rather than assuming it works.

**Cost:** Same as Week 5 (~$3/session)

---
## BUFFER WEEK 7 – Consolidation & Catch-Up

**Goal:** Solidify everything built so far

**Suggested Activities:**
1. Clean up your code:
   - Split Terraform into modules (vpc.tf, eks.tf, iam.tf, dns.tf)
   - Add better variable validation
   - Improve Makefile with env switching

2. Documentation:
   - Update README with architecture diagram (draw.io or Mermaid)
   - Document `make` commands
   - Add troubleshooting section


**Security Focus:**
- Create a simple threat model for your lab platform: identify key assets, actors, and the top few threats you care about.
- Review IAM roles, Kubernetes RBAC bindings, and IRSA usage to remove any overly broad permissions you added while experimenting.
- Scan your Terraform and manifests for hard-coded secrets or credentials and replace them with proper secret mechanisms.

3. Cost analysis:
   - Review Cost Explorer by tags
   - Create `scripts/cost-check.sh` to query costs
   - Verify TTL tags are correct

4. Testing:
   - Run full up/down cycle multiple times
   - Test from scratch in new directory
   - Verify nothing persists after destroy

5. Get ahead (if time):
   - Research CI/CD tools (GitHub Actions, GitLab CI)
   - Plan sample application to deploy

---
## Week 8 – CI/CD Part 1: Container Registry & Build Pipeline

**Time:** 10-12 hours
**Goal:** Automated image builds to ECR

**Tasks**
1. Add ECR repository in Terraform:
   - Name: `eks-lab/sample-app`
   - Scan on push: true
   - Lifecycle policy: keep last 5 images

2. Create sample application:
   - Simple Go/Python/Node app with Dockerfile
   - Health check endpoint
   - Build locally first

3. Set up GitHub Actions (or GitLab CI):
   - Workflow on push to main
   - Build image
   - Push to ECR with git SHA tag
   - Optional: Trivy scan for vulnerabilities

4. Create OIDC trust for GitHub Actions:
   - IAM role with ECR push permissions
   - GitHub OIDC provider in AWS
   - No long-lived credentials

5. Test:
   - Push code change
   - Watch action build and push
   - Verify image in ECR

**Understand:**
- ECR authentication
- GitHub OIDC vs access keys
- Container image tagging strategies


**Security Focus:**
- Introduce image scanning (for example, Trivy) into the build pipeline and at least fail builds on high/critical vulnerabilities.
- Prefer immutable image tags (like git SHAs) instead of `latest` so you can trace exactly what is running in the cluster.
- Use GitHub OIDC to assume AWS roles instead of long-lived AWS access keys stored as CI secrets.

**Cost:** ~$3.50/session (ECR: $0.10/GB/month storage)

---
## Week 9 – CI/CD Part 2: GitOps Deployment

**Time:** 10-12 hours
**Goal:** Complete CI → CD → Deploy flow

**Tasks**
1. Update GitHub Action to:
   - After image push, update Helm values or K8s manifest
   - Commit new image tag to git repo (or separate config repo)
   - Trigger Argo CD sync (webhook or auto)

2. Configure Argo CD Application:
   - Set sync policy to automatic
   - Enable pruning
   - Enable self-heal

3. Implement deployment strategy:
   - Option A: Blue/Green with Argo Rollouts
   - Option B: Canary with Argo Rollouts
   - Option C: Simple RollingUpdate (easiest)

4. Test full flow:
   - Change app code (e.g., update response text)
   - Push to git
   - Watch: build → ECR → manifest update → Argo sync → pods rolling
   - Verify via curl

5. Add rollback test:
   - Deploy broken image
   - Observe health check failure
   - Manual rollback via Argo

**Understand:**
- GitOps vs push-based CD
- How to handle secrets (preview: Week 14)
- Deployment strategies tradeoffs


**Security Focus:**
- Require that only images that have passed security scans are referenced in manifests that get merged to main or deployed.
- Use branches and pull requests to model environment promotion so there is always a review step before production-like changes.
- Avoid storing long-lived secrets directly in your CI system; plan to integrate with AWS Secrets Manager and External Secrets Operator.

**Cost:** Same as Week 8 (~$3.50/session)

---
## Week 10 – Observability Part 1: Metrics & Dashboards

**Time:** 10-12 hours
**Goal:** Prometheus + Grafana with basic dashboards

**Tasks**
1. Install Prometheus:
   - Option A: kube-prometheus-stack Helm chart (includes Grafana)
   - Option B: Prometheus Operator + Grafana separately
   - Use minimal retention (2 hours)
   - Small PVC (5GB) or ephemeral storage

2. Configure ServiceMonitors:
   - Monitor your sample app (add `/metrics` endpoint)
   - Monitor EKS nodes
   - Monitor ALB (via CloudWatch exporter)

3. Access Grafana:
   - Port-forward or expose via Ingress
   - Import dashboards:
     - Kubernetes cluster monitoring
     - ALB monitoring
     - Application golden signals (latency, traffic, errors, saturation)

4. Create custom dashboard:
   - Request rate by endpoint
   - P50/P95/P99 latency
   - Error rate
   - Pod CPU/memory

5. Test:
   - Generate load (hey, k6, or simple curl loop)
   - Watch metrics update
   - Query PromQL directly

**Understand:**
- Prometheus scrape model
- ServiceMonitor vs PodMonitor
- Basic PromQL queries
- Grafana data source configuration


**Security Focus:**
- Include security-relevant metrics (4xx/5xx rates, anomalous traffic per endpoint) in Grafana dashboards alongside SLOs.
- Lock down access to metrics and dashboards so they are not exposed publicly, even in the lab.
- Use labels and naming to clearly distinguish between internal and internet-facing services when building dashboards.

**Cost:** ~$4/session (add ~$0.50 for small EBS volume)

---
## Week 11 – Observability Part 2: Logs & Traces

**Time:** 10-12 hours
**Goal:** Centralized logging and basic distributed tracing

**Tasks**
1. **Logging:**
   - Install Fluent Bit or Fluentd as DaemonSet
   - Ship logs to:
     - Option A: CloudWatch Logs (simple, AWS-native)
     - Option B: Grafana Loki (cost-effective, integrated with Grafana)
   - Configure log filters and parsing
   - Create IAM role for CloudWatch (if using)

2. **Log Query Interface:**
   - CloudWatch Insights queries
   - Or Loki queries in Grafana

3. **Distributed Tracing (intro):**
   - Install OpenTelemetry Collector (or AWS X-Ray agent)
   - Instrument sample app with basic trace spans
   - Send traces to:
     - Option A: AWS X-Ray
     - Option B: Jaeger (self-hosted, ephemeral)
   - View trace waterfall for single request

4. **Correlation:**
   - Add trace IDs to logs
   - Link from Grafana dashboard → logs → traces

5. Test:
   - Generate traffic
   - Query logs by pod, namespace, error level
   - Find specific trace for slow request
   - Correlate metrics spike with log errors

**Understand:**
- Structured logging vs unstructured
- Log shipping patterns (sidecar vs DaemonSet)
- Trace context propagation
- Observability correlation (metrics → logs → traces)


**Security Focus:**
- Ensure application logs include enough structured context (user, action, trace ID) to support security investigations.
- Review CloudTrail and GuardDuty findings as part of this week and walk through how you would triage at least one of them.
- Define log retention settings that balance cost with the need to investigate incidents (for example, 7–14 days by default).

**Cost:** ~$5/session (CloudWatch Logs: ~$0.50/GB ingested)

---
## Week 12 – Scaling: Karpenter or Cluster Autoscaler

**Time:** 8-10 hours
**Goal:** Automatic node provisioning based on pod demand

**Tasks**
1. **Choose your path:**
   - Option A: Karpenter (AWS-native, modern, recommended)
   - Option B: Cluster Autoscaler (older, more generic)

2. **Install Karpenter** (recommended):
   - Create IAM role with EC2 permissions (IRSA)
   - Install Karpenter Helm chart
   - Create NodePool (Karpenter v1.0+):
     ```yaml
     spec:
       template:
         spec:
           requirements:
             - key: karpenter.sh/capacity-type
               operator: In
               values: ["spot", "on-demand"]
             - key: kubernetes.io/arch
               operator: In
               values: ["amd64"]
             - key: karpenter.k8s.aws/instance-family
               operator: In
               values: ["t3", "t4g"]
           taints: []
     ```

3. Remove or scale down static node groups:
   - Set min/max to 1/1 for minimal baseline
   - Let Karpenter handle scale-out

4. Test scale-out:
   - Deploy workload with large replica count (e.g., 10)
   - Set resource requests
   - Watch Karpenter logs: nodes provisioned
   - Scale down to 1, watch nodes deprovisioned (after 30s default)

5. Test Spot interruption:
   - Use Spot instances
   - Research: AWS Node Termination Handler
   - Observe graceful pod eviction

**Understand:**
- Karpenter vs Cluster Autoscaler differences
- Spot vs On-Demand tradeoffs
- Node consolidation and bin-packing
- TTL for node deprovisioning


**Security Focus:**
- Use node templates or provisioners that specify supported, up-to-date instance families and avoid legacy types by default.
- Continue to rely on IRSA for pod permissions so scaling nodes does not widen the blast radius of any instance profile.
- Document any security implications of using Spot instances (for example, shorter lifetimes but same IAM role power).

**Cost:** ~$4/session (mostly same, potential Spot savings)

---
## BUFFER WEEK 13 – Consolidation & Advanced Topics Research

**Goal:** Catch up, document, and research next phase

**Suggested Activities:**
1. Review and refactor:
   - Consolidate Helm charts
   - Standardize labels and annotations
   - Document observability stack in README


**Security Focus:**
- Perform a small security audit: look for privileged pods, hostPath mounts, and workloads that violate your own best practices.
- Evaluate tools like kube-bench or kube-hunter and decide where they would fit into a pre-production security pipeline.
- Tighten or remove any temporary exceptions you introduced while getting features working in earlier weeks.

2. Cost optimization review:
   - Check actual costs vs budget
   - Identify any leaked resources
   - Optimize Prometheus retention, log filters

3. Security prep:
   - Research Kyverno vs OPA Gatekeeper
   - Review your IAM policies for over-permissions
   - Plan next phase policies

4. Get ahead:
   - Research stateful workload patterns
   - Plan sample app with database

---
## Week 14 – Security & Policy Enforcement

**Time:** 10-12 hours
**Goal:** Admission control policies and image security

**Tasks**
1. Install policy engine:
   - **Kyverno** (recommended, easier) or OPA Gatekeeper
   - Helm installation

2. Create and enforce policies:
   - **No `:latest` tags:**
     ```yaml
     spec:
       rules:
         - name: no-latest-tag
           match:
             resources:
               kinds:
                 - Pod
           validate:
             message: "Using :latest tag is not allowed"
             pattern:
               spec:
                 containers:
                   - image: "!*:latest"
     ```
   - **Require resource limits:**
   - **Disallow privileged containers:**
   - **Require labels (owner, app, env)**

3. Test policies:
   - Try to deploy pod with `:latest` → blocked
   - Deploy without resource requests → blocked or warning
   - Verify audit mode vs enforce mode

4. Image scanning in CI:
   - Add Trivy to GitHub Actions
   - Fail pipeline on HIGH/CRITICAL CVEs
   - Generate SBOM (Software Bill of Materials)

5. Secrets management (intro):
   - Install External Secrets Operator (ESO)
   - Sync secret from AWS Secrets Manager to K8s Secret
   - App reads from K8s secret

**Understand:**
- Admission webhooks (validating vs mutating)
- Policy-as-Code
- Image vulnerability scanning
- Secrets lifecycle in K8s


**Security Focus:**
- Design Kyverno/Gatekeeper policies so they start in audit mode, then promote to enforce once you understand the impact.
- Enforce baseline security requirements such as labels, non-root containers, and restricted capabilities for most workloads.
- Backed by External Secrets Operator, ensure no new plaintext Kubernetes Secrets with hard-coded credentials are introduced.

**Cost:** ~$5/session (Secrets Manager: $0.40/secret/month)

---
## Week 15 – Stateful Services: RDS/Aurora

**Time:** 10-12 hours
**Goal:** Connect app to managed database

**Tasks**
1. Add Aurora Serverless v2 in Terraform:
   - Cluster in private subnets
   - PostgreSQL or MySQL
   - Minimal capacity: 0.5 ACU min, 1 ACU max
   - Security group: allow 5432/3306 from EKS nodes

2. Create database credentials in Secrets Manager:
   - Terraform resource: `aws_secretsmanager_secret`
   - Store JSON: `{"username": "...", "password": "...", "host": "...", "port": ...}`

3. Install External Secrets Operator (if not done in Week 14):
   - Create SecretStore pointing to Secrets Manager
   - Create ExternalSecret syncing DB credentials to K8s

4. Update sample app:
   - Add database client library
   - Read DSN from environment variables (loaded from K8s secret)
   - Implement:
     - Health check (DB ping)
     - Simple read/write endpoint
     - Database migration (optional: use Flyway, Liquibase, or golang-migrate)

5. Test:
   - `make up`
   - Verify app can connect to Aurora
   - Write data, read data
   - Check Grafana for DB connection metrics
   - `make down` → Aurora is destroyed


**Security Focus:**
- Ensure the database is encrypted at rest with KMS and only reachable from the relevant EKS node or security groups.
- Use a dedicated, least-privilege database user for the application instead of connecting as an admin or superuser.
- Keep all database credentials in AWS Secrets Manager and sync them via ESO; do not let them drift into git or CI variables.

**Cost:** ~$10-15/session (Aurora Serverless v2: ~$0.12/ACU-hour)

**Cost Optimization:**
- Use `skip_final_snapshot = true` in Terraform for lab
- Consider RDS Single-AZ t3.micro for cheaper alternative (~$0.017/hour)

**Understand:**
- VPC networking for RDS
- Security groups for database access
- Connection pooling importance
- Secrets rotation (read docs, not implemented yet)

---
## Week 16 – Async Work: SQS, SNS & Workers

**Time:** 8-10 hours
**Goal:** Event-driven architecture patterns

**Tasks**
1. Add in Terraform:
   - SQS queue: `eks-lab-tasks`
   - SQS Dead Letter Queue: `eks-lab-tasks-dlq`
   - SNS topic: `eks-lab-events`
   - Subscribe SQS to SNS

2. Create IAM role for app:
   - SQS: SendMessage, ReceiveMessage, DeleteMessage
   - SNS: Publish
   - Use IRSA

3. Update sample app:
   - API endpoint: POST `/task` → writes message to SQS
   - Or: publishes to SNS topic

4. Create worker Deployment:
   - Separate pod/container
   - Long-polls SQS
   - Processes message
   - Logs result
   - Deletes message

5. Add observability:
   - CloudWatch metrics for queue depth
   - Alert if ApproximateNumberOfMessagesVisible > 100
   - DLQ alarm for any messages

6. Test:
   - Send 10 tasks via API
   - Watch worker logs processing
   - Verify queue drains
   - Intentionally fail a message → observe DLQ

**Understand:**
- SQS vs SNS use cases
- At-least-once delivery semantics
- Visibility timeout and message deletion
- DLQ patterns for poison messages


**Security Focus:**
- Give producers and consumers separate IRSA roles with the minimal SQS/SNS permissions each needs.
- Treat message bodies as potentially sensitive data and avoid putting secrets or PII into log messages or SNS subjects.
- Design and test dead-letter queues with an eye toward abuse cases, such as attackers flooding your system with bad messages.

**Cost:** ~$6/session (Aurora + minimal SQS/SNS costs ~$0.01)

---
## Week 17 – Resilience Testing & Chaos Engineering

**Time:** 10-12 hours
**Goal:** Understand failure modes and safe operations

**Tasks**
1. Review current resiliency:
   - PodDisruptionBudgets (PDBs)
   - Readiness/liveness probes
   - Resource limits

2. Add PodDisruptionBudgets:
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: sample-app
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: sample-app
   ```

3. Manual chaos tests:
   - Delete random pod: `kubectl delete pod <name>`
   - Observe: new pod starts, no downtime (if replicas > 1)
   - Drain node: `kubectl drain <node> --ignore-daemonsets`
   - Observe: pods rescheduled

4. AWS Fault Injection Simulator (FIS) experiment:
   - Create FIS experiment template: terminate random EC2 instance
   - Requires IAM permissions and stop condition (safety)
   - Run experiment
   - Observe: Karpenter provisions replacement, pods migrate

5. Test database failover:
   - Aurora: force failover to reader
   - Observe app behavior (connection pool recovery)

6. Document runbooks:
   - Node failure response
   - Pod crashloop debugging
   - Database connection loss

**Understand:**
- Graceful shutdown and SIGTERM
- PDB prevents unsafe evictions
- Real failure scenarios vs theory
- Observability during incidents


**Security Focus:**
- Include chaos experiments that simulate security-relevant failures, such as invalid credentials or blocked deployments.
- For each experiment, write a short runbook describing how you would distinguish between misconfiguration and active attack.
- Use chaos results to refine alerts and dashboards so they highlight symptoms you would expect in a real incident.

**Cost:** ~$12/session (Aurora + potential extra node briefly)

---
## Week 18 – EKS Cluster Upgrade

**Time:** 8-10 hours
**Goal:** Safe upgrade procedures

**Tasks**
1. Research:
   - Current EKS version (e.g., 1.31)
   - Next version (e.g., 1.32)
   - Deprecation warnings: `kubectl get apiversions`
   - AWS EKS upgrade docs

2. Pre-upgrade checks:
   - Review addon compatibility (VPC CNI, CoreDNS, kube-proxy)
   - Check deprecated APIs in manifests
   - Backup critical data (if any)

3. Upgrade control plane in Terraform:
   - Change `cluster_version = "1.32"`
   - `terraform plan`
   - `terraform apply`
   - Wait 10-15 minutes

4. Upgrade managed node group:
   - Option A: Create new node group with new version, migrate, delete old
   - Option B: In-place upgrade (node group version)
   - Use Karpenter: nodes auto-rotate with new AMI

5. Upgrade addons:
   - Update VPC CNI, CoreDNS, kube-proxy via Terraform
   - Update Helm charts (Argo CD, Prometheus, etc.) if needed

6. Test:
   - Verify nodes: `kubectl get nodes`
   - Deploy sample workload
   - Check logs for errors

**Understand:**
- Control plane vs data plane upgrades
- Blue/green node group strategy
- Addon version compatibility
- Rollback procedures


**Security Focus:**
- Treat cluster and addon upgrades as a primary way to pick up security patches and close off deprecated, risky APIs.
- Audit workloads for deprecated Kubernetes APIs before upgrading so you are not forced to re-enable insecure configurations.
- Record the versions you upgrade from/to and the security-related release notes you care about.

**Cost:** ~$8/session (mostly same, brief dual node groups)

---
## Week 19 – Multi-Region & Disaster Recovery

**Time:** 10-12 hours
**Goal:** Basic DR and multi-region concepts

**Tasks**
1. Plan DR strategy:
   - Active-Passive: primary region, standby in second region
   - Active-Active: both regions serving traffic (complex, optional)

2. Create minimal "shadow" stack in second region:
   - Same Terraform code with different `var.region`
   - Smaller node count (1 node)
   - Same app deployed

3. Cross-region replication:
   - S3: enable cross-region replication for Terraform state
   - ECR: replicate images to second region
   - Aurora: global database (optional, expensive, skip for lab)

4. Route 53 health checks and failover:
   - Create health check for primary ALB
   - Weighted routing or failover routing policy
   - Test: disable primary, observe Route 53 directs to secondary

5. Manual failover procedure:
   - Document steps to promote secondary to primary
   - Test RTO (Recovery Time Objective): how long to switch?

**Understand:**
- Multi-region networking complexity
- Data replication lag

**Security Focus:**
- Design DR with security in mind: mirror IAM roles and policies carefully instead of loosening them for convenience.
- Think through how you would rebuild trust in a secondary region if the primary region's credentials or images were compromised.
- Plan for regional KMS keys and secrets replication strategies that avoid sharing master keys across regions unnecessarily.

- Cost tradeoffs of standby resources
- RTO/RPO (Recovery Point Objective) concepts

**Cost:** ~$15/session (brief second region cluster + data transfer)

---

**Security Focus:**
- Extend your TTL/janitor logic to clean up stale IAM roles, security groups, and secrets tagged for expiration.
- Review Security Hub and GuardDuty one more time and note which findings you would prioritize in a real environment.
- Summarize the DevSecOps practices you implemented across the lab as part of your final documentation.

## Week 20 – Cost Optimization, TTL Janitor & Wrap-Up

**Time:** 8-10 hours
**Goal:** Production-ready cost controls and documentation

**Tasks**
1. **Comprehensive cost review:**
   - AWS Cost Explorer by tag
   - Cost per week of lab work
   - Identify top 5 cost drivers
   - Document actual costs vs $250 budget

2. **Cost optimization:**
   - Savings Plans or Reserved Instances (skip for ephemeral)
   - Spot instances for worker nodes
   - S3 Intelligent-Tiering for logs
   - CloudWatch log retention policies (7 days)
   - ECR lifecycle policies (keep last 5 images)

3. **Optional: TTL Janitor Lambda:**
   - Small Lambda function:
     - Triggered by EventBridge (every hour)
     - Lists resources with `ttl_hours` tag
     - Calculates: `created_at + ttl_hours < now`
     - Deletes expired resources (EKS, EC2, ALB, RDS, etc.)
   - Safety: dry-run mode first, notifications to SNS

4. **Final documentation:**
   - Complete architecture diagram (draw.io, Mermaid, or Lucidchart)
   - README with:
     - Quick start
     - Prerequisites
     - Cost estimates
     - Troubleshooting
     - Runbooks
   - Document lessons learned

5. **Presentation prep (optional):**
   - Create slide deck summarizing project
   - Demo video of `make up` → deploy app → `make down`
   - Share on LinkedIn or personal blog

**Deliverable:**
- Production-ready ephemeral lab
- Complete documentation
- Cost controls in place
- Confidence to build AWS/EKS platforms

**Cost:** ~$6/session (mostly review work)

---

## Bonus Weeks 21+ (Optional Advanced Topics)

If you finish early or want to continue:

1. **Advanced GitOps:**
   - Multi-cluster Argo CD
   - ApplicationSets for environment promotion
   - Argo Rollouts with progressive delivery

2. **Service Mesh:**
   - Install Istio or Linkerd
   - Mutual TLS between services
   - Traffic splitting for canary deployments
   - Distributed tracing deep dive

3. **Advanced Security:**
   - Falco for runtime security
   - Kubebench for CIS benchmark compliance
   - Pod Security Standards enforcement
   - Network policies for microsegmentation

4. **Advanced Observability:**
   - OpenTelemetry full instrumentation
   - SLO/SLI/Error budgets with Sloth
   - On-call rotation with PagerDuty/Opsgenie
   - Incident response playbooks

5. **Developer Platform:**
   - Backstage.io for internal developer portal
   - Self-service namespace provisioning
   - Golden path templates
   - Cost showback per team

---
## Weekly Time Commitment Summary

| Week | Topic | Est. Hours | Cost/Session |
|------|-------|------------|--------------|
| 0 | AWS Setup | 4-6 | $1 |
| 1 | VPC | 8-10 | $0.50 |
| 2 | EKS | 10-12 | $1.50 |
| 3 | GitOps | 8-10 | $1.50 |
| 4 | Ingress | 10-12 | $2.50 |
| 5 | DNS | 8-10 | $3 |
| 6 | TLS | 8-10 | $3 |
| 7 | **BUFFER** | - | - |
| 8 | CI/CD Build | 10-12 | $3.50 |
| 9 | CI/CD Deploy | 10-12 | $3.50 |
| 10 | Metrics | 10-12 | $4 |
| 11 | Logs/Traces | 10-12 | $5 |
| 12 | Scaling | 8-10 | $4 |
| 13 | **BUFFER** | - | - |
| 14 | Security | 10-12 | $5 |
| 15 | RDS/Aurora | 10-12 | $10-15 |
| 16 | Queues | 8-10 | $6 |
| 17 | Chaos | 10-12 | $12 |
| 18 | Upgrade | 8-10 | $8 |
| 19 | Multi-Region | 10-12 | $15 |
| 20 | Wrap-up | 8-10 | $6 |

**Total estimated hours:** 168-210 hours
**At 12 hours/week:** 14-17.5 weeks
**Estimated total cost:** ~$150-250 (well within budget)

---

## Success Criteria

By Week 20, you should be able to:

✅ Spin up a full production-style EKS platform in <30 minutes
✅ Deploy applications via GitOps with zero manual kubectl
✅ Expose apps with automatic HTTPS and DNS
✅ Observe metrics, logs, and traces across the stack
✅ Handle node failures gracefully
✅ Enforce security policies automatically
✅ Connect to managed databases and queues
✅ Understand and explain every component
✅ Destroy everything cleanly with one command
✅ Estimate and control costs accurately

You'll have built, operated, and torn down a **production-grade AWS/EKS platform** and truly understand it.

---

## Tips for Success

1. **Commit early and often:** Git history is your learning log
2. **Document as you go:** Future-you will thank present-you
3. **Always run `make down`:** Make it muscle memory
4. **Tag resources religiously:** Cost attribution depends on it
5. **Break when stuck:** Some problems solve themselves overnight
6. **Join communities:** r/kubernetes, CNCF Slack, AWS re:Post
7. **Celebrate milestones:** Each working week is an achievement
8. **Iterate:** First pass is messy, refactor as you learn
9. **Keep a lab journal:** What worked, what didn't, lessons learned
10. **Share your work:** Blog posts solidify learning

Good luck! 🚀