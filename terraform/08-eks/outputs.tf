output "cluster_name" { value = aws_eks_cluster.this.name }
output "cluster_endpoint" { value = aws_eks_cluster.this.endpoint }
output "cluster_version" { value = aws_eks_cluster.this.version }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.cluster.arn }
output "node_role_arn" { value = aws_iam_role.node.arn }

output "support_type" {
  description = "EXTENDED면 시간당 $0.60입니다. 의도한 것인지 확인하세요."
  value       = var.support_type
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name}"
}

output "karpenter_queue_name" {
  value = var.enable_karpenter ? aws_sqs_queue.karpenter[0].name : null
}
