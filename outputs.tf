output "cluster_name" {
  value = aws_eks_cluster.core.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.core.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.core.certificate_authority[0].data
}

output "vpc_id" {
  value = aws_vpc.netw.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
