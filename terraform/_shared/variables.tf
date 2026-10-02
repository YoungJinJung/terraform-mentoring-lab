variable "use_floci" {
  description = "true면 로컬 Floci 에뮬레이터로, false면 실제 AWS로 붙습니다."
  type        = bool
  default     = true
}

variable "floci_endpoint" {
  description = "Floci 엔드포인트"
  type        = string
  default     = "http://localhost:4566"
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "tfm"
}

variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment는 dev, staging, prod 중 하나여야 합니다."
  }
}
