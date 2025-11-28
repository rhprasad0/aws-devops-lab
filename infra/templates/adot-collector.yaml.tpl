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
            - job_name: 'kubernetes-pods'
              kubernetes_sd_configs:
              - role: pod
              relabel_configs:
              - action: keep
                regex: true
                source_labels:
                - __meta_kubernetes_pod_annotation_prometheus_io_scrape
              - action: replace
                regex: (.+)
                source_labels:
                - __meta_kubernetes_pod_annotation_prometheus_io_path
                target_label: __metrics_path__
              - action: replace
                regex: ([^:]+)(?::\d+)?;(\d+)
                replacement: $1:$2
                source_labels:
                - __address__
                - __meta_kubernetes_pod_annotation_prometheus_io_port
                target_label: __address__
              - action: labelmap
                regex: __meta_kubernetes_pod_label_(.+)
                replacement: $1
              - action: replace
                source_labels:
                - __meta_kubernetes_namespace
                target_label: kubernetes_namespace
              - action: replace
                source_labels:
                - __meta_kubernetes_pod_name
                target_label: kubernetes_pod_name

    exporters:
      prometheusremotewrite:
        endpoint: "${AMP_ENDPOINT}"
        auth:
          sigv4:
            region: "${REGION}"

    service:
      pipelines:
        metrics:
          receivers: [prometheus]
          exporters: [prometheusremotewrite]
