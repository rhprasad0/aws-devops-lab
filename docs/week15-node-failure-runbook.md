# Week 15: Node Failure Runbook

## Overview

This runbook covers manual chaos testing for node failures. Use it to understand how Kubernetes handles disruptions and validate your resilience configuration.

**Companion to:** [AWS FIS Chaos Runbook](./week15-fis-chaos-runbook.md) (automated experiments)

---

## Disruption Types

| Type | Trigger | PDB Respected? | Example |
|------|---------|----------------|---------|
| **Voluntary** | Admin-initiated | Yes | `kubectl drain`, upgrades, Karpenter consolidation |
| **Involuntary** | Unexpected failure | No | Node crash, OOM, Spot interruption |

**Key insight:** PDBs only protect against voluntary disruptions. For involuntary failures, you need replicas spread across nodes (topology constraints) and fast rescheduling.

---

## Prerequisites

```bash
# Verify cluster health
kubectl get nodes
# All nodes: Ready

# Verify guestbook is running
kubectl get pods -n guestbook -o wide
# Expect: 3 pods across multiple nodes

# Verify PDB exists
kubectl get pdb -n guestbook
# Should show: guestbook  N/A  2  3  0
```

---

## Scenario 1: Delete Single Pod

**Purpose:** Test Kubernetes self-healing (ReplicaSet/Rollout controller)

**Risk:** Low - single pod deletion, immediate replacement

### Steps

```bash
# 1. Watch pods in another terminal
watch -n 1 'kubectl get pods -n guestbook -o wide'

# 2. Delete one pod
kubectl delete pod -n guestbook -l app=guestbook --field-selector=status.phase=Running --wait=false | head -1

# Or delete by name
POD=$(kubectl get pods -n guestbook -l app=guestbook -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod -n guestbook $POD
```

### Expected Behavior

| Time | Event |
|------|-------|
| T+0s | Pod enters `Terminating` state |
| T+1-5s | Rollout controller creates replacement pod |
| T+5-30s | New pod reaches `Running` state |
| T+30s | Pod terminates after graceful shutdown |

### Verification

```bash
# Check rollout status
kubectl get rollout -n guestbook guestbook

# Check events
kubectl get events -n guestbook --sort-by='.lastTimestamp' | tail -10

# Verify app still responds (if ingress configured)
curl -s https://guestbook.dev.yourdomain.com/health
```

---

## Scenario 2: Drain Node (Voluntary Disruption)

**Purpose:** Test PDB protection during node maintenance

**Risk:** Medium - affects all pods on node, but PDB-controlled

### Steps

```bash
# 1. Identify node with guestbook pods
kubectl get pods -n guestbook -o wide
NODE_TO_DRAIN=$(kubectl get pods -n guestbook -l app=guestbook -o jsonpath='{.items[0].spec.nodeName}')
echo "Will drain: $NODE_TO_DRAIN"

# 2. In separate terminals, watch:
# Terminal 1: Nodes
watch -n 2 'kubectl get nodes'

# Terminal 2: Pods
watch -n 2 'kubectl get pods -n guestbook -o wide'

# Terminal 3: PDB status
watch -n 2 'kubectl get pdb -n guestbook'

# 3. Drain the node (this respects PDBs)
kubectl drain $NODE_TO_DRAIN --ignore-daemonsets --delete-emptydir-data
```

### Expected Behavior

| Time | Event |
|------|-------|
| T+0s | Drain begins, node marked `SchedulingDisabled` |
| T+5s | Kubernetes checks PDB before each eviction |
| T+10s | First pod evicted (only 1 at a time due to PDB) |
| T+30s | Replacement pod scheduled on other node |
| T+45s | Replacement pod `Ready`, next eviction allowed |
| T+1-2m | All pods evicted, node fully drained |

### PDB in Action

```bash
# During drain, you'll see PDB blocking evictions:
kubectl get pdb -n guestbook
# NAME        MIN AVAILABLE   MAX UNAVAILABLE   CURRENT HEALTHY   DESIRED HEALTHY
# guestbook   2               N/A               2                 3

# If drain seems stuck, check why:
kubectl describe pdb guestbook -n guestbook
# Look for "Allowed disruptions: 0" - means PDB is blocking
```

### Restore Node

```bash
# Uncordon to allow scheduling again
kubectl uncordon $NODE_TO_DRAIN

# Verify node accepts workloads
kubectl get nodes
# Node should show Ready (no SchedulingDisabled)
```

---

## Scenario 3: Cordon + Delete Pods (Simulate Node Failure)

**Purpose:** Simulate involuntary failure without destroying infrastructure

**Risk:** Medium - pods rescheduled to remaining nodes

### Steps

```bash
# 1. Cordon node (prevent new scheduling)
NODE=$(kubectl get pods -n guestbook -l app=guestbook -o jsonpath='{.items[0].spec.nodeName}')
kubectl cordon $NODE

# 2. Delete pods on that node (simulates crash - no graceful eviction)
kubectl delete pods -n guestbook --field-selector spec.nodeName=$NODE --force --grace-period=0

# 3. Watch rescheduling
kubectl get pods -n guestbook -o wide -w
```

### Key Difference from Drain

- `kubectl drain`: Respects PDB, graceful termination
- `kubectl delete --force`: Ignores PDB, immediate termination (simulates crash)

### Cleanup

```bash
kubectl uncordon $NODE
```

---

## Scenario 4: Network Partition (Advanced)

**Purpose:** Test behavior when node loses API server connectivity

**Risk:** High - can cause stuck pods, use with caution

### Steps

```bash
# This requires SSH access to the node (not typical in managed EKS)
# Instead, use AWS FIS with network-disrupt action

# Verify node becomes NotReady
kubectl get nodes -w
# After ~40s of no heartbeat, node transitions to NotReady
# After ~5min, pods are evicted (pod-eviction-timeout)
```

**Recommendation:** Use [AWS FIS](./week15-fis-chaos-runbook.md) for network partition experiments.

---

## Monitoring Commands

### Real-time Dashboards

```bash
# All-in-one status
watch -n 2 '
echo "=== NODES ===" && kubectl get nodes && echo "" &&
echo "=== PODS ===" && kubectl get pods -n guestbook -o wide && echo "" &&
echo "=== PDB ===" && kubectl get pdb -n guestbook
'
```

### Check Karpenter Response

```bash
# Watch Karpenter provisioning
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller -f | grep -E 'provisioner|launched|terminated'

# Check NodeClaims
kubectl get nodeclaims -A
```

### CloudWatch Metrics

```bash
# Node count over time
aws cloudwatch get-metric-statistics \
  --namespace ContainerInsights \
  --metric-name node_count \
  --dimensions Name=ClusterName,Value=dev-eks-lab \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average
```

---

## Verification Checklist

After any node failure test:

- [ ] Application remained accessible (if multiple replicas)
- [ ] PDB was respected (for voluntary disruptions)
- [ ] Pods rescheduled to healthy nodes
- [ ] Karpenter provisioned replacement capacity (if needed)
- [ ] No data loss (check DynamoDB for guestbook entries)
- [ ] Events show expected sequence

```bash
# Quick health check
kubectl get nodes                          # All Ready
kubectl get pods -n guestbook              # All Running
kubectl get pdb -n guestbook               # CURRENT HEALTHY >= MIN AVAILABLE
kubectl get events -n guestbook --sort-by='.lastTimestamp' | tail -5
```

---

## Troubleshooting

### Drain Stuck / Hangs

**Symptom:** `kubectl drain` doesn't complete

**Cause:** PDB preventing eviction (no available disruptions)

**Resolution:**
```bash
# Check PDB status
kubectl get pdb -n guestbook
# If "Allowed disruptions: 0", wait for replacement pod to be Ready

# Check if pods are stuck
kubectl get pods -n guestbook -o wide
# Look for Pending pods - may need more node capacity

# Force drain (DANGER: ignores PDB - use only if necessary)
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --force
```

### Pods Stuck in Pending

**Symptom:** Replacement pods don't schedule

**Cause:** Insufficient cluster capacity

**Resolution:**
```bash
# Check pod events
kubectl describe pod <pending-pod> -n guestbook
# Look for: "0/2 nodes are available" or resource constraints

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller --tail=20

# Manual fix: uncordon a node or wait for Karpenter
kubectl uncordon <node-name>
```

### Pods Rescheduled to Same Node

**Symptom:** After failure, all pods land on single node

**Cause:** Missing topology spread constraints

**Resolution:** Add topology constraints to ensure spread:
```yaml
# In rollout.yaml spec.template.spec:
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: guestbook
```

---

## Related Documentation

- [AWS FIS Chaos Runbook](./week15-fis-chaos-runbook.md) - Automated experiments
- [PDB Configuration](../k8s/guestbook/pdb.yaml) - PodDisruptionBudget
- [Karpenter NodePool](../k8s/karpenter/nodepool.yaml) - Node provisioning
- [Kubernetes PDB Docs](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [EKS Best Practices - Reliability](https://aws.github.io/aws-eks-best-practices/reliability/docs/)
