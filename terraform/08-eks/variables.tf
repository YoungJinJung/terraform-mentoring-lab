variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "public_subnet_ids" { type = list(string) }

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

# ── 돈이 걸린 변수 ──────────────────────────────────────────────────
variable "support_type" {
  description = <<-EOT
    STANDARD | EXTENDED

      STANDARD — 표준 지원 기간만. 끝나면 자동 업그레이드. 시간당 $0.10
      EXTENDED — 연장 지원. 시간당 $0.60. **이게 기본값입니다**

    연 환산 차이가 클러스터 하나에 약 $4,400입니다.
    업그레이드를 주기적으로 할 수 있으면 STANDARD.
  EOT
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "STANDARD 또는 EXTENDED."
  }
}

variable "auto_mode" {
  description = "EKS Auto Mode. 노드 관리를 EKS에 맡깁니다 — 편한 대신 컴퓨팅에 관리 비용이 붙습니다."
  type        = bool
  default     = false
}

variable "enable_karpenter" {
  type    = bool
  default = false
}

# ── 엔드포인트 ─────────────────────────────────────────────────────
variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "public_access_cidrs" {
  description = "공개 엔드포인트를 쓸 때 반드시 좁히세요. 0.0.0.0/0은 API 서버 인터넷 공개입니다."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "kms_key_arn" {
  description = "etcd Secret 봉투 암호화용 KMS 키. 비우면 생략."
  type        = string
  default     = ""
}

# ── 접근 제어 ──────────────────────────────────────────────────────
variable "bootstrap_creator_admin" {
  description = <<-EOT
    true면 클러스터를 만든 주체(=CI 역할)가 자동으로 cluster-admin이 됩니다.
    편하지만, CI 역할이 곧 cluster-admin이라는 뜻입니다.
    운영에서는 false로 두고 admin_role_arns로 명시하세요.
  EOT
  type        = bool
  default     = true
}

variable "admin_role_arns" {
  description = "cluster-admin을 줄 IAM 역할 ARN"
  type        = list(string)
  default     = []
}

variable "developer_role_arns" {
  type    = list(string)
  default = []
}

variable "developer_namespaces" {
  type    = list(string)
  default = ["default", "dev"]
}

# ── 노드 그룹 ──────────────────────────────────────────────────────
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

# ── Pod Identity 예시 ──────────────────────────────────────────────
variable "app_namespace" {
  type    = string
  default = "default"
}

variable "app_service_account" {
  type    = string
  default = "demo-app"
}
