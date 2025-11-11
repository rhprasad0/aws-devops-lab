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
      version = "~> 5.0"
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
