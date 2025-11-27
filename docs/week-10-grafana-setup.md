# Week 10: AWS Managed Grafana Setup Guide

This guide covers the setup of Amazon Managed Grafana (AMG) for visualizing metrics from Amazon Managed Prometheus (AMP).

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  EKS Cluster    │────▶│  AMP Scraper    │────▶│  AMP Workspace  │
│  (Pods/Nodes)   │     │  (Agentless)    │     │  (Prometheus)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
                        ┌─────────────────┐     ┌─────────────────┐
                        │  You (Browser)  │◀────│ Amazon Managed  │
                        │  via SSO Login  │     │    Grafana      │
                        └─────────────────┘     └─────────────────┘
```

## Prerequisites

### 1. Enable IAM Identity Center (One-Time Setup)

AWS Managed Grafana uses IAM Identity Center (formerly AWS SSO) for authentication. This must be enabled before deploying Grafana.

**Steps:**

1. Go to [AWS IAM Identity Center Console](https://console.aws.amazon.com/singlesignon/)

2. Click **Enable** if not already enabled
   - Choose **Enable with AWS Organizations** (recommended) or **Enable only in this account**
   - For this lab, "Enable only in this account" is simpler

3. Choose your **Identity source**:
   - **Identity Center directory** (recommended for lab) - Built-in user management
   - **Active Directory** - For existing AD integration
   - **External identity provider** - For Okta, Azure AD, etc.

4. Wait for setup to complete (usually 1-2 minutes)

### 2. Create an IAM Identity Center User

1. In IAM Identity Center console, go to **Users** → **Add user**

2. Fill in the user details:
   - **Username**: Your email or preferred username
   - **Email address**: Your email (required for verification)
   - **First name**: Your first name
   - **Last name**: Your last name

3. Click **Next** → **Add user**

4. Check your email for the verification link and set your password

### 3. Deploy the Grafana Infrastructure

After IAM Identity Center is enabled, deploy the Terraform:

```bash
cd infra
terraform init
terraform plan
terraform apply
```

The Terraform will create:
- IAM role for Grafana workspace
- Amazon Managed Grafana workspace
- Service account for API access
- IAM policies for AMP and CloudWatch access

### 4. Assign User to Grafana Workspace

After Terraform completes:

1. Go to [Amazon Managed Grafana Console](https://console.aws.amazon.com/grafana/)

2. Click on your workspace (`dev-grafana`)

3. Go to **Authentication** tab

4. Under **AWS IAM Identity Center**, click **Assign new user or group**

5. Select your IAM Identity Center user

6. Choose role: **Admin** (for full access) or **Editor** (for dashboard editing)

7. Click **Assign users and groups**

## Accessing Grafana

### Sign In

1. Get your Grafana URL from Terraform output:
   ```bash
   terraform output grafana_workspace_endpoint
   ```

2. Open the URL in your browser

3. Click **Sign in with AWS IAM Identity Center**

4. Enter your IAM Identity Center credentials

### Configure Prometheus Data Source

Two options:

#### Option A: Using AWS Data Source Configuration (Recommended)

1. In AWS Console: **Amazon Managed Grafana** → Your workspace

2. Go to **Data sources** tab

3. Select **Amazon Managed Service for Prometheus**

4. Click **Actions** → **Enable service-managed policy**

5. Click **Configure in Grafana**

6. In Grafana workspace:
   - Click the **AWS icon** (sidebar)
   - Select **AWS services** → **Prometheus**
   - Choose your region
   - Select your AMP workspace
   - Click **Add data source**

#### Option B: Manual Configuration

1. In Grafana, go to **Connections** → **Data Sources** → **Add data source**

2. Select **Prometheus**

3. Configure:
   - **Name**: Amazon Managed Prometheus
   - **URL**: `<your-amp-prometheus-endpoint>` (from Terraform output)
   - **Auth**: Toggle **SigV4 auth** ON
   - **SigV4 Auth Details**:
     - **Authentication Provider**: AWS SDK Default
     - **Default Region**: us-east-1 (or your region)

4. Click **Save & Test**

## Import Kubernetes Dashboards

1. Go to **Dashboards** → **Import**

2. Import by ID:

   | Dashboard ID | Name | Description |
   |--------------|------|-------------|
   | 315 | Kubernetes cluster monitoring | Overview of cluster health |
   | 6417 | Kubernetes Pods | Pod-level metrics |
   | 13770 | Kube-state-metrics v2 | Deployment/ReplicaSet status |
   | 12006 | Kubernetes apiserver | API server performance |

3. Select **Amazon Managed Prometheus** as the data source

## Useful PromQL Queries

### Cluster Health
```promql
# All scrape targets
up{}

# Node count
count(kube_node_info)

# Pod count by namespace
count by (namespace) (kube_pod_info)
```

### Resource Usage
```promql
# CPU usage by namespace (5m rate)
sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))

# Memory usage by namespace
sum by (namespace) (container_memory_working_set_bytes{container!=""})

# Pod restarts in last hour
sum by (namespace) (increase(kube_pod_container_status_restarts_total[1h]))
```

### Application Metrics
```promql
# Request rate (if app exposes metrics)
rate(http_requests_total[5m])

# Request latency percentiles
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

## Cost Considerations

### Amazon Managed Grafana Pricing
- **Editor/Admin users**: $9/user/month
- **Viewer users**: $5/user/month
- **First user is included** in workspace cost

### Cost Optimization Tips
1. Use **Viewer** role for team members who only need to view dashboards
2. Consider **shared workspace** for multiple environments (use folders/namespaces)
3. Delete workspace when not in use (Terraform destroy)

## Troubleshooting

### "Access Denied" when signing in
- Ensure user is assigned to the workspace in AWS Console
- Verify IAM Identity Center user is active (not pending verification)

### Data source connection failed
- Check IAM role has correct AMP permissions
- Verify SigV4 auth is enabled
- Ensure region is correct

### No metrics showing
- Check AMP scraper is running: `terraform output amp_workspace_id`
- Verify pods are exporting metrics on `/metrics` endpoint
- Wait a few minutes for initial scrape to complete

## Security Notes

1. **Authentication**: All access goes through IAM Identity Center - no shared passwords
2. **Authorization**: Use Grafana roles (Admin/Editor/Viewer) to control access
3. **Network**: Grafana workspace is public but requires IAM Identity Center auth
4. **Data access**: IAM policies scope Prometheus queries to your workspace only

## Clean Up

To remove Grafana resources:

```bash
cd infra
terraform destroy -target=aws_grafana_workspace.main
```

Or destroy everything:

```bash
make down
```

## References

- [Amazon Managed Grafana User Guide](https://docs.aws.amazon.com/grafana/latest/userguide/)
- [Adding AMP as Data Source](https://docs.aws.amazon.com/grafana/latest/userguide/AMP-adding-AWS-config.html)
- [IAM Identity Center User Guide](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [Grafana Dashboard Gallery](https://grafana.com/grafana/dashboards/)

