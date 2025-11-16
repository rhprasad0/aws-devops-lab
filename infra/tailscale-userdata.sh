#!/bin/bash
# Tailscale Gateway Setup Script

# Update system
dnf update -y

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Start and join Tailscale network with subnet routing
systemctl enable --now tailscaled

# Get VPC CIDR for route advertisement
VPC_CIDR=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -s http://169.254.169.254/latest/meta-data/mac)/vpc-ipv4-cidr-block)

# Join Tailscale and advertise VPC routes
tailscale up --authkey=${tailscale_auth_key} --hostname=eks-gateway --advertise-routes=$VPC_CIDR --accept-routes

# Enable IP forwarding for subnet routing
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
sysctl -p

# Install useful tools for monitoring
dnf install -y git htop

# Create welcome message
cat > /etc/motd << 'EOF'
=================================
  EKS Tailscale Subnet Router
=================================
- Advertising VPC routes to Tailscale
- EKS private endpoint accessible via Tailscale
- Run kubectl from your local machine

Status:
- tailscale status
- tailscale netcheck
=================================
EOF

echo "Tailscale subnet router setup complete" > /var/log/tailscale-setup.log
