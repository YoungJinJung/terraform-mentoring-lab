# ─────────────────────────────────────────────────────────────────────
# 모듈 9 · 관측 (Observability)
#
# 이 모듈의 주제는 "무엇을 보느냐"가 아니라 **무엇을 보지 않을 것인가**입니다.
# 관측 비용은 거의 항상 "다 켜두었기 때문에" 발생합니다.
#
#   · 로그 보존 기간과 저장 클래스
#   · 메트릭 필터로 로그를 지표로 바꿔 쿼리 비용을 줄이기
#   · 복합 알람으로 알람 피로(alert fatigue)를 줄이기
#   · 합성 모니터링 — "안에서 보기"와 "밖에서 보기"
# ─────────────────────────────────────────────────────────────────────

locals {
  name = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── 알림 ───────────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"

  # 전송 실패를 로그로 남깁니다. 이게 없으면 "알람이 안 왔다"를
  # 조사할 방법이 없습니다.
  sqs_success_feedback_sample_rate = 0
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = {
        StringEquals = { "AWS:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value

  # ★ 이메일 구독은 사람이 확인 메일을 눌러야 활성화됩니다.
  #   Terraform은 "pending confirmation" 상태로 끝내고 성공으로 봅니다.
  #   알람을 만들었는데 아무도 못 받는 가장 흔한 원인입니다.
}

# ── 로그 그룹 ──────────────────────────────────────────────────────
#
# ★★ 보존 기간을 안 주면 "영구"입니다 ★★
#
# CloudWatch Logs 비용은 (수집 GB) + (저장 GB·월) + (쿼리 스캔 GB)입니다.
# 영구 보존은 저장 비용이 매달 누적됩니다. 3년 전 로그를 보는 사람은
# 없는데 요금은 매달 나갑니다.
resource "aws_cloudwatch_log_group" "app" {
  for_each = var.log_groups

  name              = each.key
  retention_in_days = each.value.retention_days

  # Infrequent Access 클래스 — 저장 비용이 낮습니다.
  # 대가: Live Tail, 메트릭 필터, 구독 필터를 못 씁니다.
  # "규정 때문에 남기지만 평소에 안 보는" 로그에 적합합니다.
  log_group_class = each.value.infrequent_access ? "INFREQUENT_ACCESS" : "STANDARD"
}

# ── 메트릭 필터 ────────────────────────────────────────────────────
#
# 로그를 뒤져서 세는 대신, 들어올 때 지표로 바꿔 둡니다.
#
#   Logs Insights 쿼리 : 스캔한 데이터만큼 과금
#   메트릭 필터        : 필터 자체는 무료, 생성된 커스텀 지표만 과금
#
# "5분마다 에러 수를 세는 대시보드"를 Insights로 만들면
# 매 5분마다 로그를 다시 스캔합니다. 메트릭 필터로 바꾸면 한 번만 셉니다.
resource "aws_cloudwatch_log_metric_filter" "errors" {
  for_each = { for k, v in var.log_groups : k => v if !v.infrequent_access }

  name           = "${replace(each.key, "/", "-")}-errors"
  log_group_name = aws_cloudwatch_log_group.app[each.key].name

  # JSON 로그면 { $.level = "ERROR" }, 평문이면 아래처럼.
  pattern = var.log_format == "json" ? "{ $.level = \"ERROR\" || $.level = \"FATAL\" }" : "?ERROR ?FATAL ?Exception"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "${local.name}/App"
    value     = "1"
    # ★ default_value를 주지 않으면 에러가 없는 기간에 데이터가
    #   아예 없습니다. 그러면 알람이 INSUFFICIENT_DATA로 빠지고
    #   "에러가 없는 것"과 "수집이 멈춘 것"을 구분할 수 없습니다.
    default_value = 0
    unit          = "Count"
  }
}

# 지연시간을 로그에서 추출 — 앱이 구조화 로그를 찍는다면 이쪽이
# APM보다 훨씬 쌉니다.
resource "aws_cloudwatch_log_metric_filter" "latency" {
  for_each = var.log_format == "json" ? { for k, v in var.log_groups : k => v if !v.infrequent_access } : {}

  name           = "${replace(each.key, "/", "-")}-latency"
  log_group_name = aws_cloudwatch_log_group.app[each.key].name
  pattern        = "{ $.duration_ms = * }"

  metric_transformation {
    name      = "LatencyMs"
    namespace = "${local.name}/App"
    value     = "$.duration_ms"
    unit      = "Milliseconds"
  }
}

# ── 알람 ───────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name        = "${local.name}-error-rate"
  alarm_description = "애플리케이션 에러가 임계값을 넘었습니다"

  namespace           = "${local.name}/App"
  metric_name         = "ErrorCount"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.error_threshold
  comparison_operator = "GreaterThanThreshold"

  # ★ missing_data 처리가 알람 설계의 핵심입니다.
  #
  #   notBreaching — 데이터 없음을 "정상"으로. 수집이 멈춰도 조용합니다.
  #   breaching    — 데이터 없음을 "장애"로. 배포 중에 오탐이 납니다.
  #   missing      — 상태 유지 (기본값)
  #
  # 에러 카운트에는 default_value = 0 을 줬으므로 notBreaching이 맞습니다.
  # "수집이 멈춤"은 별도 알람(아래 heartbeat)으로 잡습니다.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ALB 5xx — 앱 로그가 아니라 LB 관점
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = var.alb_arn_suffix == "" ? 0 : 1

  alarm_name          = "${local.name}-alb-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2 # 3번 중 2번 — 순간 스파이크를 흘려보냅니다
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# p99 지연 — 평균이 아니라 분위수로 봅니다.
# 평균 200ms는 "90%가 50ms, 10%가 1.5초"일 수 있습니다.
resource "aws_cloudwatch_metric_alarm" "latency_p99" {
  count = var.alb_arn_suffix == "" ? 0 : 1

  alarm_name          = "${local.name}-latency-p99"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  extended_statistic  = "p99"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.latency_p99_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── 복합 알람 — 알람 피로를 줄이는 장치 ────────────────────────────
#
# 배포 중에는 5xx가 잠깐 뜨는 게 정상입니다. 그때마다 호출되면
# 사람들이 알람을 무시하게 됩니다 — 그게 진짜 장애를 놓치는 경로입니다.
#
# "5xx가 많다" AND "지연도 높다"일 때만 호출합니다.
resource "aws_cloudwatch_composite_alarm" "page" {
  count = var.alb_arn_suffix == "" ? 0 : 1

  alarm_name        = "${local.name}-PAGE"
  alarm_description = "둘 다 울릴 때만 사람을 깨웁니다"

  alarm_rule = join(" AND ", [
    "ALARM(${aws_cloudwatch_metric_alarm.alb_5xx[0].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.latency_p99[0].alarm_name})",
  ])

  alarm_actions = [aws_sns_topic.alerts.arn]

  # 배포 중 알람을 억제하려면 "배포 진행 중" 알람을 만들어
  # actions_suppressor로 지정합니다.
  # actions_suppressor            = aws_cloudwatch_metric_alarm.deploying.alarm_name
  # actions_suppressor_wait_period = 120
}

# 수집이 멈춘 것을 잡는 알람 — 위 에러 알람과 역할이 다릅니다
resource "aws_cloudwatch_metric_alarm" "heartbeat" {
  count = var.alb_arn_suffix == "" ? 0 : 1

  alarm_name          = "${local.name}-no-traffic"
  alarm_description   = "요청이 아예 없습니다 — 장애이거나 지표 수집이 멈췄습니다"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "RequestCount"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching" # ★ 여기서는 breaching이 맞습니다

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── 대시보드 ───────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type = "metric", x = 0, y = 0, width = 12, height = 6
          properties = {
            title  = "에러 수"
            region = data.aws_region.current.region
            metrics = [
              ["${local.name}/App", "ErrorCount", { stat = "Sum" }],
            ]
            period = 300
            view   = "timeSeries"
            # 알람 임계값을 그래프에 그려 넣습니다 —
            # "이 선을 넘으면 호출된다"가 눈에 보여야 합니다.
            annotations = {
              horizontal = [{ label = "임계값", value = var.error_threshold }]
            }
          }
        },
      ],
      var.alb_arn_suffix == "" ? [] : [
        {
          type = "metric", x = 12, y = 0, width = 12, height = 6
          properties = {
            title  = "응답 시간 (p50 / p99)"
            region = data.aws_region.current.region
            metrics = [
              ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50", label = "p50" }],
              ["...", { stat = "p99", label = "p99" }],
            ]
            period = 60
            view   = "timeSeries"
          }
        },
        {
          type = "metric", x = 0, y = 6, width = 12, height = 6
          properties = {
            title  = "요청 / 4xx / 5xx"
            region = data.aws_region.current.region
            metrics = [
              ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
              [".", "HTTPCode_Target_4XX_Count", ".", ".", { stat = "Sum" }],
              [".", "HTTPCode_Target_5XX_Count", ".", ".", { stat = "Sum" }],
            ]
            period = 60
            view   = "timeSeries"
          }
        },
      ],
      [
        {
          # Logs Insights 위젯. 대시보드를 열 때마다 쿼리가 돌고
          # 스캔한 만큼 과금됩니다 — 기간을 좁게 두세요.
          type = "log", x = 12, y = 6, width = 12, height = 6
          properties = {
            title  = "최근 에러 (1시간)"
            region = data.aws_region.current.region
            query  = "SOURCE '${keys(var.log_groups)[0]}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
            view   = "table"
          }
        },
      ],
    )
  })
}

# ── 합성 모니터링 (Synthetics) ─────────────────────────────────────
#
# 지표·로그는 "안에서 보는 것"입니다. DNS가 깨지거나 인증서가 만료되면
# 안에서는 전부 정상으로 보입니다. Canary는 밖에서 찔러봅니다.
#
# 가장 많이 잡히는 사고: 인증서 만료, DNS 전파 실패, CDN 캐시 오류.
resource "aws_s3_bucket" "canary" {
  count         = var.enable_canary ? 1 : 0
  bucket        = "${local.name}-canary-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "canary" {
  count                   = var.enable_canary ? 1 : 0
  bucket                  = aws_s3_bucket.canary[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "canary" {
  count = var.enable_canary ? 1 : 0
  name  = "${local.name}-canary"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "canary" {
  count = var.enable_canary ? 1 : 0
  name  = "inline"
  role  = aws_iam_role.canary[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetBucketLocation"]
        Resource = ["${aws_s3_bucket.canary[0].arn}", "${aws_s3_bucket.canary[0].arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/cwsyn-*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "CloudWatchSynthetics" }
        }
      },
    ]
  })
}

resource "aws_synthetics_canary" "http" {
  count = var.enable_canary ? 1 : 0

  name                 = substr("${var.project}${var.environment}http", 0, 21) # 이름 21자 제한
  artifact_s3_location = "s3://${aws_s3_bucket.canary[0].bucket}/canary/"
  execution_role_arn   = aws_iam_role.canary[0].arn
  handler              = "pageLoadBlueprint.handler"
  runtime_version      = var.canary_runtime
  zip_file             = "${path.module}/canary/canary.zip"

  start_canary = true

  schedule {
    expression = "rate(5 minutes)" # 1분으로 줄이면 비용이 5배
  }

  run_config {
    timeout_in_seconds = 60
    memory_in_mb       = 960
    active_tracing     = false
  }

  success_retention_period = 2  # 성공 스크린샷을 오래 둘 이유가 없습니다
  failure_retention_period = 14 # 실패는 조사해야 하니 길게
}

resource "aws_cloudwatch_metric_alarm" "canary" {
  count = var.enable_canary ? 1 : 0

  alarm_name          = "${local.name}-canary-failed"
  namespace           = "CloudWatchSynthetics"
  metric_name         = "SuccessPercent"
  dimensions          = { CanaryName = aws_synthetics_canary.http[0].name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 90
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
}
