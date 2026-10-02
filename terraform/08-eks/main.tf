# ─────────────────────────────────────────────────────────────────────
# 모듈 8 · EKS
#
# 이 모듈에서 반드시 짚는 네 가지
#
#   1. upgradePolicy.supportType — 기본값이 EXTENDED입니다.
#      시간당 $0.10 → $0.60. 안 보고 두면 6배입니다.
#   2. aws-auth ConfigMap은 폐기(deprecated) → Access Entry
#   3. IRSA vs Pod Identity
#   4. Karpenter v1 — Provisioner/AWSNodeTemplate은 사라졌습니다
# ─────────────────────────────────────────────────────────────────────

locals {
  name = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ── 클러스터 역할 ──────────────────────────────────────────────────
resource "aws_iam_role" "cluster" {
  name = "${local.name}-eks-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
    # EKS Auto Mode / 블록 스토리지·로드밸런서를 EKS가 직접 관리하게 할 때
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSComputePolicy",
  ])
  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

# ── 클러스터 ───────────────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = local.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    # 공개 엔드포인트를 쓸 거면 CIDR을 반드시 좁히세요.
    # 기본값 0.0.0.0/0은 "API 서버를 인터넷에 공개"입니다.
    public_access_cidrs = var.public_access_cidrs
  }

  # ★★ 1. 지원 정책 ★★
  #
  #   STANDARD — 표준 지원 기간만. 기간이 끝나면 **자동 업그레이드**됩니다.
  #   EXTENDED — 연장 지원. 시간당 $0.60 (표준 $0.10). 기본값.
  #
  # "업그레이드 안 하고 버티기"에 6배 요금이 붙는 구조입니다.
  # 업그레이드 주기를 지킬 수 있다면 STANDARD로 두고,
  # 자동 업그레이드를 감지할 알람을 붙이세요.
  upgrade_policy {
    support_type = var.support_type
  }

  # ★★ 2. 인증 모드 ★★
  #
  #   CONFIG_MAP       — 옛 방식. aws-auth ConfigMap만.
  #   API_AND_CONFIG_MAP — 전환기용
  #   API              — Access Entry만. 새 클러스터는 이것.
  #
  # aws-auth는 "ConfigMap을 잘못 고치면 아무도 못 들어오는" 구조였습니다.
  # Access Entry는 IAM API라서 Terraform으로 안전하게 다룹니다.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_creator_admin
  }

  # 감사 로그. 끄면 "누가 무엇을 했는지"가 남지 않습니다.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # 비밀 암호화 — KMS 키를 주면 etcd의 Secret이 봉투 암호화됩니다
  dynamic "encryption_config" {
    for_each = var.kms_key_arn == "" ? [] : [1]
    content {
      provider { key_arn = var.kms_key_arn }
      resources = ["secrets"]
    }
  }

  # EKS Auto Mode — 노드 그룹·Karpenter·CSI·LB 컨트롤러를 EKS가 관리합니다.
  # 편한 대신 노드 설정 자유도가 줄고, 컴퓨팅에 관리 비용이 얹힙니다.
  dynamic "compute_config" {
    for_each = var.auto_mode ? [1] : []
    content {
      enabled       = true
      node_pools    = ["general-purpose", "system"]
      node_role_arn = aws_iam_role.node.arn
    }
  }

  dynamic "kubernetes_network_config" {
    for_each = var.auto_mode ? [1] : []
    content {
      elastic_load_balancing { enabled = true }
    }
  }

  dynamic "storage_config" {
    for_each = var.auto_mode ? [1] : []
    content {
      block_storage { enabled = true }
    }
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# ── 노드 역할 ──────────────────────────────────────────────────────
resource "aws_iam_role" "node" {
  name = "${local.name}-eks-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ── 관리형 노드 그룹 (Auto Mode가 아닐 때) ─────────────────────────
resource "aws_eks_node_group" "default" {
  count = var.auto_mode ? 0 : 1

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  # Karpenter를 쓸 거라면 이 노드 그룹은 "Karpenter 자신을 띄울 자리"입니다.
  # 2대면 충분합니다. 나머지는 Karpenter가 띄웁니다.
  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"

  # 노드를 한 번에 몇 개까지 교체할지. 기본 1은 느립니다.
  update_config {
    max_unavailable_percentage = 33
  }

  lifecycle {
    # Cluster Autoscaler/Karpenter가 바꾸는 값을 되돌리지 않게
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ── OIDC 공급자 (IRSA용) ───────────────────────────────────────────
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
}

# ── 애드온 ─────────────────────────────────────────────────────────
#
# ★★ 3. Pod Identity vs IRSA ★★
#
#   IRSA         : OIDC 공급자 + 신뢰 정책에 OIDC sub 조건.
#                  클러스터마다 공급자가 하나씩 생기고, 역할 신뢰 정책에
#                  클러스터 OIDC URL이 박힙니다 → 클러스터를 새로 만들면
#                  역할을 다 고쳐야 합니다.
#   Pod Identity : eks-pod-identity-agent 애드온 + Association 리소스.
#                  신뢰 정책은 pods.eks.amazonaws.com 하나로 끝.
#                  클러스터를 바꿔도 역할을 안 고칩니다.
#
# 새로 만든다면 Pod Identity. 단 Fargate에서는 아직 IRSA만 됩니다.
resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"

  # 애드온 설정이 손으로 바뀌어 있을 때 어떻게 할지
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  configuration_values = jsonencode({
    env = {
      # Prefix delegation — 노드당 파드 수 한계를 크게 늘립니다.
      # 이걸 안 켜면 m5.large에 파드 29개가 상한입니다.
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })
}

resource "aws_eks_addon" "coredns" {
  count        = var.auto_mode ? 0 : 1
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"

  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.default]
}

resource "aws_eks_addon" "kube_proxy" {
  count        = var.auto_mode ? 0 : 1
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_create = "OVERWRITE"
}

# ── Access Entry ───────────────────────────────────────────────────
#
# aws-auth ConfigMap을 대체합니다. 비교:
#
#   예전:  kubectl edit configmap aws-auth -n kube-system
#          → YAML 들여쓰기 하나 틀리면 전원 접근 불가
#   지금:  aws_eks_access_entry + aws_eks_access_policy_association
#          → plan으로 검토, 롤백 가능
resource "aws_eks_access_entry" "admins" {
  for_each = toset(var.admin_role_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admins" {
  for_each = toset(var.admin_role_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# 개발자에게는 특정 네임스페이스만
resource "aws_eks_access_entry" "developers" {
  for_each = toset(var.developer_role_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "developers" {
  for_each = toset(var.developer_role_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = var.developer_namespaces
  }
}

# ── Pod Identity 예시 — 앱이 S3를 읽게 ─────────────────────────────
resource "aws_iam_role" "app_pod" {
  name = "${local.name}-app-pod"

  # ★ IRSA와 비교해 보세요. 클러스터 OIDC URL이 안 들어갑니다.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
}

resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.app_namespace
  service_account = var.app_service_account
  role_arn        = aws_iam_role.app_pod.arn

  depends_on = [aws_eks_addon.pod_identity]
}
