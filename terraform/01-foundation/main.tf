# ──────────────────────────────────────────────────────────────
# 모듈 1 · 기초 — 이후 모든 모듈이 쓸 state backend를 만듭니다.
#
# 닭과 달걀: backend를 만드는 이 구성 자체는 로컬 state를 씁니다.
# 만들고 나면 backend.tf의 주석을 풀고 `terraform init -migrate-state`.
# ──────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "state" {
  bucket = "${local.name_prefix}-tfstate-${data.aws_region.current.name}"

  # 실수로 지우면 모든 모듈의 state가 날아갑니다.
  lifecycle {
    prevent_destroy = false # 실습 환경이라 false. 실제 AWS에서는 true로.
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # state를 실수로 덮어써도 되돌릴 수 있습니다
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── 실습용 리소스 ─────────────────────────────────────────────
# LAB 01 — 변수·local·output, 그리고 for_each vs count 비교

variable "demo_buckets" {
  description = "for_each 실습용. 가운데 항목을 지우고 plan을 비교해 보세요."
  type        = set(string)
  default     = ["alpha", "bravo", "charlie"]
}

resource "aws_s3_bucket" "demo_for_each" {
  for_each = var.demo_buckets
  bucket   = "${local.name_prefix}-fe-${each.key}"
}

# 같은 것을 count로 — 가운데를 지우면 뒤가 전부 재생성됩니다.
resource "aws_s3_bucket" "demo_count" {
  count  = length(var.demo_buckets)
  bucket = "${local.name_prefix}-ct-${tolist(var.demo_buckets)[count.index]}"
}
