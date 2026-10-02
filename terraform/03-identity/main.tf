# ─────────────────────────────────────────────────────────────────────
# 모듈 3 · IAM & 비밀 관리
#
#   · OIDC 신뢰 정책 — 2026-07-15부터 새 리포는 immutable subject claim
#   · 권한 경계(permissions boundary)로 "관리자도 못 넘는 선" 그리기
#   · SOPS로 암호화한 파일을 ephemeral로 읽어 state 유출을 막기
# ─────────────────────────────────────────────────────────────────────

locals {
  name = "${var.project}-${var.environment}"

  # GitHub Actions OIDC subject.
  #
  # 예전 형식:  repo:ORG/REPO:ref:refs/heads/main
  # 새 형식  :  repo:ORG@ORGID/REPO@REPOID:ref:refs/heads/main
  #
  # 2026-04 발표, 2026-07-15부터 "새로 만든 리포"는 자동 적용입니다.
  # 기존 리포는 옵트인이지만, 조직에서 켜는 순간 예전 형식 trust policy는
  # 조용히 깨집니다. 그래서 여기서는 둘 다 허용하도록 만듭니다.
  oidc_sub_legacy    = "repo:${var.github_org}/${var.github_repo}:*"
  oidc_sub_immutable = "repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:*"

  oidc_subs = compact([
    local.oidc_sub_legacy,
    var.github_org_id != "" && var.github_repo_id != "" ? local.oidc_sub_immutable : "",
  ])
}

# ─────────────────────────────────────────────────────────────────────
# OIDC 공급자
#
# 계정에 하나만 있으면 됩니다. 이미 있다면 import 하세요:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<ACCOUNT>:oidc-provider/token.actions.githubusercontent.com
#
# thumbprint_list: 2023년 이후 AWS가 서버 측에서 검증하므로 값 자체는
# 사실상 무의미해졌지만, API가 비어 있는 리스트를 거부합니다.
# ─────────────────────────────────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"
      identifiers = [(
        var.create_oidc_provider
        ? aws_iam_openid_connect_provider.github[0].arn
        : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      )]
    }

    # aud 검증 — 빠뜨리면 아무 GitHub 리포나 이 역할을 가져갈 수 있습니다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # sub 검증 — 반드시 StringLike + 와일드카드 위치를 정확히.
    # "repo:ORG/*"처럼 느슨하게 쓰면 조직 내 모든 리포가 통과합니다.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.oidc_subs
    }
  }
}

data "aws_caller_identity" "current" {}

# ─────────────────────────────────────────────────────────────────────
# 권한 경계 — plan 역할은 절대 쓰기를 못 하게
# ─────────────────────────────────────────────────────────────────────
resource "aws_iam_policy" "boundary" {
  name        = "${local.name}-boundary"
  description = "이 경계를 붙인 역할은 여기 적힌 범위를 넘지 못합니다"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowRegionScoped"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = [var.region] }
        }
      },
      {
        # 경계를 떼어내거나 IAM 자체를 건드리는 건 금지.
        Sid    = "DenyIamEscalation"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateAccessKey",
          "iam:DeleteRolePermissionsBoundary",
          "iam:PutRolePermissionsBoundary",
          "iam:AttachRolePolicy",
          "organizations:*",
          "account:*",
        ]
        Resource = "*"
      },
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────
# plan 역할 / apply 역할을 나눕니다.
# PR 단계에서는 읽기만, main 병합 후에만 쓰기.
# ─────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "plan" {
  name                 = "${local.name}-tf-plan"
  assume_role_policy   = data.aws_iam_policy_document.github_assume.json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# plan도 state 버킷과 lock 파일에는 쓸 수 있어야 합니다.
# 이 예외를 빠뜨려서 "plan은 읽기만" 설계가 실패하는 경우가 많습니다.
resource "aws_iam_role_policy" "plan_state" {
  name = "state-access"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.state_bucket}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.state_bucket}"
      },
    ]
  })
}

resource "aws_iam_role" "apply" {
  name                 = "${local.name}-tf-apply"
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = (var.create_oidc_provider
          ? aws_iam_openid_connect_provider.github[0].arn
          : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        )
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # apply는 와일드카드 없이 "main 브랜치" 또는 "environment"로 못 박습니다.
          "token.actions.githubusercontent.com:sub" = (
            var.github_org_id != "" && var.github_repo_id != ""
            ? "repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main"
            : "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
          )
        }
      }
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────
# SOPS — ephemeral로 읽기
#
# 왜 ephemeral인가: data "sops_file"로 읽으면 복호화된 값이 state에
# 평문으로 남습니다. ephemeral은 state에 기록되지 않습니다.
# (Terraform 1.10+ / carlpett/sops 1.1+)
# ─────────────────────────────────────────────────────────────────────
ephemeral "sops_file" "secrets" {
  count       = var.sops_file == "" ? 0 : 1
  source_file = var.sops_file
}

resource "aws_secretsmanager_secret" "app" {
  count                   = var.sops_file == "" ? 0 : 1
  name                    = "${local.name}/app"
  recovery_window_in_days = 0 # 실습용. 운영에서는 7~30.
}

resource "aws_secretsmanager_secret_version" "app" {
  count     = var.sops_file == "" ? 0 : 1
  secret_id = aws_secretsmanager_secret.app[0].id

  # write-only argument (Terraform 1.11+). state에 값이 남지 않습니다.
  secret_string_wo         = ephemeral.sops_file.secrets[0].raw
  secret_string_wo_version = var.sops_version
}
