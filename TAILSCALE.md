# Tailscale Subnet Router for EKS Private Access

## Overview
Tailscale subnet router advertises your VPC routes to your Tailscale network, enabling direct kubectl access to private EKS endpoints without SSH proxying.

**Cost:** ~$7/month (t3.micro instance) + $0 (Tailscale free tier)

## Prerequisites
- Tailscale account (free at https://tailscale.com)
- EKS cluster deployed (Week 2 complete)

## Step 1: Get Tailscale Auth Key

1. Visit https://login.tailscale.com/admin/settings/keys
2. Click **Generate auth key**
3. Settings:
   - **Reusable:** Yes (for infrastructure)
   - **Ephemeral:** Yes (auto-cleanup when offline)
   - **Preauthorized:** Yes
4. Copy the key (starts with `tskey-auth-`)

## Step 2: Deploy Tailscale Subnet Router

```bash
# Set environment variables
export TF_VAR_enable_tailscale=true
export TF_VAR_tailscale_auth_key="tskey-auth-xxxxx"

# Deploy infrastructure
cd infra
terraform apply

# Note the instance ID from output
```

## Step 3: Install Tailscale on Your Device

### macOS
```bash
brew install tailscale
sudo tailscale up --accept-routes
```

### Linux (Ubuntu/Debian)
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --accept-routes
```

### Windows
1. Download from https://tailscale.com/download/windows
2. Install and run: `tailscale up --accept-routes`

## Step 4: Approve Subnet Routes

1. Go to https://login.tailscale.com/admin/machines
2. Find "eks-gateway" machine
3. In "Subnet routes" section, **approve** `10.0.0.0/16`

## Step 5: Test Direct kubectl Access

```bash
# Check Tailscale network status
tailscale status
# Should show eks-gateway and route acceptance

# Make EKS private-only (optional but recommended)
export TF_VAR_eks_private_only=true
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name dev-eks --region us-east-1

# Test direct access via Tailscale routing
kubectl get nodes
kubectl get pods -A
```

## How It Works

1. **Subnet Router**: EC2 instance advertises VPC CIDR (`10.0.0.0/16`) to Tailscale
2. **Route Acceptance**: Your device accepts routes from the subnet router
3. **Direct Access**: kubectl traffic routes through Tailscale to private EKS endpoint
4. **No SSH**: No need to SSH into instances or port forwarding

## Troubleshooting

### Routes Not Working
```bash
# Check local Tailscale status
tailscale status
# Look for "Some peers are advertising routes but --accept-routes is false"

# Enable route acceptance
sudo tailscale up --accept-routes
```

### Subnet Router Not Advertising
```bash
# Check instance logs
aws ssm start-session --target $(terraform output -raw tailscale_subnet_router_id)
sudo tailscale status
sudo journalctl -u tailscaled -f
```

### kubectl Connection Timeout
```bash
# Verify EKS endpoint is reachable via Tailscale
ping $(terraform output -raw tailscale_subnet_router_ip)
curl -k https://PRIVATE-EKS-ENDPOINT:443
```

### Routes Not Approved
- Go to Tailscale admin console → Machines
- Find "eks-gateway" 
- Manually approve the `10.0.0.0/16` subnet route

## Security Benefits

- **Private EKS endpoint** - No public internet exposure
- **Zero-trust networking** - Device authentication required  
- **Encrypted mesh** - All traffic encrypted via WireGuard
- **Audit trail** - All connections logged in Tailscale admin
- **No SSH keys** - No bastion host management needed

## Cleanup

```bash
# Disable Tailscale subnet router
export TF_VAR_enable_tailscale=false
terraform apply

# Remove device from Tailscale network (optional)
tailscale logout
```

## Next Steps

- **Week 4:** Add AWS Load Balancer Controller (works with private EKS)
- **Production:** Consider AWS Client VPN for team access
- **Advanced:** Multiple subnet routers for HA
