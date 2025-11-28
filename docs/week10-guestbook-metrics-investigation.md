# Week 10: Guestbook Application Metrics - Investigation Notes

## Goal
Configure ADOT (AWS Distro for OpenTelemetry) to scrape custom application metrics from the guestbook application's `/metrics` endpoint and display them in the Grafana dashboard.

## Current Status
- **Container metrics (CPU, Memory)**: ✅ Working - scraped via cAdvisor
- **Application metrics (http_requests_total, etc.)**: ❌ Not appearing in Prometheus/Grafana
- **Pod Discovery**: ✅ Working - guestbook pods ARE being discovered
- **Address Construction**: ❌ BLOCKED - `__address__` label not being set correctly

---

## 🚧 CURRENT BLOCKER: Relabel Config Not Setting `__address__`

### Symptom
ADOT collector logs show guestbook pods being discovered, but the `instance` label is `":"` instead of `"10.x.x.x:8000"`:

```
target_labels: "{..., instance=\":\", namespace=\"guestbook\", pod=\"guestbook-79476f8967-fshct\", ...}"
```

### What We've Proven Works
1. ✅ Pod discovery via `kubernetes_sd_configs` with `role: pod`
2. ✅ Filtering pods with `prometheus.io/scrape=true` annotation
3. ✅ `__meta_kubernetes_pod_ip` contains correct IP (e.g., `10.0.12.23`)
4. ✅ `prometheus.io/port` annotation contains correct port (`8000`)
5. ✅ RBAC permissions allow listing pods in all namespaces
6. ✅ Guestbook `/metrics` endpoint is accessible and returns valid Prometheus metrics

### What Doesn't Work
The relabel rule to combine pod IP + port into `__address__` fails silently. Multiple approaches attempted:

### Attempted Solutions

| Attempt | Approach | Config | Result |
|---------|----------|--------|--------|
| 1 | Two-step with `__tmp_pod_ip` | Extract IP to temp label, then combine | `instance=":"` |
| 2 | Single regex rule | `regex: ([^:]+):[0-9]+;([0-9]+)` | `instance=":"` |
| 3 | Direct `__meta_kubernetes_pod_ip` | Skip `__address__` parsing | `instance=":"` |
| 4 | Debug labels | Added `debug_pod_ip` and `debug_port` | **Values present!** |
| 5 | Separator approach | Use `separator: ':'` instead of regex | `instance=":"` |
| 6 | `${1}:${2}` replacement syntax | Terraform escaped braces | `instance=":"` |
| 7 | `$1:$2` replacement syntax | Go regex style without braces | `instance=":"` |

### Debug Evidence
With debug labels added, logs show the source values ARE populated:
```
debug_pod_ip="10.0.11.31", debug_port="8000", instance=":"
```

This proves:
- The meta labels have correct values
- The `replace` action with `regex: (.+);(.+)` is NOT matching
- Something about the replacement rule is failing silently

### Current Config (Latest Attempt)
```yaml
relabel_configs:
  # Keep only pods with prometheus.io/scrape=true
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: "true"
  # Set metrics path from annotation
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
    action: replace
    target_label: __metrics_path__
    regex: (.+)
  # Construct address from pod IP + annotation port
  - source_labels: [__meta_kubernetes_pod_ip, __meta_kubernetes_pod_annotation_prometheus_io_port]
    action: replace
    regex: "(.+);(.+)"
    replacement: $1:$2
    target_label: __address__
```

**Result**: Still produces `instance=":"` - the replacement is not executing.

### Theories

1. **ADOT/OTel Prometheus Receiver quirk** - The Prometheus receiver in ADOT v0.36.0 may handle relabel configs differently than vanilla Prometheus. This is the **most likely cause** given all syntax variants have failed.

2. **YAML parsing issue** - The config is inside a YAML block string (`config: |`), which may affect how special characters are interpreted. However, we verified the config is correctly applied to the cluster.

3. **Order of operations** - The `__address__` label may be getting reset somewhere after our relabel rules run.

4. **Regex engine differences** - OTel may use a different regex engine than Prometheus.

5. **`__meta_*` labels not available for replacement target** - The OTel receiver may not expose `__meta_kubernetes_pod_ip` at the stage where `__address__` is constructed.

### Key Finding
The ADOT collector is using image `public.ecr.aws/aws-observability/aws-otel-collector:v0.36.0`. Multiple regex/replacement syntaxes have been tested (`${1}:${2}`, `$1:$2`, separator approach) and **none work**. This strongly suggests a bug or limitation in the OTel Prometheus receiver's relabel config implementation.

---

## What Was Accomplished

### 1. Grafana Dashboard Created
- **File**: `dashboards/guestbook-app.json`
- **Panels**:
  | Panel | Query | Status |
  |-------|-------|--------|
  | HTTP Request Rate | `sum(rate(http_requests_total{namespace="guestbook"}[5m])) by (handler, status)` | ❌ No data |
  | Guestbook Memory Usage | `sum(container_memory_working_set_bytes{namespace="guestbook"}) by (pod)` | ✅ Working |
  | Guestbook CPU Usage | `sum(rate(container_cpu_usage_seconds_total{namespace="guestbook"}[5m])) by (pod)` | ✅ Working |

### 2. Guestbook Application Metrics Verified
The guestbook app exposes Prometheus metrics at `http://pod-ip:8000/metrics`:

```bash
# Verified via port-forward:
kubectl port-forward -n guestbook svc/guestbook 8080:80
curl http://localhost:8080/metrics

# Key metrics available:
- http_requests_total{handler, method, status}
- http_request_duration_highr_seconds (histogram)
- http_request_size_bytes
- http_response_size_bytes
- process_cpu_seconds_total
- process_resident_memory_bytes
- python_gc_* (Python runtime metrics)
```

### 3. Pod Annotations Verified
Guestbook pods have correct Prometheus scrape annotations:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8000"
  prometheus.io/path: "/metrics"
```

### 4. RBAC Verified
```bash
$ kubectl auth can-i list pods --namespace=guestbook \
    --as=system:serviceaccount:opentelemetry-operator-system:adot-collector
yes
```

---

## Next Steps to Try

### 1. ~~Check if separator approach works~~ ❌ FAILED
Tested - still produces `instance=":"`.

### 2. Try static_configs as workaround (RECOMMENDED NEXT)
Hardcode guestbook pod IPs temporarily to prove scraping works.
Current pod IPs (as of 2025-11-28):
```yaml
- job_name: 'guestbook-static'
  metrics_path: /metrics
  static_configs:
  - targets: ['10.0.12.23:8000', '10.0.11.31:8000', '10.0.12.151:8000']
    labels:
      namespace: guestbook
      app: guestbook
```
**Purpose**: If this works, it proves the scraping mechanism is fine and the issue is purely with relabel_configs.

### 3. Switch to Prometheus Operator with PodMonitor
Use CRDs instead of annotation-based discovery:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: guestbook
  namespace: guestbook
spec:
  selector:
    matchLabels:
      app: guestbook
  podMetricsEndpoints:
  - port: http
    path: /metrics
```

### 4. Try kube-prometheus-stack Helm chart
Replace ADOT's Prometheus receiver with a dedicated Prometheus server that has proven relabel config support.

### 5. Open GitHub issue on ADOT
If separator approach fails, this may be a bug in the ADOT Prometheus receiver.

---

## Verification Commands

```bash
# Check ADOT collector logs for scrape attempts
kubectl logs -n opentelemetry-operator-system -l app.kubernetes.io/name=adot-collector-collector --since=2m | grep guestbook

# Check if instance label is now correct
kubectl logs -n opentelemetry-operator-system -l app.kubernetes.io/name=adot-collector-collector --since=1m | grep "instance="

# Verify guestbook metrics endpoint works
kubectl port-forward -n guestbook svc/guestbook 8080:80
curl http://localhost:8080/metrics

# Check pod annotations
kubectl get pod -n guestbook -o jsonpath='{.items[0].metadata.annotations}'

# Check current ADOT config
kubectl get OpenTelemetryCollector -n opentelemetry-operator-system adot-collector -o jsonpath='{.spec.config}' | grep -A15 relabel

# Force sync ArgoCD
kubectl annotate application adot-collector -n argocd argocd.argoproj.io/refresh=hard --overwrite

# Restart collector pod to pick up new config
kubectl delete pod -n opentelemetry-operator-system -l app.kubernetes.io/name=adot-collector-collector
```

---

## Files Modified

| File | Description |
|------|-------------|
| `dashboards/guestbook-app.json` | Grafana dashboard JSON with 3 panels |
| `infra/templates/adot-collector.yaml.tpl` | ADOT collector configuration template |
| `k8s/adot/collector.yaml` | Generated collector manifest (via Terraform) |

---

## References

- [ADOT Prometheus Receiver](https://aws-otel.github.io/docs/components/prometheus-receiver)
- [Prometheus Kubernetes SD Config](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config)
- [OpenTelemetry Collector Configuration](https://opentelemetry.io/docs/collector/configuration/)
- [Prometheus Relabel Config](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config)

