# ─────────────────────────────────────────────────────────────────────
# 모듈 7 · ECS on Fargate
#
# 이 모듈의 주제는 **배포 전략**입니다.
#
#   2025-07부터 ECS가 Blue/Green·Canary·Linear를 네이티브로 지원합니다.
#   그 전에는 CodeDeploy(deployment_controller.type = "CODE_DEPLOY")를
#   붙이고 appspec.yaml을 따로 관리해야 했습니다.
#
#   provider는 aws v6.4.0 이상이 필요합니다.
# ─────────────────────────────────────────────────────────────────────

locals {
  name = "${var.project}-${var.environment}-app"
}

# ── 클러스터 ───────────────────────────────────────────────────────
resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enhanced" : "disabled"
  }
}

# Fargate / Fargate Spot 비중을 정합니다.
# Spot은 2분 경고 후 회수됩니다 — 무상태 워커에만.
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = var.on_demand_base # 최소 이만큼은 온디맨드로
    weight            = 1
  }

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    base              = 0
    weight            = var.spot_weight
  }
}

# ── 로그 ───────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days # 기본 "영구"는 돈이 샙니다
}

# ── 역할 두 개 — 이 구분이 시험·면접 단골입니다 ───────────────────
#
#   execution_role : ECS 에이전트가 씀. ECR pull, 로그 쓰기, 비밀 주입.
#   task_role      : 컨테이너 안의 앱이 씀. S3 읽기, SQS 등.
#
# 섞어 쓰면 앱이 ECR·로그 권한까지 들고 돕니다.
resource "aws_iam_role" "execution" {
  name = "${local.name}-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${local.name}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

# ECS Exec(컨테이너 셸 접속)에 필요한 권한. task_role 쪽입니다.
resource "aws_iam_role_policy" "task_exec_ssm" {
  name = "ecs-exec"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}

# ── 보안 그룹 ──────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name   = "${local.name}-alb"
  vpc_id = var.vpc_id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.ingress_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Blue/Green 테스트 리스너용 포트. 운영 트래픽과 분리해서
# 새 버전을 먼저 찔러볼 수 있습니다.
resource "aws_vpc_security_group_ingress_rule" "alb_test" {
  count             = var.deployment_strategy == "ROLLING" ? 0 : 1
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.ingress_cidr
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "task" {
  name   = "${local.name}-task"
  vpc_id = var.vpc_id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  security_group_id            = aws_security_group.task.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "task_all" {
  security_group_id = aws_security_group.task.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ── ALB + 타깃 그룹 두 개 ──────────────────────────────────────────
#
# Blue/Green은 타깃 그룹 2개가 필요합니다. ECS가 둘 사이에서
# 리스너를 전환합니다. 롤링이면 하나만 씁니다.
resource "aws_lb" "this" {
  name                       = local.name
  load_balancer_type         = "application"
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "blue" {
  name        = "${local.name}-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # ★ Fargate는 awsvpc 모드 → 반드시 "ip"

  deregistration_delay = 30

  health_check {
    path                = "/health"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_lb_target_group" "green" {
  count       = var.deployment_strategy == "ROLLING" ? 0 : 1
  name        = "${local.name}-green"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    path                = "/health"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # ★ ECS가 배포 중에 이 리스너의 타깃 그룹을 바꿉니다.
  #   Terraform이 그걸 되돌리면 배포가 깨집니다.
  lifecycle {
    ignore_changes = [default_action]
  }
}

resource "aws_lb_listener" "test" {
  count             = var.deployment_strategy == "ROLLING" ? 0 : 1
  load_balancer_arn = aws_lb.this.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green[0].arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# ── 태스크 정의 ────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture # ARM64가 x86보다 ~20% 쌉니다
  }

  container_definitions = jsonencode([{
    name      = "app"
    image     = var.image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
      # 이름을 주면 Service Connect에서 참조할 수 있습니다
      name = "http"
    }]

    environment = [
      { name = "APP_VERSION", value = var.app_version },
      { name = "PORT", value = tostring(var.container_port) },
    ]

    # ★ 컨테이너 자체 헬스체크. ALB 헬스체크와 별개입니다.
    #   둘 다 있어야 "ALB는 뺐는데 컨테이너는 살아 있는" 상태를 피합니다.
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:${var.container_port}/health || exit 1"]
      interval    = 10
      timeout     = 5
      retries     = 3
      startPeriod = 20
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "app"
      }
    }

    # 읽기 전용 루트 파일시스템 — 컨테이너가 침해돼도 바이너리를 못 심습니다.
    readonlyRootFilesystem = var.readonly_root
    linuxParameters = {
      initProcessEnabled = true # PID 1 좀비 프로세스 방지
    }
  }])
}

# ── 서비스 ─────────────────────────────────────────────────────────
resource "aws_ecs_service" "app" {
  name            = local.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count

  enable_execute_command = true # ECS Exec

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false # 프라이빗 서브넷 + NAT 또는 VPC 엔드포인트
  }

  # ★★ 2025-07 네이티브 배포 ★★
  #
  #   type = "ECS"  + strategy = "BLUE_GREEN" | "CANARY" | "LINEAR" | 미지정(=롤링)
  #
  # 예전 방식: type = "CODE_DEPLOY" + aws_codedeploy_* 3개 + appspec.yaml
  deployment_controller {
    type = "ECS"
  }

  deployment_configuration {
    strategy = var.deployment_strategy == "ROLLING" ? null : var.deployment_strategy

    # 전환 후 이만큼 지켜본 뒤 옛 버전을 내립니다.
    # 0으로 두면 "전환 즉시 롤백 불가"가 됩니다.
    bake_time_in_minutes = var.deployment_strategy == "ROLLING" ? null : var.bake_time_minutes

    # CANARY / LINEAR일 때만 의미가 있습니다
    dynamic "lifecycle_hook" {
      for_each = var.validation_lambda_arn == "" ? [] : [1]
      content {
        hook_target_arn  = var.validation_lambda_arn
        role_arn         = aws_iam_role.execution.arn
        lifecycle_stages = ["POST_TEST_TRAFFIC_SHIFT"]
      }
    }
  }

  # ★ 롤링일 때만 유효합니다. Blue/Green에는 circuit breaker가 없습니다
  #   (대신 bake time 중 알람으로 롤백합니다).
  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_strategy == "ROLLING" ? [1] : []
    content {
      enable   = true
      rollback = true
    }
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "app"
    container_port   = var.container_port

    # Blue/Green 전환에 필요한 정보
    dynamic "advanced_configuration" {
      for_each = var.deployment_strategy == "ROLLING" ? [] : [1]
      content {
        alternate_target_group_arn = aws_lb_target_group.green[0].arn
        production_listener_rule   = aws_lb_listener.prod.arn
        test_listener_rule         = aws_lb_listener.test[0].arn
        role_arn                   = aws_iam_role.ecs_deploy[0].arn
      }
    }
  }

  # 배포 중 ALB가 안정화될 시간을 줍니다.
  health_check_grace_period_seconds = 60

  # CI가 태스크 정의를 올리는 구성이면 아래를 켜세요.
  # lifecycle { ignore_changes = [task_definition, desired_count] }

  depends_on = [aws_lb_listener.prod]
}

# Blue/Green 전환에 쓰는 역할 — ECS가 리스너를 바꾸려면 필요합니다
resource "aws_iam_role" "ecs_deploy" {
  count = var.deployment_strategy == "ROLLING" ? 0 : 1
  name  = "${local.name}-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_deploy" {
  count      = var.deployment_strategy == "ROLLING" ? 0 : 1
  role       = aws_iam_role.ecs_deploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

# ── 오토스케일링 ───────────────────────────────────────────────────
resource "aws_appautoscaling_target" "app" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 60

    # 스케일 인은 천천히, 스케일 아웃은 빠르게.
    scale_in_cooldown  = 300
    scale_out_cooldown = 30
  }
}
