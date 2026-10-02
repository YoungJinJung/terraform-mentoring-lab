# ──────────────────────────────────────────────────────────────
# 모듈 2 · VPC — 이후 모든 모듈이 올라탈 네트워크
#
# Floci 주의: VPC·서브넷·라우팅은 API 객체로 만들어지지만
# 실제 패킷은 흐르지 않습니다. 구조를 코드로 익히는 용도이고,
# 통신 검증은 실제 AWS에서 하세요.
# ──────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "subnets" {
  description = "tier는 public | private | isolated"
  type = map(object({
    cidr = string
    az   = string
    tier = string
  }))
  default = {
    "public-a"   = { cidr = "10.10.0.0/24", az = "a", tier = "public" }
    "public-c"   = { cidr = "10.10.1.0/24", az = "c", tier = "public" }
    "private-a"  = { cidr = "10.10.16.0/22", az = "a", tier = "private" }
    "private-c"  = { cidr = "10.10.20.0/22", az = "c", tier = "private" }
    "isolated-a" = { cidr = "10.10.48.0/24", az = "a", tier = "isolated" }
    "isolated-c" = { cidr = "10.10.49.0/24", az = "c", tier = "isolated" }
  }
}

variable "nat_strategy" {
  description = "none | single | per_az — 바꿔가며 plan 차이를 보세요"
  type        = string
  default     = "single"

  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_strategy)
    error_message = "nat_strategy는 none, single, per_az 중 하나여야 합니다."
  }
}

locals {
  public   = { for k, v in var.subnets : k => v if v.tier == "public" }
  private  = { for k, v in var.subnets : k => v if v.tier == "private" }
  isolated = { for k, v in var.subnets : k => v if v.tier == "isolated" }

  # NAT를 몇 개 만들지 — 이 표현식이 모듈 2의 핵심 실습입니다
  nat_keys = (
    var.nat_strategy == "none" ? {} :
    var.nat_strategy == "single" ? { (keys(local.public)[0]) = 1 } :
    { for k, v in local.public : k => 1 }
  )
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # VPC Endpoint·Lattice가 요구합니다
  tags                 = { Name = local.name_prefix }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = "${var.region}${each.value.az}"
  map_public_ip_on_launch = each.value.tier == "public"

  tags = {
    Name = "${local.name_prefix}-${each.key}"
    Tier = each.value.tier
    # EKS가 LB를 띄울 서브넷을 찾는 데 쓰는 태그 — 빠뜨리면 모듈 8에서 막힙니다
    "kubernetes.io/role/${each.value.tier == "public" ? "elb" : "internal-elb"}" = "1"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = local.name_prefix }
}

resource "aws_eip" "nat" {
  for_each = local.nat_keys
  domain   = "vpc"
  tags     = { Name = "${local.name_prefix}-nat-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_keys

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[each.key].id
  tags          = { Name = "${local.name_prefix}-${each.key}" }

  depends_on = [aws_internet_gateway.this] # 참조가 없으니 명시
}

# ── 라우팅 ────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-rt-public" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = local.public
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# 프라이빗은 AZ마다 테이블을 따로 — 자기 AZ의 NAT를 보게 하려고
resource "aws_route_table" "private" {
  for_each = local.private
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${local.name_prefix}-rt-${each.key}" }
}

resource "aws_route" "private_nat" {
  for_each = length(local.nat_keys) > 0 ? local.private : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id = var.nat_strategy == "per_az" ? (
    [for k, s in local.public : aws_nat_gateway.this[k].id if s.az == each.value.az][0]
  ) : values(aws_nat_gateway.this)[0].id
}

resource "aws_route_table_association" "private" {
  for_each       = local.private
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# isolated는 local 경로만 — 아웃바운드가 없습니다
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-rt-isolated" }
}

resource "aws_route_table_association" "isolated" {
  for_each       = local.isolated
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.isolated.id
}

# ── S3 Gateway Endpoint — 무료이고 NAT 요금을 없앱니다 ────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(values(aws_route_table.private)[*].id, [aws_route_table.isolated.id])
  tags              = { Name = "${local.name_prefix}-s3" }
}
