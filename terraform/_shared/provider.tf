# ──────────────────────────────────────────────────────────────
# 로컬(Floci) ↔ 실제 AWS 전환
#
# 코드를 두 벌 쓰지 않기 위해, 엔드포인트 오버라이드를 조건부로 넣습니다.
# var.use_floci = false 면 endpoints 블록이 비어 평소대로 실제 AWS를 봅니다.
#
#   terraform apply                        # 로컬 (기본값)
#   terraform apply -var use_floci=false   # 실제 AWS
# ──────────────────────────────────────────────────────────────
locals {
  # Floci는 모든 서비스를 한 포트(4566)로 받습니다.
  floci_services = [
    "s3", "dynamodb", "iam", "sts", "kms", "secretsmanager", "ssm",
    "ec2", "elbv2", "autoscaling", "ecs", "ecr", "eks", "lambda",
    "cloudwatch", "cloudwatchlogs", "codebuild", "codedeploy", "codepipeline",
    "rds", "sns", "sqs", "route53", "acm", "cloudtrail", "organizations",
  ]
}

provider "aws" {
  region = var.region

  # 에뮬레이터에는 실제 자격 증명이 없으므로 검증 단계를 건너뜁니다.
  access_key                  = var.use_floci ? "test" : null
  secret_key                  = var.use_floci ? "test" : null
  skip_credentials_validation = var.use_floci
  skip_metadata_api_check     = var.use_floci
  skip_requesting_account_id  = var.use_floci
  skip_region_validation      = var.use_floci

  # Floci의 S3는 path-style 주소를 씁니다.
  s3_use_path_style = var.use_floci

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Lab         = var.use_floci ? "floci" : "aws"
    }
  }

  dynamic "endpoints" {
    for_each = var.use_floci ? [1] : []
    content {
      s3             = var.floci_endpoint
      dynamodb       = var.floci_endpoint
      iam            = var.floci_endpoint
      sts            = var.floci_endpoint
      kms            = var.floci_endpoint
      secretsmanager = var.floci_endpoint
      ssm            = var.floci_endpoint
      ec2            = var.floci_endpoint
      elbv2          = var.floci_endpoint
      autoscaling    = var.floci_endpoint
      ecs            = var.floci_endpoint
      ecr            = var.floci_endpoint
      eks            = var.floci_endpoint
      lambda         = var.floci_endpoint
      cloudwatch     = var.floci_endpoint
      cloudwatchlogs = var.floci_endpoint
      codebuild      = var.floci_endpoint
      codedeploy     = var.floci_endpoint
      codepipeline   = var.floci_endpoint
      rds            = var.floci_endpoint
      sns            = var.floci_endpoint
      sqs            = var.floci_endpoint
      route53        = var.floci_endpoint
      acm            = var.floci_endpoint
      cloudtrail     = var.floci_endpoint
      organizations  = var.floci_endpoint
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
}
