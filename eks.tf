# Minimal IAM role for EKS control plane
resource "aws_iam_role" "eks_cluster" {
  name = format("%s-eks-cluster-role", local.cluster_name)
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = { Service = "eks.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "core" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy]
}

# Node group IAM role
resource "aws_iam_role" "node_group" {
  name = format("%s-node-group-role", local.cluster_name)
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Explicit Instance profile for node role (deterministic name)
resource "aws_iam_instance_profile" "node" {
  name = format("%s-node-instance-profile", local.cluster_name)
  role = aws_iam_role.node_group.name
}

locals {
  node_groups = {
    amd64 = {
      desired = var.desired_capacity
      min     = var.desired_capacity
      max     = var.desired_capacity
    }
    arm64 = {
      desired = 1
      min     = 1
      max     = 3
    }
  }

  node_group_names = {
    amd64 = format("%s-amd64", local.cluster_name)
    arm64 = format("%s-arm64", local.cluster_name)
  }

  node_group_instance_types = {
    amd64 = var.amd64_instance_types
    arm64 = var.arm64_instance_types
  }
}

# AMD64 Node Group for general workloads
resource "aws_eks_node_group" "amd64" {
  cluster_name    = aws_eks_cluster.core.name
  node_group_name = local.node_group_names.amd64
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = local.node_groups.amd64.desired
    max_size     = local.node_groups.amd64.max
    min_size     = local.node_groups.amd64.min
  }

  instance_types = local.node_group_instance_types.amd64
  ami_type       = "BOTTLEROCKET_x86_64"

  tags = merge(var.common_tags, { Name = local.node_group_names.amd64 })

  depends_on = [aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy]
}

# ARM64 node group to satisfy arm64 workloads (m6g Graviton)
resource "aws_eks_node_group" "arm64" {
  cluster_name    = aws_eks_cluster.core.name
  node_group_name = local.node_group_names.arm64
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = local.node_groups.arm64.desired
    max_size     = local.node_groups.arm64.max
    min_size     = local.node_groups.arm64.min
  }

  instance_types = local.node_group_instance_types.arm64
  ami_type       = "BOTTLEROCKET_ARM_64"
  capacity_type  = "ON_DEMAND"

  tags = merge(var.common_tags, { Name = local.node_group_names.arm64 })

  depends_on = [aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy]
}
