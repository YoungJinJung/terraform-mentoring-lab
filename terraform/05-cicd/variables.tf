variable "terraform_version" {
  type    = string
  default = "1.16.1"
}

variable "terraform_dir" {
  description = "파이프라인이 plan/apply할 디렉터리"
  type        = string
  default     = "terraform/02-network"
}

variable "create_connection" {
  description = "CodeStar Connection과 파이프라인을 만들지 여부. Floci에서는 false."
  type        = bool
  default     = false
}

variable "target_role_arn" {
  description = "CodeBuild가 assume할 apply 역할 (모듈 3 출력). 비우면 * 로 둡니다 — 실습 전용."
  type        = string
  default     = ""
}

variable "github_org" {
  type    = string
  default = "YoungJinJung"
}

variable "github_repo" {
  type    = string
  default = "terraform-mentoring-lab"
}
