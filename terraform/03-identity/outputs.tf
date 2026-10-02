output "plan_role_arn" { value = aws_iam_role.plan.arn }
output "apply_role_arn" { value = aws_iam_role.apply.arn }
output "boundary_arn" { value = aws_iam_policy.boundary.arn }

output "oidc_subjects_allowed" {
  description = "trust policy가 실제로 허용하는 subject 목록"
  value       = local.oidc_subs
}
