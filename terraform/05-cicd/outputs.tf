output "artifact_bucket" { value = aws_s3_bucket.artifacts.bucket }
output "plan_project" { value = aws_codebuild_project.plan.name }
output "apply_project" { value = aws_codebuild_project.apply.name }

output "connection_arn" {
  value       = var.create_connection ? aws_codestarconnections_connection.github[0].arn : null
  description = "생성 후 콘솔에서 PENDING → AVAILABLE로 승격시켜야 합니다"
}

output "pipeline_name" {
  value = var.create_connection ? aws_codepipeline.this[0].name : null
}
