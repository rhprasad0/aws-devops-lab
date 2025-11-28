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
            # Kubernetes pod discovery with Endpoints role (more reliable for address construction)
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
              # WORKAROUND: Use replacement with regex capture groups
              # The OTel prometheus receiver requires explicit regex even for simple copies
              - source_labels: [__meta_kubernetes_pod_ip, __meta_kubernetes_pod_annotation_prometheus_io_port]
                action: replace
                regex: "(.+);(.+)"
                replacement: "$${1}:$${2}"
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
