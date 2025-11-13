terraform {
  required_version = ">= 1.0"
  
  backend "s3" {
    bucket         = "ryan-eks-lab-tfstate"
    key            = "eks-lab/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "eks-lab-tfstate-lock"
    encrypt        = true
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  
  default_tags {
    tags = {
      project    = "eks-ephemeral-lab"
      env        = var.env
      owner      = var.owner
      created_at = "2025-11-11"
      ttl_hours  = var.ttl_hours
    }
  }
}

# VPC
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  
  name = "${var.env}-vpc"
  cidr = "10.0.0.0/16"
  
  azs             = ["${var.region}a", "${var.region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
  
  enable_nat_gateway     = true
  one_nat_gateway_per_az = true  # One NAT per AZ for HA (+$32/month vs single NAT)
  enable_vpn_gateway     = false
  
  # EKS subnet tags
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${var.env}-eks" = "shared"
  }
  
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.env}-eks" = "shared"
  }
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"
  
  name               = "${var.env}-eks"
  kubernetes_version = "1.31"
  
  endpoint_public_access  = true
  endpoint_private_access = true
  
  # Grant cluster creator admin permissions
  enable_cluster_creator_admin_permissions = true
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  # Enable logging for faster debugging
  enabled_log_types = ["api", "audit", "authenticator"]
  
  # Essential addons - install VPC CNI and Pod Identity before nodes
  addons = {
    vpc-cni = {
      before_compute = true
      most_recent    = true
    }
    eks-pod-identity-agent = {
      before_compute = true
      most_recent    = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }
  
  # Managed node group
  eks_managed_node_groups = {
    main = {
      # AL2 is more stable for EKS bootstrap process
      ami_type       = "AL2_x86_64"
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      
      disk_size = 20
      
      # 10-minute timeouts for faster feedback
      timeouts = {
        create = "10m"
        update = "10m"
        delete = "10m"
      }
      
      # Fix IMDS hop limit for private subnets with NAT Gateway
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
    }
  }
}
