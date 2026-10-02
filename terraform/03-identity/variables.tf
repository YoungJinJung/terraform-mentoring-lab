variable "github_org" {
  description = "GitHub 조직 또는 사용자명"
  type        = string
  default     = "YoungJinJung"
}

variable "github_repo" {
  type    = string
  default = "terraform-mentoring-lab"
}

# ── immutable subject claim용 숫자 ID ──────────────────────────────
#
#   curl -s https://api.github.com/users/YoungJinJung | jq .id
#   curl -s https://api.github.com/repos/OWNER/REPO  | jq .id
#
# 비워두면 예전(mutable) 형식만 허용합니다. 2026-07-15 이후에 만든
# 리포라면 반드시 채워야 합니다.
variable "github_org_id" {
  type    = string
  default = ""
}

variable "github_repo_id" {
  type    = string
  default = ""
}

variable "create_oidc_provider" {
  description = "계정에 OIDC 공급자가 아직 없을 때만 true"
  type        = bool
  default     = true
}

variable "state_bucket" {
  description = "모듈 1에서 만든 state 버킷 이름"
  type        = string
  default     = "tfm-dev-tfstate"
}

variable "sops_file" {
  description = "암호화된 SOPS 파일 경로. 비우면 비밀 관련 리소스를 건너뜁니다."
  type        = string
  default     = ""
}

variable "sops_version" {
  description = "write-only 값을 다시 밀어넣으려면 이 숫자를 올리세요"
  type        = number
  default     = 1
}
