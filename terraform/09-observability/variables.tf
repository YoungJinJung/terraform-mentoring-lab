variable "log_groups" {
  description = <<-EOT
    관리할 로그 그룹. 보존 기간을 **반드시** 지정하세요 —
    생략하면 "영구"이고 저장 비용이 매달 누적됩니다.

    infrequent_access = true 는 저장 비용을 낮추지만
    메트릭 필터·구독 필터·Live Tail을 포기합니다.
  EOT
  type = map(object({
    retention_days    = number
    infrequent_access = optional(bool, false)
  }))

  default = {
    "/app/api" = { retention_days = 30 }
    "/app/web" = { retention_days = 14 }
    # 규정 때문에 남기지만 평소에 안 보는 로그
    "/app/audit" = { retention_days = 365, infrequent_access = true }
  }

  validation {
    condition = alltrue([
      for k, v in var.log_groups :
      contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], v.retention_days)
    ])
    error_message = "retention_days는 CloudWatch가 허용하는 값이어야 합니다 (1,3,5,7,14,30,60,90,...)."
  }
}

variable "log_format" {
  description = "json | text. json이면 구조화 필터를 씁니다."
  type        = string
  default     = "json"
}

variable "alert_emails" {
  description = "구독 후 각자 확인 메일을 눌러야 활성화됩니다"
  type        = list(string)
  default     = []
}

variable "alb_arn_suffix" {
  description = "모듈 6/7의 ALB arn_suffix. 비우면 ALB 관련 알람을 건너뜁니다."
  type        = string
  default     = ""
}

variable "error_threshold" {
  type    = number
  default = 10
}

variable "latency_p99_threshold_seconds" {
  type    = number
  default = 1.5
}

variable "enable_canary" {
  description = "Synthetics Canary. Floci에서는 false."
  type        = bool
  default     = false
}

variable "canary_runtime" {
  description = "런타임은 주기적으로 폐기됩니다 — 콘솔에서 현재 목록을 확인하세요"
  type        = string
  default     = "syn-nodejs-puppeteer-11.0"
}
