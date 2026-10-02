variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }

variable "image" {
  description = "Floci/로컬에서는 공개 이미지로 충분합니다"
  type        = string
  default     = "public.ecr.aws/docker/library/nginx:alpine"
}

variable "container_port" {
  type    = number
  default = 80
}

variable "app_version" {
  description = "LAB에서 이 값을 바꿔 배포를 유발합니다"
  type        = string
  default     = "v1"
}

# ── 배포 전략 — 이 모듈의 주인공 ────────────────────────────────────
variable "deployment_strategy" {
  description = "ROLLING | BLUE_GREEN | CANARY | LINEAR"
  type        = string
  default     = "ROLLING"

  validation {
    condition     = contains(["ROLLING", "BLUE_GREEN", "CANARY", "LINEAR"], var.deployment_strategy)
    error_message = "ROLLING, BLUE_GREEN, CANARY, LINEAR 중 하나여야 합니다."
  }
}

variable "bake_time_minutes" {
  description = "전환 후 지켜보는 시간. 0이면 롤백 기회가 없습니다."
  type        = number
  default     = 5
}

variable "validation_lambda_arn" {
  description = "lifecycle hook으로 호출할 검증 Lambda. 비우면 훅 없음."
  type        = string
  default     = ""
}

# ── 용량 ───────────────────────────────────────────────────────────
variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "cpu_architecture" {
  description = "ARM64 | X86_64. ARM64가 더 저렴합니다."
  type        = string
  default     = "X86_64"
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 6
}

variable "on_demand_base" {
  description = "Spot 비중을 쓰더라도 최소 이만큼은 온디맨드"
  type        = number
  default     = 1
}

variable "spot_weight" {
  type    = number
  default = 0
}

# ── 기타 ───────────────────────────────────────────────────────────
variable "ingress_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "container_insights" {
  description = "enhanced는 태스크 단위 지표까지 보냅니다 — 유용하지만 유료"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "readonly_root" {
  description = "nginx 공개 이미지는 쓰기가 필요해서 false. 직접 만든 이미지면 true를 노려보세요."
  type        = bool
  default     = false
}
