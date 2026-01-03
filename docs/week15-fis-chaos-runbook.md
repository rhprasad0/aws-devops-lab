# Week 15: AWS FIS Chaos Engineering Runbook

## Overview

This runbook documents the AWS Fault Injection Simulator (FIS) experiment for testing application resilience during node failures.

**Experiment:** Terminate one EKS worker node
**Purpose:** Validate that PodDisruptionBudgets and Kubernetes self-healing work correctly
**Risk Level:** Low (controlled single-node failure)
**Cost:** ~$0.01 per experiment run

---

## Prerequisites

Before running the experiment, verify:

1. **Cluster is healthy**
   ```bash
   kubectl get nodes
   # All nodes should be Ready

   kubectl get pods -n guestbook
   # All pods should be Running (expect 3 replicas)
   ```

2. **PDB is configured**
   ```bash
   kubectl get pdb -n guestbook
   # Should show: guestbook  N/A  2  3  0
   ```

3. **FIS infrastructure is deployed**
   ```bash
   cd infra && terraform apply
   # Verify fis.tf resources are created
   ```

4. **Multiple nodes available**
   ```bash
   kubectl get nodes
   # Need at least 2 nodes for pods to reschedule
   ```

---

## Running the Experiment

### Step 1: Get the Experiment Template ID

```bash
# From Terraform output
cd /workspaces/aws-devops-lab/infra
terraform output fis_experiment_template_id

# Or via AWS CLI
aws fis list-experiment-templates --query 'experimentTemplates[?tags.Component==`chaos-engineering`].id' --output text
```

### Step 2: Start the Experiment

```bash
# Replace TEMPLATE_ID with the actual ID
aws fis start-experiment \
  --experiment-template-id TEMPLATE_ID \
  --tags Name=manual-test-$(date +%Y%m%d-%H%M%S)
```

Save the returned `experimentId` for monitoring.

### Step 3: Monitor the Experiment

**Watch nodes:**
```bash
# In a separate terminal
watch -n 2 'kubectl get nodes'
```

**Watch pods:**
```bash
# In another terminal
watch -n 2 'kubectl get pods -n guestbook -o wide'
```

**Watch experiment status:**
```bash
aws fis get-experiment --id EXPERIMENT_ID --query 'experiment.state'
```

### Step 4: Check Experiment Logs

```bash
# View FIS logs in CloudWatch
aws logs tail /aws/fis/dev-experiments --follow
```

---

## Expected Behavior

| Time | What Happens |
|------|--------------|
| T+0s | FIS initiates EC2 termination |
| T+30s | Node enters `NotReady` state |
| T+60s | Kubernetes begins pod eviction |
| T+90s | Pods reschedule to remaining node(s) |
| T+2-5m | EKS Auto Scaling or Karpenter provisions new node |
| T+5-10m | New node joins cluster, pods rebalance |

### Key Observations

1. **PDB Protection**: Only 1 guestbook pod should be disrupted at a time (minAvailable: 2)
2. **Service Continuity**: Guestbook app should remain accessible throughout
3. **Node Replacement**: Karpenter (or ASG) should provision a replacement node

---

## Verification Checklist

After the experiment:

- [ ] Application remained accessible during disruption
- [ ] At least 2 guestbook pods were running at all times
- [ ] New node was provisioned automatically
- [ ] Pods rescheduled successfully
- [ ] No data loss (check DynamoDB entries)

```bash
# Verify app is accessible
curl -k https://guestbook.dev.yourdomain.com/health

# Check PDB was respected
kubectl describe pdb guestbook -n guestbook

# Check events for any issues
kubectl get events -n guestbook --sort-by='.lastTimestamp' | tail -20
```

---

## Troubleshooting

### Pods Stuck in Pending

**Symptom:** Pods don't reschedule to other nodes

**Possible Causes:**
- No nodes with available capacity
- Taints preventing scheduling
- Resource requests too high

**Resolution:**
```bash
kubectl describe pod <pod-name> -n guestbook
# Check Events section for scheduling failures
```

### PDB Violation

**Symptom:** More than 1 pod disrupted simultaneously

**Possible Causes:**
- PDB selector doesn't match pods
- Multiple simultaneous disruptions

**Resolution:**
```bash
kubectl describe pdb guestbook -n guestbook
# Verify Selector matches pod labels
```

### Node Not Replaced

**Symptom:** Cluster stays at reduced capacity

**Possible Causes:**
- Karpenter not running
- ASG min/max limits reached
- IAM permission issues

**Resolution:**
```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller --tail=50

# Check ASG
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity,MinSize,MaxSize]'
```

---

## Stopping the Experiment

If something goes wrong:

```bash
# Stop immediately
aws fis stop-experiment --id EXPERIMENT_ID

# Verify stopped
aws fis get-experiment --id EXPERIMENT_ID --query 'experiment.state'
```

---

## Post-Experiment Cleanup

The experiment is self-cleaning (node termination is the only action). Verify cluster health:

```bash
# Wait for new node to be ready
kubectl get nodes -w

# Verify all pods healthy
kubectl get pods -n guestbook

# Check Karpenter provisioned new capacity
kubectl get nodeclaims -A
```

---

## Cost Estimate

| Component | Cost |
|-----------|------|
| FIS experiment | ~$0.01/run |
| Node replacement | ~$0.02/hr (t4g.medium) |
| CloudWatch logs | ~$0.01/experiment |
| **Total per experiment** | **~$0.05** |

---

## Related Documentation

- [PDB Configuration](../k8s/guestbook/pdb.yaml)
- [Karpenter NodePool](../k8s/karpenter/nodepool.yaml)
- [AWS FIS User Guide](https://docs.aws.amazon.com/fis/latest/userguide/)
