# ─────────────────────────────────────────────────────────────────────
# 모듈 6 · EC2 / ALB / Auto Scaling
#
#   · Launch Template (Launch Configuration은 신규 계정에서 아예 못 씁니다)
#   · IMDSv2 강제 — SSRF로 자격증명이 새는 가장 흔한 경로를 막습니다
#   · Instance Refresh로 무중단 교체, 그리고 롤백이 왜 기본값이 아닌지
#   · user_data 바꿀 때 왜 인스턴스가 안 바뀌는지 (이게 LAB 03)
# ─────────────────────────────────────────────────────────────────────

locals {
  name = "${var.project}-${var.environment}-web"
}

data "aws_ami" "al2023" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  # ★ most_recent = true 는 "매번 바뀔 수 있다"는 뜻입니다.
  #   운영에서는 SSM 파라미터로 버전을 고정하거나, AMI ID를 변수로
  #   받아 PR에 기록을 남기는 쪽을 권합니다.
  #   data "aws_ssm_parameter" "al2023" {
  #     name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  #   }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : try(data.aws_ami.al2023[0].id, "ami-00000000000000000")
}

# ── 보안 그룹 ──────────────────────────────────────────────────────
#
# aws_security_group_rule(구형) 대신 aws_vpc_security_group_*_rule을 씁니다.
# 구형은 하나의 리소스가 여러 CIDR을 품어서 plan이 지저분하고,
# 동시 수정 시 충돌이 납니다.
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB ingress"
  vpc_id      = var.vpc_id

  # 인라인 규칙을 쓰지 않는다는 선언. 섞어 쓰면 서로 지웁니다.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "실습용 HTTP. 운영에서는 443만."
  cidr_ipv4         = var.ingress_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "ALB에서만 받습니다"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

# ★ CIDR이 아니라 "소스 보안 그룹"으로 엽니다.
#   서브넷 CIDR로 열면 그 서브넷의 모든 것이 들어옵니다.
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ── 인스턴스 역할 — SSM Session Manager로 접속 (키 페어 없음) ──────
resource "aws_iam_role" "app" {
  name = "${local.name}-instance"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# 22번 포트를 아예 열지 않고 SSM으로 들어갑니다.
# 베스티온 호스트와 키 관리가 통째로 사라집니다.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name}-instance"
  role = aws_iam_role.app.name
}

# ── Launch Template ────────────────────────────────────────────────
#
# Launch Configuration은 2023-12 이후 신규 생성 불가,
# 2024-10-01 이후에 만든 계정은 **기존 것도 못 씁니다**.
# 오래된 블로그를 보고 LC로 시작하면 바로 막힙니다.
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-"
  image_id      = local.ami_id
  instance_type = var.instance_type

  iam_instance_profile { arn = aws_iam_instance_profile.app.arn }
  vpc_security_group_ids = [aws_security_group.app.id]

  # ★★ IMDSv2 강제 ★★
  #
  # http_tokens = "required"  → PUT으로 토큰을 먼저 받아야 메타데이터 접근 가능.
  #                             단순 SSRF(GET 한 번)로는 자격증명을 못 빼냅니다.
  # hop_limit   = 1           → 컨테이너/프록시를 한 번 거치면 못 닿습니다.
  #                             EC2에 직접 띄우는 앱이면 1, ECS bridge 모드면 2.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring { enabled = true }

  # user_data는 base64입니다. templatefile로 바깐 값이 바뀌면
  # 템플릿 해시가 바뀌고 → LT 새 버전이 생깁니다.
  # 하지만 ASG의 기존 인스턴스는 **스스로 바뀌지 않습니다** (LAB 03).
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    app_port = 8080
    message  = var.app_message
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = local.name }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── ALB ────────────────────────────────────────────────────────────
resource "aws_lb" "this" {
  name               = local.name
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  # 실습에서는 false로 두면 destroy가 편합니다. 운영에서는 true.
  enable_deletion_protection = false
  drop_invalid_header_fields = true
  idle_timeout               = 60
}

resource "aws_lb_target_group" "app" {
  name     = local.name
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # ALB가 인스턴스를 빼기 전에 기다리는 시간.
  # 기본 300초는 실습에서 너무 깁니다.
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # TG는 ALB보다 먼저 만들어지고 나중에 지워져야 합니다.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── Auto Scaling Group ─────────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                = local.name
  vpc_zone_identifier = var.private_subnet_ids

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # ★ ELB 헬스체크를 켜야 "떠 있지만 응답 안 하는" 인스턴스가 교체됩니다.
  #   기본값 EC2는 "인스턴스가 살아 있는가"만 봅니다.
  health_check_type         = "ELB"
  health_check_grace_period = 120

  target_group_arns = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # 한 AZ에 몰리지 않게
  instance_maintenance_policy {
    min_healthy_percentage = 90
    max_healthy_percentage = 110
  }

  # ★★ Instance Refresh ★★
  #
  # LT가 바뀌면 자동으로 롤링 교체합니다.
  # auto_rollback 기본값은 false입니다 — 새 버전이 전부 unhealthy여도
  # 멈춘 상태로 끝납니다. 켜두는 걸 권합니다.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
      instance_warmup        = 120
      auto_rollback          = true
      # 체크포인트를 쓰면 "10% 교체 후 5분 멈춤"처럼 단계적으로 갈 수 있습니다.
      # checkpoint_percentages = [10, 50, 100]
      # checkpoint_delay       = 300
    }
    # user_data 변경을 교체 트리거로 인정하려면 LT 버전이 바뀌어야 하고,
    # 위 launch_template.version = latest_version 설정이 그 역할을 합니다.
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = local.name
    propagate_at_launch = true
  }

  lifecycle {
    # desired_capacity는 스케일링 정책이 바꿉니다.
    # Terraform이 매번 되돌리면 안 됩니다.
    ignore_changes = [desired_capacity]
  }
}

# ── 스케일링 정책 ──────────────────────────────────────────────────
#
# Target Tracking을 씁니다. Step Scaling은 임계값·쿨다운을 손으로
# 맞춰야 하고, 대부분의 경우 Target Tracking이 더 잘 동작합니다.
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${local.name}-cpu"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}

# ALB 요청 수 기준 — CPU보다 앱 부하를 잘 반영하는 경우가 많습니다.
resource "aws_autoscaling_policy" "requests" {
  name                   = "${local.name}-rps"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 1000
  }
}
