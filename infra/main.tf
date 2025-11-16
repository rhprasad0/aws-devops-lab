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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
      # Required for unique S3 bucket names in security.tf (Config storage)
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

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
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
  
  # Add your IAM user as cluster admin
  access_entries = {
    eks-lab-admin = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::407645373626:user/eks-lab-admin"
      
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
  
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
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      
      disk_size = 20
      
      # 15-minute timeouts for more reliable operations
      timeouts = {
        create = "15m"
        update = "15m"
        delete = "15m"
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

# Argo CD Installation
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name                         = "argocd"
      "app.kubernetes.io/name"     = "argocd"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "7.6.12"  # Stable version

  values = [
    file("../k8s/argocd/values.yaml")
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# Sample App Application
resource "kubernetes_manifest" "sample_app_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "sample-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/rhprasad0/aws-devops-lab"
        targetRevision = "HEAD"
        path           = "k8s/sample-app"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
