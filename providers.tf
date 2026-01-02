provider "aws" {
  region = var.region
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.core.name
}

# Kubernetes provider for the EKS cluster
provider "kubernetes" {
  host                   = aws_eks_cluster.core.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.core.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "tls" {}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.core.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.core.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
