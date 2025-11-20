# Data source to get current AWS region
data "aws_region" "current" {}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# ECR Repository for main application container images
resource "aws_ecr_repository" "app" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# ECR Repository for init container images
resource "aws_ecr_repository" "init" {
  name                 = "${var.name}-init"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# EKS Cluster IAM Role
resource "aws_iam_role" "cluster_role" {
  name = "${var.name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Attach required policies to cluster role
resource "aws_iam_role_policy_attachment" "cluster_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  ])

  policy_arn = each.value
  role       = aws_iam_role.cluster_role.name
}

# EKS Node Group IAM Role
resource "aws_iam_role" "node_group_role" {
  name = "${var.name}-node-group-role"

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

  tags = var.tags
}

# Attach required policies to node group role
resource "aws_iam_role_policy_attachment" "node_group_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])

  policy_arn = each.value
  role       = aws_iam_role.node_group_role.name
}

# Security group for EKS cluster
resource "aws_security_group" "cluster_sg" {
  name_prefix = "${var.name}-cluster-sg"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-cluster-sg"
  })
}

# Security group for EKS nodes
resource "aws_security_group" "node_group_sg" {
  name_prefix = "${var.name}-node-group-sg"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster_sg.id]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-node-group-sg"
  })
}

# EKS Cluster
resource "aws_eks_cluster" "cluster" {
  name     = var.name
  role_arn = aws_iam_role.cluster_role.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"] 
    security_group_ids      = [aws_security_group.cluster_sg.id]
  }

  # Enable cluster logging
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Enable IRSA (IAM Roles for Service Accounts)
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policies,
    aws_cloudwatch_log_group.cluster_logs
  ]

  tags = var.tags
}

# CloudWatch log group for EKS cluster
resource "aws_cloudwatch_log_group" "cluster_logs" {
  name              = "/aws/eks/${var.name}-eks/cluster"
  retention_in_days = 7

  tags = var.tags
}


# EKS Managed Node Group
resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "${var.name}-node-group"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = var.pod_subnet_ids

  instance_types = var.node_group_instance_types
  capacity_type  = var.node_group_capacity_type

  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  update_config {
    max_unavailable_percentage = 25
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  depends_on = [
    aws_iam_role_policy_attachment.node_group_policies,
    aws_eks_cluster.cluster
  ]

  tags = var.tags
}

# OIDC Identity Provider for IRSA
data "tls_certificate" "cluster_cert" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster_oidc" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.cluster_cert[0].certificates[0].sha1_fingerprint]

  tags = var.tags
}

# IAM Role for Service Account to access Parameter Store
resource "aws_iam_role" "parameter_store_role" {
  count = var.enable_irsa ? 1 : 0
  name  = "${var.name}-parameter-store-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.cluster_oidc[0].arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.cluster_oidc[0].url, "https://", "")}:sub": "system:serviceaccount:${var.name}:${var.name}-sa"
            "${replace(aws_iam_openid_connect_provider.cluster_oidc[0].url, "https://", "")}:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Policy to access Parameter Store
resource "aws_iam_policy" "parameter_store_policy" {
  count = var.enable_irsa ? 1 : 0
  name  = "${var.name}-parameter-store-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/weather-bot-*",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.name}/*"
        ]
      }
    ]
  })

  tags = var.tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "parameter_store_policy_attachment" {
  count      = var.enable_irsa ? 1 : 0
  policy_arn = aws_iam_policy.parameter_store_policy[0].arn
  role       = aws_iam_role.parameter_store_role[0].name
}