#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# Floci 실습 가능 범위 실측 스크립트
#
# 자료에 "된다/안 된다"를 추측으로 쓰지 않기 위해, 모듈별로 실제 API를
# 때려보고 결과를 표로 남깁니다. 결과는 docs/FLOCI-SUPPORT.md 에 씁니다.
#
#   ./smoke-test.sh            # 전체
#   ./smoke-test.sh 01 02 03   # 특정 모듈만
# ──────────────────────────────────────────────────────────────────────
set -uo pipefail

ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION="$REGION" AWS_ENDPOINT_URL="$ENDPOINT"
export AWS_PAGER=""

OUT="${OUT:-$(cd "$(dirname "$0")/../.." && pwd)/docs/FLOCI-SUPPORT.md}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; SKIP=0
ROWS=()

c_g(){ printf '\033[32m%s\033[0m' "$1"; }
c_r(){ printf '\033[31m%s\033[0m' "$1"; }
c_y(){ printf '\033[33m%s\033[0m' "$1"; }
c_d(){ printf '\033[2m%s\033[0m' "$1"; }

# check <모듈> <항목> <비고> <명령...>
check() {
  local mod="$1" name="$2" note="$3"; shift 3
  printf '  %-34s ' "$name"
  if out=$("$@" 2>&1); then
    c_g "OK"; echo
    ROWS+=("$mod|$name|OK|$note")
    PASS=$((PASS+1))
  else
    local msg
    msg=$(echo "$out" | grep -oE '(NotImplemented|InvalidAction|UnknownOperation|501|Unsupported[A-Za-z]*|AccessDenied|ValidationException)' | head -1)
    msg="${msg:-실패}"
    c_r "NO"; c_d "  ($msg)"; echo
    ROWS+=("$mod|$name|NO|${note:+$note · }$msg")
    FAIL=$((FAIL+1))
  fi
}

skip() {
  local mod="$1" name="$2" note="$3"
  printf '  %-34s ' "$name"; c_y "SKIP"; c_d "  ($note)"; echo
  ROWS+=("$mod|$name|SKIP|$note")
  SKIP=$((SKIP+1))
}

want() { [ ${#WANT[@]} -eq 0 ] && return 0; for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }

WANT=("$@")

echo
echo "  엔드포인트  $ENDPOINT"
echo "  리전        $REGION"
echo

if ! curl -sf --max-time 5 "$ENDPOINT" >/dev/null 2>&1; then
  c_r "  Floci에 연결할 수 없습니다. 'make up' 먼저 실행하세요."; echo; exit 1
fi
command -v aws >/dev/null || { c_r "  aws CLI가 필요합니다."; echo; exit 1; }

B="tfm-smoke-$$"

# ── 모듈 1 · 기초 ───────────────────────────────────────────────────
if want 01; then
echo "모듈 01 · 기초 (state · backend)"
check 01 "S3 버킷 생성" "" \
  aws s3api create-bucket --bucket "$B" --create-bucket-configuration LocationConstraint="$REGION"
check 01 "S3 버전 관리" "state 복구에 필요" \
  aws s3api put-bucket-versioning --bucket "$B" --versioning-configuration Status=Enabled
check 01 "S3 서버측 암호화" "state 보호" \
  aws s3api put-bucket-encryption --bucket "$B" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
# ★ S3 네이티브 잠금(use_lockfile)은 조건부 쓰기(If-None-Match)가 필요합니다.
echo hello > "$TMP/x"
check 01 "S3 조건부 쓰기 (use_lockfile 전제)" "Terraform 1.11+ 네이티브 잠금" \
  aws s3api put-object --bucket "$B" --key lock.tflock --body "$TMP/x" --if-none-match '*'
check 01 "DynamoDB 테이블 (레거시 잠금)" "deprecated 경로" \
  aws dynamodb create-table --table-name "$B" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
echo
fi

# ── 모듈 2 · 네트워크 ───────────────────────────────────────────────
if want 02; then
echo "모듈 02 · VPC · 네트워크"
VPC=$(aws ec2 create-vpc --cidr-block 10.10.0.0/16 --query 'Vpc.VpcId' --output text 2>/dev/null)
if [ -n "${VPC:-}" ] && [ "$VPC" != "None" ]; then
  printf '  %-34s ' "VPC 생성"; c_g "OK"; echo; ROWS+=("02|VPC 생성|OK|$VPC"); PASS=$((PASS+1))
  check 02 "서브넷 생성" "" aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 10.10.1.0/24
  check 02 "인터넷 게이트웨이" "" aws ec2 create-internet-gateway
  check 02 "라우팅 테이블" "" aws ec2 create-route-table --vpc-id "$VPC"
  check 02 "보안 그룹" "" aws ec2 create-security-group --group-name "$B" --description smoke --vpc-id "$VPC"
  check 02 "NAT 게이트웨이" "실제 트래픽은 흐르지 않음" \
    aws ec2 describe-nat-gateways
  check 02 "VPC 엔드포인트" "" aws ec2 describe-vpc-endpoints
  check 02 "VPC Peering" "" aws ec2 describe-vpc-peering-connections
  check 02 "Transit Gateway" "" aws ec2 describe-transit-gateways
else
  printf '  %-34s ' "VPC 생성"; c_r "NO"; echo; ROWS+=("02|VPC 생성|NO|"); FAIL=$((FAIL+1))
fi
check 02 "ELBv2 (ALB)" "" aws elbv2 describe-load-balancers
# VPC Lattice는 Floci 지원 서비스 목록에 없습니다 — 실측으로 확인
check 02 "VPC Lattice 서비스 네트워크" "미지원 예상" \
  aws vpc-lattice list-service-networks
echo
fi

# ── 모듈 3 · 권한 · 시크릿 ──────────────────────────────────────────
if want 03; then
echo "모듈 03 · IAM · KMS · 시크릿"
check 03 "IAM Role 생성" "" \
  aws iam create-role --role-name "$B" \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
check 03 "IAM 정책 연결" "" \
  aws iam put-role-policy --role-name "$B" --policy-name inline \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"s3:GetObject","Resource":"*"}]}'
check 03 "STS AssumeRole" "크로스 계정 실습 전제" \
  aws sts get-caller-identity
check 03 "KMS 키 생성" "SOPS 전제" aws kms create-key --description smoke
check 03 "KMS Encrypt/Decrypt" "SOPS 핵심" bash -c '
  K=$(aws kms create-key --description sops-smoke --query KeyMetadata.KeyId --output text) || exit 1
  C=$(aws kms encrypt --key-id "$K" --plaintext "$(printf secret | base64)" --query CiphertextBlob --output text) || exit 1
  aws kms decrypt --ciphertext-blob "$C" --query Plaintext --output text >/dev/null'
check 03 "Secrets Manager" "" \
  aws secretsmanager create-secret --name "$B" --secret-string '{"password":"smoke"}'
check 03 "SSM Parameter Store" "" \
  aws ssm put-parameter --name "/$B/x" --value smoke --type SecureString
check 03 "IAM OIDC Provider" "GitHub Actions OIDC 전제" \
  aws iam list-open-id-connect-providers
echo
fi

# ── 모듈 5 · CI/CD ─────────────────────────────────────────────────
if want 05; then
echo "모듈 05 · CI/CD"
check 05 "ECR 리포지토리" "" aws ecr create-repository --repository-name "$B"
check 05 "CodeBuild 프로젝트 조회" "API만 — 실제 빌드는 별개" aws codebuild list-projects
check 05 "CodeDeploy 조회" "" aws deploy list-applications
check 05 "CodePipeline 조회" "" aws codepipeline list-pipelines
echo
fi

# ── 모듈 6 · EC2 ───────────────────────────────────────────────────
if want 06; then
echo "모듈 06 · EC2"
check 06 "Launch Template" "" aws ec2 describe-launch-templates
check 06 "Auto Scaling Group" "" aws autoscaling describe-auto-scaling-groups
check 06 "ELBv2 타겟 그룹" "Blue/Green 전제" aws elbv2 describe-target-groups
skip   06 "EC2 인스턴스 기동" "Docker 컨테이너로 뜸 — 시간이 걸려 수동 확인 권장"
echo
fi

# ── 모듈 7 · ECS ───────────────────────────────────────────────────
if want 07; then
echo "모듈 07 · ECS"
check 07 "ECS 클러스터" "" aws ecs create-cluster --cluster-name "$B"
check 07 "Task Definition 등록" "" \
  aws ecs register-task-definition --family "$B" --network-mode awsvpc \
  --requires-compatibilities FARGATE --cpu 256 --memory 512 \
  --container-definitions '[{"name":"app","image":"nginx:alpine","essential":true}]'
check 07 "서비스 조회" "" aws ecs list-services --cluster "$B"
skip   07 "네이티브 Blue/Green (2025)" "deployment_configuration.strategy — 지원 가능성 낮음"
echo
fi

# ── 모듈 8 · EKS ───────────────────────────────────────────────────
if want 08; then
echo "모듈 08 · EKS"
check 08 "EKS 클러스터 조회" "k3s 기반" aws eks list-clusters
check 08 "Access Entry API" "aws-auth 대체 경로" bash -c '
  aws eks list-access-entries --cluster-name nonexistent 2>&1 | grep -qv "UnknownOperation"'
skip   08 "Pod Identity · IRSA" "IAM 연동 — 실제 AWS 필요"
skip   08 "Karpenter" "실제 EC2 인스턴스 타입 API 필요"
echo
fi

# ── 모듈 9 · Observability ─────────────────────────────────────────
if want 09; then
echo "모듈 09 · Observability"
check 09 "CloudWatch Logs" "" aws logs create-log-group --log-group-name "/$B"
check 09 "CloudWatch 메트릭" "" aws cloudwatch list-metrics
skip   09 "Datadog · Sumo Logic" "외부 SaaS — 무료 트라이얼 필요"
echo
fi

# ── 결과 ───────────────────────────────────────────────────────────
TOTAL=$((PASS+FAIL+SKIP))
echo "  ────────────────────────────────────────────"
printf '  총 %d  ·  ' "$TOTAL"; c_g "OK $PASS"; printf '  ·  '; c_r "NO $FAIL"; printf '  ·  '; c_y "SKIP $SKIP"; echo
echo

mkdir -p "$(dirname "$OUT")"
{
  echo "# Floci 실습 가능 범위"
  echo
  echo "> 이 문서는 \`lab/scripts/smoke-test.sh\`가 **실제로 API를 호출해 생성**합니다."
  echo "> 추측이 아니라 실측 결과입니다. 환경이 바뀌면 다시 돌리세요."
  echo
  echo "- 측정 시각: \`$(date '+%Y-%m-%d %H:%M:%S %Z')\`"
  echo "- 엔드포인트: \`$ENDPOINT\` · 리전: \`$REGION\`"
  echo "- 결과: **OK $PASS · NO $FAIL · SKIP $SKIP** (총 $TOTAL)"
  echo
  echo "| 모듈 | 항목 | 결과 | 비고 |"
  echo "|---|---|:--:|---|"
  for r in "${ROWS[@]}"; do
    IFS='|' read -r m n s t <<<"$r"
    case "$s" in
      OK)   s="✅" ;;
      NO)   s="❌" ;;
      SKIP) s="⏭️" ;;
    esac
    echo "| $m | $n | $s | $t |"
  done
  echo
  echo "## 읽는 법"
  echo
  echo "- ✅ 는 **API가 응답했다**는 뜻이지, 실제 동작까지 같다는 뜻은 아닙니다."
  echo "  특히 네트워크는 객체만 만들어지고 패킷은 흐르지 않습니다."
  echo "- ❌ 가 뜬 항목은 해당 실습을 실제 AWS에서 해야 합니다."
  echo "- ⏭️ 는 자동 판정이 어려워 수동 확인이 필요한 항목입니다."
} > "$OUT"

echo "  결과를 기록했습니다 → ${OUT#"$(pwd)/"}"
echo
[ "$FAIL" -eq 0 ]
