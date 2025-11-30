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
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
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
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.13.0"
  
  name = "${var.env}-vpc"
  cidr = "10.0.0.0/16"
  
  azs             = ["${var.region}a", "${var.region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
  
  enable_nat_gateway     = true
  single_nat_gateway     = true  # Single NAT shared across AZs (saves ~$32/month, reduces HA)
  enable_vpn_gateway     = false
  
  # EKS subnet tags
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${var.env}-eks" = "shared"
  }
  
  private_subnet_tags = merge(
    {
      "kubernetes.io/role/internal-elb"       = "1"
      "kubernetes.io/cluster/${var.env}-eks"  = "shared"
    },
    # Karpenter discovery tag (Week 12) - only add if Karpenter is enabled
    var.enable_karpenter ? { "karpenter.sh/discovery" = "${var.env}-eks" } : {}
  )
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.0.0"
  
  name               = "${var.env}-eks"
  kubernetes_version = "1.32"  # Upgraded from 1.31 to avoid extended support costs ($0.60/hr vs $0.10/hr)
  
  # Grant cluster creator admin permissions (automatically creates access entry for current user)
  enable_cluster_creator_admin_permissions = true
  
  # Additional access entries (if needed for other users/roles)
  access_entries = {}
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  # Endpoint configuration (correct terraform-aws-modules/eks syntax)
  endpoint_public_access  = true
  endpoint_private_access = true
  
  # Public access enabled for kubectl from anywhere
  endpoint_public_access_cidrs = ["0.0.0.0/0"]
  
  # Enable logging for faster debugging
  enabled_log_types = ["api", "audit", "authenticator"]
  
  # Essential addons - install VPC CNI and Pod Identity before nodes
  addons = {
    vpc-cni = {
      before_compute = true
      most_recent    = true
      # Enable prefix delegation to increase max pods per node
      # t4g.medium: 17 pods (default) -> 110 pods (with prefix delegation)
      # Each node reserves /28 prefixes (16 IPs) instead of individual IPs
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"  # Keep 1 warm /28 prefix per ENI
        }
      })
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
  
  # Managed node group - REMOVED
  # Using direct aws_eks_node_group resource instead (see graviton-nodes.tf)
  # Reason: terraform-aws-modules/eks v21.0.0 has a bug where ami_type
  # is not properly passed when using launch templates
  eks_managed_node_groups = {}
}

# Argo CD Installation
resource "kubernetes_namespace" "argocd" {
  count = var.enable_argocd ? 1 : 0
  
  depends_on = [module.eks.aws_eks_cluster]
  
  metadata {
    name = "argocd"
    labels = {
      name                         = "argocd"
      "app.kubernetes.io/name"     = "argocd"
    }
  }
}

resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0
  
  depends_on = [
    module.eks.aws_eks_cluster,
    kubernetes_namespace.argocd,
    module.eks,
    helm_release.aws_load_balancer_controller  # Wait for LB Controller to be fully ready
  ]
  
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd[0].metadata[0].name
  version    = "7.6.12"  # Stable version
  
  # Wait for webhook to be fully operational before proceeding
  wait          = true
  wait_for_jobs = true
  timeout       = 600  # 10 minutes timeout

  values = [
    file("../k8s/argocd/values.yaml")
  ]
  
  # Add small delay to ensure webhook is fully ready
  provisioner "local-exec" {
    command = "echo 'Waiting 30s for LB Controller webhook to stabilize...' && sleep 30"
  }
}

# Bootstrap Application - "App of Apps" pattern
# This Application watches k8s/argocd/ and manages all other Applications/Projects
resource "kubernetes_manifest" "argocd_bootstrap" {
  count = var.enable_argocd ? 1 : 0
  
  depends_on = [helm_release.argocd]
  
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "argocd-apps"
      namespace = "argocd"
      labels = {
        "app.kubernetes.io/name" = "argocd-bootstrap"
      }
    }
    spec = {
      project = "default"
      
      source = {
        repoURL        = "https://github.com/rhprasad0/aws-devops-lab"
        targetRevision = "main"
        path           = "k8s/argocd"
        directory = {
          recurse = true  # Watch all subdirectories (projects/, applications/)
        }
      }
      
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

# Argo CD Project for sample apps (security boundary)
resource "kubernetes_manifest" "sample_apps_project" {
  count = var.enable_argocd_apps ? 1 : 0
  
  depends_on = [helm_release.argocd]
  
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "sample-apps"
      namespace = "argocd"
      labels = {
        "app.kubernetes.io/name" = "sample-apps-project"
      }
    }
    spec = {
      description = "Project for sample applications in the EKS lab"
      
      sourceRepos = [
        "https://github.com/rhprasad0/aws-devops-lab"
      ]
      
      destinations = [
        {
          namespace = "default"
          server    = "https://kubernetes.default.svc"
        },
        {
          namespace = "test"
          server    = "https://kubernetes.default.svc"
        }
      ]
      
      namespaceResourceWhitelist = [
        { group = "", kind = "ConfigMap" },
        { group = "", kind = "Secret" },
        { group = "", kind = "Service" },
        { group = "", kind = "ServiceAccount" },
        { group = "apps", kind = "Deployment" },
        { group = "apps", kind = "ReplicaSet" },
        { group = "networking.k8s.io", kind = "Ingress" }
      ]
      
      clusterResourceBlacklist = [
        { group = "", kind = "Namespace" },
        { group = "rbac.authorization.k8s.io", kind = "ClusterRole" },
        { group = "rbac.authorization.k8s.io", kind = "ClusterRoleBinding" }
      ]
    }
  }
}

# Sample App Application (now using restricted project)
resource "kubernetes_manifest" "sample_app_application" {
  count = var.enable_argocd_apps ? 1 : 0
  
  depends_on = [kubernetes_manifest.sample_apps_project]
  
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "sample-app"
      namespace = "argocd"
    }
    spec = {
      project = "sample-apps"  # Use restricted project instead of default
      source = {
        repoURL        = "https://github.com/rhprasad0/aws-devops-lab"
        targetRevision = "main"
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
}
