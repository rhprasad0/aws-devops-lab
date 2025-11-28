apiVersion: v1
kind: ServiceAccount
metadata:
  name: adot-collector
  namespace: opentelemetry-operator-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: adot-collector
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/proxy", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["non-resource-urls"]
  resources: ["/metrics"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: adot-collector
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: adot-collector
subjects:
- kind: ServiceAccount
  name: adot-collector
  namespace: opentelemetry-operator-system
---
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: adot-collector
  namespace: opentelemetry-operator-system
spec:
  mode: deployment
  serviceAccount: adot-collector
  config: |
    receivers:
      prometheus:
        config:
          global:
            scrape_interval: 60s
          scrape_configs:
            # Kubernetes pod discovery - scrapes pods with prometheus.io/scrape=true annotation
            - job_name: 'kubernetes-pods'
              kubernetes_sd_configs:
              - role: pod
              relabel_configs:
              # Keep only pods with prometheus.io/scrape=true
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                action: keep
                regex: "true"
              # Set metrics path from annotation (default: /metrics)
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
                action: replace
                target_label: __metrics_path__
                regex: (.+)
              # Build __address__ from pod IP and annotation port
              # First, set a debug label to see what values we have
              - source_labels: [__meta_kubernetes_pod_ip]
                action: replace
                target_label: __tmp_pod_ip
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
                action: replace
                target_label: __tmp_port
              # Construct address: pod_ip:port
              - source_labels: [__tmp_pod_ip, __tmp_port]
                action: replace
                regex: (.+);(.+)
                replacement: $1:$2
                target_label: __address__
              # Copy pod labels to metric labels
              - action: labelmap
                regex: __meta_kubernetes_pod_label_(.+)
              # Add namespace and pod name as labels for easier querying
              - source_labels: [__meta_kubernetes_namespace]
                action: replace
                target_label: namespace
              - source_labels: [__meta_kubernetes_pod_name]
                action: replace
                target_label: pod
              # Debug: expose the tmp labels to see what's happening
              - source_labels: [__tmp_pod_ip]
                action: replace
                target_label: debug_pod_ip
              - source_labels: [__tmp_port]
                action: replace
                target_label: debug_port

    extensions:
      sigv4auth:
        region: "${REGION}"
        service: "aps"

    exporters:
      prometheusremotewrite:
        endpoint: "${AMP_ENDPOINT}"
        auth:
          authenticator: sigv4auth

    service:
      extensions: [sigv4auth]
      pipelines:
        metrics:
          receivers: [prometheus]
          exporters: [prometheusremotewrite]
