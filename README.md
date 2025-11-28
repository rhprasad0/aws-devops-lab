# EKS Ephemeral Lab

Production-style AWS/EKS DevOps learning platform.

**Timeline:** Part-time weekends (12 hrs/week) | **Budget:** $250/month | **Progress:** Weeks 0-9 ✅

---

## Quick Start

```bash
make up      # Create infrastructure + configure kubectl
make down    # Destroy everything
```

---

## Completed (Weeks 0-9)

| Week | Topic | Status |
|------|-------|--------|
| 0 | AWS Setup, Billing, Terraform State | ✅ |
| 1 | VPC Foundation | ✅ |
| 2 | EKS Cluster | ✅ |
| 3 | GitOps (Argo CD) | ✅ |
| 4 | AWS Load Balancer Controller | ✅ |
| 5 | ExternalDNS | ✅ |
| 6 | TLS (cert-manager) | ✅ |
| 7 | Buffer Week | ✅ |
| 8 | CI/CD Build (ECR, GitHub Actions) | ✅ |
| 9 | CI/CD Deploy (GitOps flow) | ✅ |

**State Backend:** S3 `ryan-eks-lab-tfstate` + DynamoDB `eks-lab-tfstate-lock`

---

## Remaining Weeks

### Week 10 – Observability: Metrics & Dashboards 🚧 BLOCKED
**Goal:** AMP + AMG + ADOT for metrics collection

- [x] Create AMP workspace (Terraform)
- [x] Create AMG workspace with SSO auth
- [x] Install ADOT Collector with EKS Pod Identity
- [x] Configure Prometheus scraping → AMP remote write (container metrics working)
- [x] Import Grafana dashboards (cluster, node, app golden signals)
- [ ] **BLOCKED:** Application metrics scraping (see `docs/week10-guestbook-metrics-investigation.md`)

**Blocker:** ADOT Prometheus receiver v0.36.0 relabel_configs fail to construct `__address__` from `__meta_kubernetes_pod_ip` + annotation port. Multiple syntax variants tested; all produce `instance=":"`. Container metrics work via cAdvisor; only custom app metrics (e.g., `http_requests_total`) are affected. Options: static_configs workaround, switch to kube-prometheus-stack, or file ADOT bug.

**Cost:** ~$4/session (AMP ingestion + AMG ~$9/editor/month)

---

### Week 11 – Observability: Logs & Traces
**Goal:** Centralized logging and distributed tracing

- [ ] Install Fluent Bit DaemonSet → CloudWatch Logs or Loki
- [ ] Configure log parsing and filters
- [ ] Install OpenTelemetry Collector for tracing → X-Ray or Jaeger
- [ ] Instrument sample app with trace spans
- [ ] Correlate metrics → logs → traces

**Cost:** ~$5/session (CloudWatch Logs ~$0.50/GB)

---

### Week 12 – Scaling: Karpenter
**Goal:** Automatic node provisioning

- [ ] Create Karpenter IAM role (IRSA)
- [ ] Install Karpenter Helm chart
- [ ] Create NodePool (Spot + On-Demand, t3/t4g families)
- [ ] Scale down static node groups
- [ ] Test scale-out/scale-in with replica changes

**Cost:** ~$4/session (potential Spot savings)

---

### Week 13 – Buffer Week
**Goal:** Consolidation and catch-up

- [ ] Refactor Helm charts, standardize labels
- [ ] Cost review via Cost Explorer
- [ ] Security audit: privileged pods, hostPath, IRSA usage
- [ ] Research Kyverno vs OPA Gatekeeper

---

### Week 14 – Security & Policy Enforcement
**Goal:** Admission control and secrets management

- [ ] Install Kyverno
- [ ] Create policies: no `:latest`, require limits, no privileged, require labels
- [ ] Add Trivy to CI pipeline (fail on HIGH/CRITICAL)
- [ ] Install External Secrets Operator
- [ ] Sync secret from Secrets Manager → K8s

**Cost:** ~$5/session (Secrets Manager ~$0.40/secret/month)

---

### Week 15 – Stateful: RDS/Aurora
**Goal:** App connected to managed database

- [ ] Add Aurora Serverless v2 (0.5-1 ACU, private subnets)
- [ ] Store credentials in Secrets Manager
- [ ] Sync via External Secrets Operator
- [ ] Update app: DB client, health check, read/write endpoints
- [ ] Verify ephemeral cleanup

**Cost:** ~$10-15/session (Aurora ~$0.12/ACU-hour)

---

### Week 16 – Async: SQS/SNS Workers
**Goal:** Event-driven architecture

- [ ] Add SQS queue + DLQ, SNS topic (Terraform)
- [ ] Create IRSA role for app (SQS/SNS permissions)
- [ ] API endpoint → SQS/SNS
- [ ] Worker deployment: poll, process, delete messages
- [ ] CloudWatch alarms for queue depth and DLQ

**Cost:** ~$6/session

---

### Week 17 – Resilience & Chaos
**Goal:** Understand failure modes

- [ ] Add PodDisruptionBudgets
- [ ] Manual chaos: delete pods, drain nodes
- [ ] AWS FIS experiment: terminate EC2 instance
- [ ] Test Aurora failover
- [ ] Document runbooks

**Cost:** ~$12/session

---

### Week 18 – EKS Upgrade
**Goal:** Safe upgrade procedures

- [ ] Research deprecations for next EKS version
- [ ] Pre-upgrade: check addon compatibility, deprecated APIs
- [ ] Upgrade control plane in Terraform
- [ ] Upgrade node groups (or let Karpenter rotate)
- [ ] Upgrade addons (VPC CNI, CoreDNS, kube-proxy)

**Cost:** ~$8/session

---

### Week 19 – Multi-Region & DR
**Goal:** Basic disaster recovery

- [ ] Create minimal stack in second region
- [ ] S3 cross-region replication, ECR replication
- [ ] Route 53 health checks + failover routing
- [ ] Document manual failover procedure
- [ ] Test RTO

**Cost:** ~$15/session

---

### Week 20 – Cost Optimization & Wrap-Up
**Goal:** Production-ready cost controls and documentation

- [ ] Cost review by tag in Cost Explorer
- [ ] Optimize: Spot instances, log retention, ECR lifecycle
- [ ] Optional: TTL Janitor Lambda
- [ ] Final architecture diagram
- [ ] Complete README with runbooks

**Cost:** ~$6/session

---

## Repo Structure

```
infra/           # Terraform
k8s/             # Helm/manifests
  argocd/        # Argo CD config + Applications
  guestbook/     # Sample app
scripts/         # up.sh, down.sh
dashboards/      # Grafana JSON
docs/            # Week-specific notes
```

---

## Tagging Convention

All resources tagged with: `project`, `env`, `owner`, `created_at`, `ttl_hours`

---

## Security Baseline

- MFA on root, IAM user for daily work
- Security Hub, GuardDuty, Config enabled
- IRSA for pod-to-AWS access
- HTTPS for public endpoints
- No 0.0.0.0/0 except documented ALB

---

## Success Criteria (Week 20)

✅ Spin up full platform in <30 min  
✅ Deploy via GitOps, zero manual kubectl  
✅ Automatic HTTPS + DNS  
✅ Metrics, logs, traces observable  
✅ Graceful failure handling  
✅ Security policies enforced  
✅ DB + queue connectivity  
✅ Destroy cleanly with one command  
✅ Understand and explain every component
