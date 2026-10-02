variable "vpc_id" {
  description = "모듈 2의 vpc_id"
  type        = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ami_id" {
  description = "비우면 최신 AL2023을 조회합니다. Floci에서는 더미 ID를 넣으세요."
  type        = string
  default     = ""
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ingress_cidr" {
  description = "ALB에 접근할 수 있는 CIDR. 0.0.0.0/0은 실습 전용."
  type        = string
  default     = "0.0.0.0/0"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "app_message" {
  description = "LAB 03에서 이 값을 바꿔보세요"
  type        = string
  default     = "hello from v1"
}
