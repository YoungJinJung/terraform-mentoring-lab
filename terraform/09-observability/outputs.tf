output "sns_topic_arn" { value = aws_sns_topic.alerts.arn }
output "dashboard_url" {
  value = "https://${data.aws_region.current.region}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "log_group_names" { value = [for k, v in aws_cloudwatch_log_group.app : v.name] }

output "alarm_names" {
  value = compact(concat(
    [aws_cloudwatch_metric_alarm.error_rate.alarm_name],
    var.alb_arn_suffix == "" ? [] : [
      aws_cloudwatch_metric_alarm.alb_5xx[0].alarm_name,
      aws_cloudwatch_metric_alarm.latency_p99[0].alarm_name,
      aws_cloudwatch_metric_alarm.heartbeat[0].alarm_name,
      aws_cloudwatch_composite_alarm.page[0].alarm_name,
    ],
  ))
}

output "pending_email_confirmations" {
  description = "이 주소들은 확인 메일을 눌러야 알람을 받습니다"
  value       = var.alert_emails
}
