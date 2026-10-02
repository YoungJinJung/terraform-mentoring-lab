output "vpc_id" { value = aws_vpc.this.id }
output "vpc_cidr" { value = aws_vpc.this.cidr_block }
output "public_subnet_ids" { value = [for k, v in var.subnets : aws_subnet.this[k].id if v.tier == "public"] }
output "private_subnet_ids" { value = [for k, v in var.subnets : aws_subnet.this[k].id if v.tier == "private"] }
output "isolated_subnet_ids" { value = [for k, v in var.subnets : aws_subnet.this[k].id if v.tier == "isolated"] }
output "private_route_table_ids" { value = values(aws_route_table.private)[*].id }
output "nat_gateway_count" {
  description = "nat_strategy를 바꿔가며 이 값이 어떻게 변하는지 보세요"
  value       = length(aws_nat_gateway.this)
}
