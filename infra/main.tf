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
  
  enable_nat_gateway = false  # Save $64/month
  enable_vpn_gateway = false
  
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
