# Tailscale Subnet Router Instance (Optional - for private EKS access)
# Cost: ~$7/month (t3.micro)
# Enable with: export TF_VAR_enable_tailscale=true
# 
# This instance advertises VPC routes to your Tailscale network,
# allowing direct kubectl access to private EKS endpoint from your local machine.

# Security group for Tailscale subnet router
resource "aws_security_group" "tailscale" {
  count = var.enable_tailscale ? 1 : 0

  name_prefix = "${var.env}-tailscale-"
  vpc_id      = module.vpc.vpc_id

  # Outbound: Allow all (Tailscale needs internet access for coordination)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Tailscale subnet router outbound traffic"
  }

  tags = {
    Name = "${var.env}-tailscale-subnet-router-sg"
  }
}

# IAM role for Tailscale subnet router
resource "aws_iam_role" "tailscale" {
  count = var.enable_tailscale ? 1 : 0

  name = "${var.env}-tailscale-subnet-router-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# SSM access for remote management (optional)
resource "aws_iam_role_policy_attachment" "tailscale_ssm" {
  count = var.enable_tailscale ? 1 : 0

  role       = aws_iam_role.tailscale[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile
resource "aws_iam_instance_profile" "tailscale" {
  count = var.enable_tailscale ? 1 : 0

  name = "${var.env}-tailscale-subnet-router-profile"
  role = aws_iam_role.tailscale[0].name
}

# Get latest Amazon Linux 2023 AMI (has AWS CLI v2 by default)
data "aws_ami" "amazon_linux_2023" {
  count = var.enable_tailscale ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Tailscale subnet router instance
resource "aws_instance" "tailscale" {
  count = var.enable_tailscale ? 1 : 0

  ami           = data.aws_ami.amazon_linux_2023[0].id
  instance_type = "t3.micro"
  
  subnet_id                   = module.vpc.private_subnets[0]
  vpc_security_group_ids      = [aws_security_group.tailscale[0].id]
  iam_instance_profile        = aws_iam_instance_profile.tailscale[0].name
  associate_public_ip_address = false
  source_dest_check           = false  # Required for subnet routing

  # Install Tailscale as subnet router
  user_data_base64 = base64encode(templatefile("${path.module}/tailscale-userdata.sh", {
    tailscale_auth_key = var.tailscale_auth_key
    cluster_name       = "${var.env}-eks"
    region            = var.region
  }))

  tags = {
    Name = "${var.env}-tailscale-subnet-router"
  }
}

# Allow Tailscale subnet router to access EKS cluster API
resource "aws_security_group_rule" "tailscale_to_eks" {
  count = var.enable_tailscale ? 1 : 0

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.tailscale[0].id
  security_group_id        = module.eks.cluster_security_group_id
  description              = "Tailscale subnet router to EKS API"
}
