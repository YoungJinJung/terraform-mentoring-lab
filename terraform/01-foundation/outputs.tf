output "state_bucket" {
  description = "이후 모듈의 backend가 쓸 버킷 이름"
  value       = aws_s3_bucket.state.id
}

output "for_each_addresses" {
  description = "주소가 키라서, 하나를 지워도 나머지는 그대로입니다."
  value       = { for k, b in aws_s3_bucket.demo_for_each : k => b.id }
}

output "count_addresses" {
  description = "주소가 인덱스라서, 가운데를 지우면 뒤가 밀립니다."
  value       = aws_s3_bucket.demo_count[*].id
}
