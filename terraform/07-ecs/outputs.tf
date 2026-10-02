output "alb_dns_name" { value = aws_lb.this.dns_name }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "service_name" { value = aws_ecs_service.app.name }
output "task_definition_arn" { value = aws_ecs_task_definition.app.arn }

output "test_url" {
  description = "Blue/Green·Canary일 때 새 버전을 먼저 찔러볼 주소"
  value       = var.deployment_strategy == "ROLLING" ? null : "http://${aws_lb.this.dns_name}:8080/"
}

output "prod_url" {
  value = "http://${aws_lb.this.dns_name}/"
}

output "exec_into_task" {
  value = "aws ecs execute-command --cluster ${aws_ecs_cluster.this.name} --task <TASK_ID> --container app --interactive --command /bin/sh"
}
