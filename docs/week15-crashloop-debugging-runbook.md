# Week 15: Pod CrashLoop Debugging Runbook

## Overview

A CrashLoopBackOff means Kubernetes is repeatedly trying to start a pod that keeps failing. This runbook provides systematic debugging steps.

**Symptoms:**
- Pod status: `CrashLoopBackOff` or `Error`
- RESTARTS count increasing
- Pod cycles through: `Running` → `Error` → `CrashLoopBackOff`

---

## Quick Diagnosis

```bash
# 1. Identify the problem pod
kubectl get pods -n <namespace>
# Look for: CrashLoopBackOff, Error, or high RESTARTS count

# 2. Get pod details
kubectl describe pod <pod-name> -n <namespace>
# Key sections: Events, State, Last State

# 3. Check current logs
kubectl logs <pod-name> -n <namespace>

# 4. Check previous container logs (crashed instance)
kubectl logs <pod-name> -n <namespace> --previous
```

---

## CrashLoopBackOff Timing

Kubernetes uses exponential backoff for restart delays:

| Restart # | Delay |
|-----------|-------|
| 1 | 10s |
| 2 | 20s |
| 3 | 40s |
| 4 | 80s |
| 5+ | 300s (5 min cap) |

**Tip:** If you need to debug immediately, delete the pod to reset the backoff timer.

---

## Common Causes & Solutions

### 1. Application Error (Exit Code 1)

**Symptom:**
```
State:          Waiting
  Reason:       CrashLoopBackOff
Last State:     Terminated
  Reason:       Error
  Exit Code:    1
```

**Diagnosis:**
```bash
# Check application logs
kubectl logs <pod-name> -n <namespace> --previous

# Look for: stack traces, assertion errors, unhandled exceptions
```

**Common Causes:**
- Missing environment variables
- Invalid configuration
- Database connection failure
- Unhandled exception in startup code

**Resolution:**
```bash
# Check environment variables
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].env}' | jq

# Check configmaps/secrets exist
kubectl get configmap -n <namespace>
kubectl get secrets -n <namespace>

# Verify secret has expected keys
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data}' | jq 'keys'
```

---

### 2. OOMKilled (Exit Code 137)

**Symptom:**
```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

**Diagnosis:**
```bash
# Check memory limits vs actual usage
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Limits:"

# Check container metrics (if Container Insights enabled)
kubectl top pod <pod-name> -n <namespace>
```

**Resolution:**

Option A: Increase memory limit
```yaml
resources:
  limits:
    memory: "512Mi"  # Increase from 256Mi
  requests:
    memory: "256Mi"
```

Option B: Fix memory leak in application
```bash
# Check logs for memory-related errors before OOM
kubectl logs <pod-name> -n <namespace> --previous | tail -100
```

---

### 3. Liveness Probe Failure (Exit Code 137)

**Symptom:**
```
Events:
  Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 503
  Normal   Killing    Container failed liveness probe, will be restarted
```

**Diagnosis:**
```bash
# Check probe configuration
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].livenessProbe}' | jq

# Test probe endpoint manually
kubectl exec <pod-name> -n <namespace> -- curl -s localhost:8080/health
```

**Common Causes:**
- Probe timeout too short
- initialDelaySeconds too short (app not ready)
- Health endpoint has bug
- Dependency health check failing

**Resolution:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30  # Give app time to start
  periodSeconds: 10
  timeoutSeconds: 5        # Increase if health check is slow
  failureThreshold: 3      # Allow some failures
```

---

### 4. Image Pull Errors

**Symptom:**
```
State:          Waiting
  Reason:       ImagePullBackOff
Events:
  Warning  Failed   Failed to pull image "123456789.dkr.ecr...": not found
```

**Diagnosis:**
```bash
# Check image exists
aws ecr describe-images --repository-name <repo> --image-ids imageTag=<tag>

# Check pull secret exists
kubectl get secret -n <namespace> | grep regcred

# Verify service account has ECR access
kubectl get serviceaccount <sa-name> -n <namespace> -o yaml
```

**Common Causes:**
- Image tag doesn't exist
- ECR repository in different region
- Missing or expired pull credentials
- IRSA not configured correctly

**Resolution:**
```bash
# For ECR with IRSA, verify pod identity
kubectl describe pod <pod-name> -n <namespace> | grep -A3 "Service Account"

# Test ECR access from pod (if running)
kubectl exec <pod-name> -n <namespace> -- aws ecr get-login-password --region us-east-1
```

---

### 5. ConfigMap/Secret Not Found

**Symptom:**
```
Events:
  Warning  Failed  Error: configmap "app-config" not found
```

**Diagnosis:**
```bash
# List configmaps in namespace
kubectl get configmap -n <namespace>

# Check if referenced in pod spec
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A10 "configMapRef\|secretRef"
```

**Resolution:**
```bash
# Create missing configmap
kubectl create configmap app-config -n <namespace> --from-literal=key=value

# Or sync via External Secrets
kubectl get externalsecret -n <namespace>
kubectl describe externalsecret <name> -n <namespace>
```

---

### 6. Volume Mount Failure

**Symptom:**
```
Events:
  Warning  FailedMount  Unable to attach or mount volumes
```

**Diagnosis:**
```bash
# Check PVC status
kubectl get pvc -n <namespace>

# Check PV binding
kubectl get pv

# Check storage class
kubectl get storageclass
```

**Common Causes:**
- PVC pending (no PV available)
- EBS volume in different AZ than node
- EBS CSI driver not installed

**Resolution:**
```bash
# Check EBS CSI driver
kubectl get pods -n kube-system | grep ebs-csi

# Check PVC events
kubectl describe pvc <pvc-name> -n <namespace>
```

---

### 7. Insufficient Resources

**Symptom:**
```
Events:
  Warning  FailedScheduling  0/3 nodes are available: 3 Insufficient memory
```

**Diagnosis:**
```bash
# Check node capacity
kubectl describe nodes | grep -A5 "Allocated resources"

# Check pending pods
kubectl get pods -A | grep Pending
```

**Resolution:**
```bash
# Option 1: Reduce resource requests
# Option 2: Wait for Karpenter to scale

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller --tail=20
```

---

## Debug Workflow

### Step 1: Gather Information

```bash
NAMESPACE=guestbook
POD=<pod-name>

# Comprehensive info dump
echo "=== POD STATUS ===" && kubectl get pod $POD -n $NAMESPACE -o wide
echo ""
echo "=== DESCRIBE ===" && kubectl describe pod $POD -n $NAMESPACE
echo ""
echo "=== CURRENT LOGS ===" && kubectl logs $POD -n $NAMESPACE --tail=50 2>/dev/null || echo "No current logs"
echo ""
echo "=== PREVIOUS LOGS ===" && kubectl logs $POD -n $NAMESPACE --previous --tail=50 2>/dev/null || echo "No previous logs"
```

### Step 2: Check Exit Code

| Exit Code | Meaning | Common Cause |
|-----------|---------|--------------|
| 0 | Success | Completed job (shouldn't restart) |
| 1 | Application error | Unhandled exception, assertion |
| 137 | SIGKILL (128+9) | OOMKilled or liveness probe |
| 143 | SIGTERM (128+15) | Graceful shutdown |
| 255 | Exit status out of range | Invalid exit code from app |

### Step 3: Interactive Debugging

```bash
# Override entrypoint to keep container running
kubectl run debug-pod -n <namespace> --rm -it \
  --image=<same-image> \
  --overrides='{"spec":{"containers":[{"name":"debug","image":"<image>","command":["sleep","3600"]}]}}'

# Then exec in and test manually
kubectl exec -it debug-pod -n <namespace> -- /bin/sh
```

### Step 4: Check Dependencies

```bash
# Test database connectivity
kubectl exec <pod-name> -n <namespace> -- nc -zv <db-host> <port>

# Test secrets availability
kubectl exec <pod-name> -n <namespace> -- printenv | grep -i password

# Test DNS resolution
kubectl exec <pod-name> -n <namespace> -- nslookup kubernetes.default
```

---

## Guestbook-Specific Checks

```bash
# Check DynamoDB connectivity
kubectl exec -n guestbook <pod> -- aws dynamodb list-tables --region us-east-1

# Check external secret sync
kubectl get externalsecret -n guestbook
kubectl describe externalsecret guestbook-secret -n guestbook

# Check IRSA configuration
kubectl get serviceaccount guestbook -n guestbook -o yaml | grep eks.amazonaws.com

# Verify Kyverno isn't blocking
kubectl get policyreport -A
```

---

## Prevention

### Resource Limits
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"  # 2x request as buffer
    cpu: "500m"
```

### Probe Configuration
```yaml
startupProbe:           # For slow-starting apps
  httpGet:
    path: /health
    port: 8080
  failureThreshold: 30  # 30 * 10s = 5 min to start
  periodSeconds: 10

livenessProbe:          # After startup
  httpGet:
    path: /health
    port: 8080
  periodSeconds: 10
  failureThreshold: 3
```

### Graceful Shutdown
```yaml
spec:
  terminationGracePeriodSeconds: 30
  containers:
  - name: app
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "sleep 5"]  # Allow LB to drain
```

---

## Related Documentation

- [Node Failure Runbook](./week15-node-failure-runbook.md)
- [AWS FIS Chaos Runbook](./week15-fis-chaos-runbook.md)
- [Kubernetes Debugging](https://kubernetes.io/docs/tasks/debug/debug-application/)
- [EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
