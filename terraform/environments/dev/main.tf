terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name                  = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_count  = var.public_subnet_count
  private_subnet_count = var.private_subnet_count
  enable_nat_gateway   = var.enable_nat_gateway
  tags                = local.common_tags
}


module "eks" {
  source = "../../modules/eks"

  name             = var.project_name
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.public_subnet_ids
  pod_subnet_ids   = length(module.vpc.private_subnet_ids) > 0 ? module.vpc.private_subnet_ids : module.vpc.public_subnet_ids

  cluster_version               = "1.28"
  node_group_instance_types     = ["t3.small", "t3.medium"]
  node_group_desired_size       = 2
  node_group_max_size           = 4
  node_group_min_size           = 1
  node_group_capacity_type      = "SPOT"
  enable_irsa                   = true

  tags = local.common_tags
}

module "alb_eks" {
  source = "../../modules/alb-eks"

  name                      = var.project_name
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.public_subnet_ids
  cluster_name              = module.eks.cluster_id
  cluster_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  cluster_endpoint          = module.eks.cluster_endpoint
  cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  node_security_group_id    = module.eks.node_group_security_group_id
  enable_aws_load_balancer_controller = true

  tags = local.common_tags
}

resource "random_password" "rds_password" {
  count            = var.enable_rds && var.rds_master_password == "" ? 1 : 0
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "../../modules/rds"

  name                      = var.project_name
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = length(module.vpc.private_subnet_ids) > 0 ? module.vpc.private_subnet_ids : module.vpc.public_subnet_ids
  allowed_security_group_ids = [
    module.eks.node_group_security_group_id,
    module.eks.cluster_security_group_id
  ]
  instance_class            = var.rds_instance_class
  master_password           = var.rds_master_password != "" ? var.rds_master_password : random_password.rds_password[0].result
  publicly_accessible       = length(module.vpc.private_subnet_ids) > 0 ? false : true
  skip_final_snapshot       = true
  deletion_protection       = false

  tags = local.common_tags
}