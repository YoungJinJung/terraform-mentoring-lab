# ─────────────────────────────────────────────────────────────────────
# Karpenter v1 — API가 v1beta1에서 완전히 바뀌었습니다.
#
#   v1alpha5         v1beta1              v1  (현재)
#   ───────────────  ───────────────────  ──────────────────
#   Provisioner      NodePool             NodePool
#   AWSNodeTemplate  EC2NodeClass         EC2NodeClass
#   (없음)           NodeClaim            NodeClaim
#
# 오래된 블로그의 Provisioner YAML은 지금 적용되지 않습니다.
# ─────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "karpenter" {
  count = var.enable_karpenter ? 1 : 0
  name  = "${local.name}-karpenter"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
}

resource "aws_eks_pod_identity_association" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter[0].arn

  depends_on = [aws_eks_addon.pod_identity]
}

# Karpenter가 노드를 띄우려면 EC2 권한이 필요합니다.
# 공식 모듈(terraform-aws-modules/eks/aws//modules/karpenter)을 쓰면
# 이 정책과 SQS 중단 큐까지 만들어 줍니다. 여기서는 구조를 보여주려고
# 직접 씁니다.
resource "aws_iam_role_policy" "karpenter" {
  count = var.enable_karpenter ? 1 : 0
  name  = "karpenter"
  role  = aws_iam_role.karpenter[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowScopedEC2Launch"
        Effect   = "Allow"
        Action   = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
            # ★ 태그 조건이 없으면 Karpenter 역할로 아무 인스턴스나
            #   띄울 수 있습니다. 반드시 클러스터로 묶으세요.
            "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}" = "owned"
          }
        }
      },
      {
        Sid      = "AllowScopedTermination"
        Effect   = "Allow"
        Action   = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.this.name}" = "owned"
          }
        }
      },
      {
        Sid      = "AllowRead"
        Effect   = "Allow"
        Action   = ["ec2:Describe*", "pricing:GetProducts", "ssm:GetParameter", "eks:DescribeCluster"]
        Resource = "*"
      },
      {
        Sid      = "AllowPassNodeRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.node.arn
      },
      {
        Sid      = "AllowInterruptionQueue"
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = var.enable_karpenter ? aws_sqs_queue.karpenter[0].arn : "*"
      },
    ]
  })
}

# Spot 중단·인스턴스 재시작 이벤트를 받는 큐.
# 이게 없으면 Spot 노드가 예고 없이 사라지고 파드가 같이 죽습니다.
resource "aws_sqs_queue" "karpenter" {
  count                     = var.enable_karpenter ? 1 : 0
  name                      = "${local.name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  count       = var.enable_karpenter ? 1 : 0
  name        = "${local.name}-spot-interruption"
  description = "Spot 회수 2분 경고"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  count = var.enable_karpenter ? 1 : 0
  rule  = aws_cloudwatch_event_rule.spot_interruption[0].name
  arn   = aws_sqs_queue.karpenter[0].arn
}

# Karpenter가 노드를 배치할 서브넷·보안그룹을 찾는 방법은 **태그**입니다.
# 모듈 2에서 서브넷에 karpenter.sh/discovery 태그를 붙여두세요.
resource "aws_ec2_tag" "karpenter_subnets" {
  for_each = var.enable_karpenter ? toset(var.private_subnet_ids) : toset([])

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = aws_eks_cluster.this.name
}
