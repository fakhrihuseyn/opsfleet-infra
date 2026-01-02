data "tls_certificate" "oidc" {
  url = aws_eks_cluster.core.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = aws_eks_cluster.core.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "karpenter_controller" {
  name = format("%s-karpenter-controller", local.cluster_name)

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Federated = aws_iam_openid_connect_provider.oidc.arn },
        Action    = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:aud" = "sts.amazonaws.com",
          }
          StringLike = {
            "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter"
          }
        }
      }
    ]
  })
}

# Minimal set of managed permissive policies (least-privilege for production).
resource "aws_iam_role_policy_attachment" "karpenter_ec2" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}
resource "aws_iam_role_policy_attachment" "karpenter_sqs" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}
resource "aws_iam_role_policy_attachment" "karpenter_logs" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Karpenter namespace
resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
    labels = {
      name                                 = "karpenter"
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

# Karpenter ServiceAccount with IRSA annotation
resource "kubernetes_service_account" "karpenter" {
  metadata {
    name      = "karpenter"
    namespace = kubernetes_namespace.karpenter.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn
    }
  }

  depends_on = [kubernetes_namespace.karpenter]
}

# Karpenter via Helm using the TF-managed ServiceAccount
resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "https://charts.karpenter.sh"
  chart            = "karpenter"
  version          = "0.16.3"
  namespace        = kubernetes_namespace.karpenter.metadata[0].name
  create_namespace = false

  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.karpenter.metadata[0].name
  }
  set {
    name  = "controller.clusterName"
    value = aws_eks_cluster.core.name
  }
  set {
    name  = "controller.clusterEndpoint"
    value = aws_eks_cluster.core.endpoint
  }
  set {
    name  = "clusterName"
    value = aws_eks_cluster.core.name
  }
  set {
    name  = "clusterEndpoint"
    value = aws_eks_cluster.core.endpoint
  }
  set {
    name  = "controller.replicaCount"
    value = "1"
  }
  set {
    name  = "replicaCount"
    value = "1"
  }
  set {
    name  = "webhook.replicaCount"
    value = "1"
  }

  # Lower resource requests/limits for the small bootstrap cluster
  set {
    name  = "controller.resources.requests.cpu"
    value = "200m"
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "512Mi"
  }
  set {
    name  = "controller.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "controller.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "webhook.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "webhook.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "webhook.resources.limits.cpu"
    value = "200m"
  }
  set {
    name  = "webhook.resources.limits.memory"
    value = "256Mi"
  }

  # AWS instance profile to attach to provisioned EC2 instances so
  # Karpenter can launch nodes without requiring a per-Provisioner instanceProfile.
  set {
    name  = "controller.extraArgs[0]"
    value = format("--aws-default-instance-profile=%s", aws_iam_instance_profile.node.name)
  }

  #Helm timeout to allow webhook/controller bootstrap.
  timeout = 1200
  wait    = true

  depends_on = [kubernetes_service_account.karpenter, aws_iam_role_policy_attachment.karpenter_ec2]
}
