output "alb_dns_name" { value = aws_lb.this.dns_name }
output "asg_name" { value = aws_autoscaling_group.app.name }
output "launch_template_latest_version" { value = aws_launch_template.app.latest_version }
output "app_security_group_id" { value = aws_security_group.app.id }

output "curl_me" {
  value = "curl http://${aws_lb.this.dns_name}/"
}
