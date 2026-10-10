# ─────────────────────────────────────────────────────────────────────
# 모듈 5 · CI/CD
#
# AWS 네이티브(CodePipeline V2 + CodeBuild)로 terraform plan/apply
# 파이프라인을 만듭니다. GitHub Actions / Jenkins 버전은 같은 디렉터리의
# workflows/ 와 Jenkinsfile 을 보세요 — 셋을 나란히 두고 비교하는 게
# 이 모듈의 목표입니다.
# ─────────────────────────────────────────────────────────────────────

locals {
  name = "${var.project}-${var.environment}-tf"
}

# ── 아티팩트 버킷 ──────────────────────────────────────────────────
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # 실습용
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# 아티팩트는 쌓이면 돈입니다. 실습에서도 수명주기를 붙이는 습관.
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

# ── CodeBuild 역할 ─────────────────────────────────────────────────
resource "aws_iam_role" "codebuild" {
  name = "${local.name}-codebuild"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "codebuild.amazonaws.com" }
      # confused deputy 방지 — 이 두 조건이 없으면 남의 프로젝트가
      # 이 역할을 호출할 수 있는 구조가 됩니다.
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:codebuild:${var.region}:${data.aws_caller_identity.current.account_id}:project/${local.name}-*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "inline"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${local.name}*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketLocation"]
        Resource = ["${aws_s3_bucket.artifacts.arn}", "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        # 실습이므로 ReadOnly + state. 운영에서는 모듈 3의 apply 역할을
        # assume하게 만들고, 이 역할 자체에는 sts:AssumeRole만 줍니다.
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = var.target_role_arn == "" ? "*" : var.target_role_arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_ro" {
  role       = aws_iam_role.codebuild.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ── CodeBuild 프로젝트: plan ───────────────────────────────────────
#
# compute_type 고르는 기준
#   BUILD_LAMBDA_*   — 콜드스타트 거의 없음, 과금은 초 단위. 단
#                      ① Docker 빌드 불가 ② 최대 15분 ③ 캐시 제한
#                      terraform plan/validate에는 보통 이게 가장 쌉니다.
#   BUILD_GENERAL1_* — 범용. Docker 필요하거나 15분 넘으면 이쪽.
#
# 아래는 plan을 Lambda compute로 돌립니다.
resource "aws_codebuild_project" "plan" {
  name         = "${local.name}-plan"
  service_role = aws_iam_role.codebuild.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    type            = "LINUX_LAMBDA_CONTAINER"
    compute_type    = "BUILD_LAMBDA_1GB"
    image           = "aws/codebuild/amazonlinux-x86_64-lambda-standard:nodejs22"
    privileged_mode = false # Lambda compute에서는 어차피 불가

    environment_variable {
      name  = "TF_VERSION"
      value = var.terraform_version
    }
    environment_variable {
      name  = "TF_DIR"
      value = var.terraform_dir
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec-plan.yml")
  }

  logs_config {
    cloudwatch_logs {
      group_name = "/aws/codebuild/${local.name}-plan"
    }
  }
}

# ── CodeBuild 프로젝트: apply ──────────────────────────────────────
resource "aws_codebuild_project" "apply" {
  name         = "${local.name}-apply"
  service_role = aws_iam_role.codebuild.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"

    environment_variable {
      name  = "TF_VERSION"
      value = var.terraform_version
    }
    environment_variable {
      name  = "TF_DIR"
      value = var.terraform_dir
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec-apply.yml")
  }
}

# ── CodeStar Connection (GitHub) ───────────────────────────────────
#
# 생성 직후 상태는 PENDING입니다. 콘솔에서 "Update pending connection"을
# 눌러 GitHub 인증을 끝내야 AVAILABLE이 됩니다. Terraform으로는
# 끝까지 못 갑니다 — 이게 정상이고, 시험에도 자주 나오는 부분입니다.
resource "aws_codestarconnections_connection" "github" {
  count         = var.create_connection ? 1 : 0
  name          = "${local.name}-gh"
  provider_type = "GitHub"
}

# ── 파이프라인 역할 ────────────────────────────────────────────────
resource "aws_iam_role" "pipeline" {
  name = "${local.name}-pipeline"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "pipeline" {
  name = "inline"
  role = aws_iam_role.pipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = ["${aws_s3_bucket.artifacts.arn}", "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = [aws_codebuild_project.plan.arn, aws_codebuild_project.apply.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = var.create_connection ? aws_codestarconnections_connection.github[0].arn : "*"
      },
    ]
  })
}

# ── 파이프라인 ─────────────────────────────────────────────────────
#
# pipeline_type = "V2"
#   V1 대비 차이: 트리거 필터(브랜치/경로), 변수, 스테이지 롤백.
#   과금도 다릅니다 — V1은 활성 파이프라인당 월 $1 고정,
#   V2는 실행 시간(액션-분) 과금. 하루 몇 번 도는 인프라
#   파이프라인이면 V2가 보통 더 쌉니다. 반대로 하루 수백 번
#   도는 앱 파이프라인은 V1이 쌀 수 있습니다.
resource "aws_codepipeline" "this" {
  count    = var.create_connection ? 1 : 0
  name     = local.name
  role_arn = aws_iam_role.pipeline.arn

  pipeline_type  = "V2"
  execution_mode = "QUEUED" # SUPERSEDED면 뒤 실행이 앞 실행을 덮어씁니다 — state에는 위험

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  # V2 트리거 — terraform 디렉터리 변경에만 반응
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches { includes = ["main"] }
        file_paths { includes = ["terraform/**"] }
      }
    }
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["src"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github[0].arn
        FullRepositoryId = "${var.github_org}/${var.github_repo}"
        BranchName       = "main"
        DetectChanges    = "false" # 트리거 블록이 대신합니다
      }
    }
  }

  stage {
    name = "Plan"
    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["src"]
      output_artifacts = ["plan"]
      configuration    = { ProjectName = aws_codebuild_project.plan.name }
    }
  }

  # ★ 사람이 plan을 읽는 자리. 인프라 파이프라인에서 이걸 빼면
  #   "자동으로 무엇이든 지울 수 있는 파이프라인"이 됩니다.
  stage {
    name = "Approve"
    action {
      name     = "Approve"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
      configuration = {
        CustomData = "Plan 출력을 확인하고 승인하세요. 삭제 항목이 있으면 특히."
      }
    }
  }

  stage {
    name = "Apply"
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["plan"]
      configuration   = { ProjectName = aws_codebuild_project.apply.name }
    }
  }
}
