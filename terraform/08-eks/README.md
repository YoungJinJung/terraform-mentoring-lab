# 모듈 8 · EKS

> 자료: [`docs/part8-eks.html`](../../docs/part8-eks.html)

## 이 디렉터리에서 하는 것

| 실습 | 내용 |
|---|---|
| LAB 01 | 클러스터 + 노드 그룹 + 애드온, `kubectl get nodes` |
| LAB 02 | `support_type` 두 값의 **요금 차이**를 Cost Explorer로 확인 |
| LAB 03 | Access Entry로 권한 주기 → `aws-auth`를 보고 **비어 있음**을 확인 |
| LAB 04 | Pod Identity로 S3 읽기 → 같은 걸 IRSA로 다시 → 신뢰 정책 비교 |
| LAB 05 | Karpenter v1 설치 → 파드 100개 띄우고 노드가 어떻게 뜨는지 |
| LAB 06 | v1beta1 YAML을 그대로 apply → **거부되는 것** 확인 |

## ★ 먼저 볼 것 — `support_type`

```hcl
upgrade_policy {
  support_type = "STANDARD"   # 기본값은 EXTENDED
}
```

| | 시간당 | 월(730h) | 연 |
|---|---|---|---|
| STANDARD | $0.10 | 약 $73 | 약 $876 |
| EXTENDED | $0.60 | 약 $438 | 약 $5,256 |

차이가 연 **약 $4,400**, 클러스터 하나당입니다. dev/staging/prod 세 개면
연 $13,000입니다. 그리고 이건 **아무것도 안 해도 기본값으로 붙는 비용**입니다.

STANDARD의 대가: 표준 지원이 끝나면 AWS가 **자동으로 업그레이드**합니다.
업그레이드 주기를 지킬 수 있으면 STANDARD, 못 지킬 환경이면 EXTENDED를
의식적으로 고르세요. 모르고 EXTENDED를 쓰는 게 문제입니다.

(단가는 리전·시점에 따라 바뀝니다 — [EKS 요금](https://aws.amazon.com/eks/pricing/)에서 확인하세요.)

## LAB 03 — aws-auth는 끝났습니다

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name $(terraform output -raw cluster_name)
kubectl get configmap aws-auth -n kube-system
# → Error: not found.  authentication_mode = "API" 이므로 존재하지 않습니다
```

권한은 IAM API로 줍니다.

```bash
aws eks list-access-entries --cluster-name $(terraform output -raw cluster_name)
aws eks list-associated-access-policies \
  --cluster-name $(terraform output -raw cluster_name) \
  --principal-arn <ROLE_ARN>
```

### 왜 바뀌었나

| | aws-auth ConfigMap | Access Entry |
|---|---|---|
| 저장 위치 | 클러스터 안 ConfigMap | EKS 컨트롤 플레인 (IAM API) |
| 잘못 고치면 | **아무도 못 들어옴** (복구는 AWS 지원) | API라 롤백 가능 |
| Terraform | `kubernetes_config_map` — 순환 의존 문제 | 네이티브 리소스 |
| 감사 | ConfigMap 변경 이력 없음 | CloudTrail |

"ConfigMap 들여쓰기 하나로 클러스터를 잠근" 사고가 실제로 흔했습니다.

## LAB 04 — Pod Identity vs IRSA

이 디렉터리의 `aws_iam_role.app_pod` 신뢰 정책:

```hcl
Principal = { Service = "pods.eks.amazonaws.com" }
```

IRSA였다면:

```hcl
Principal = { Federated = "arn:aws:iam::123:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/ABC..." }
Condition = {
  StringEquals = {
    "oidc.eks.ap-northeast-2.amazonaws.com/id/ABC...:sub" = "system:serviceaccount:default:demo-app"
  }
}
```

**클러스터 OIDC URL이 신뢰 정책에 박힙니다.** 클러스터를 새로 만들면
URL이 바뀌고, 그 역할을 쓰던 모든 앱의 신뢰 정책을 고쳐야 합니다.
블루/그린 클러스터 교체를 해 본 사람은 이 고통을 압니다.

| | IRSA | Pod Identity |
|---|---|---|
| 필요한 것 | OIDC 공급자 + 신뢰 정책 조건 | 애드온 + Association |
| 클러스터 교체 시 | 역할 전부 수정 | 그대로 |
| 역할 하나를 여러 클러스터에서 | 신뢰 정책에 OIDC를 여러 개 | 그냥 됨 |
| 세션 태그 | 제한적 | 지원 |
| Fargate | ✓ | ✗ (아직) |
| EKS 외부(ECS 등) | ✗ | ✗ |

새로 만든다면 Pod Identity입니다.

## LAB 06 — Karpenter v1 마이그레이션

`k8s/nodepool.yaml`을 보세요. v1beta1에서 바뀐 것 중 **적용을 실패시키는** 것들:

1. `nodeClassRef`에 `group`·`kind` 필수
2. `consolidationPolicy: WhenUnderutilized` → `WhenEmptyOrUnderutilized`
3. `consolidateAfter` **필수** (v1beta1에선 생략 가능)
4. `EC2NodeClass`에 `amiSelectorTerms` **필수** (`amiFamily`만으로는 거부)
5. `expireAfter`·`terminationGracePeriod`가 `spec.template.spec`로 이동

그리고 v1alpha5의 `Provisioner`/`AWSNodeTemplate`은 아예 없는 리소스입니다.
인터넷에서 찾은 Karpenter YAML의 절반이 지금 안 돕니다 — `apiVersion`을
먼저 보세요.

### 4번이 왜 생겼나

`amiFamily: AL2023`만 쓰면 Karpenter가 "최신 AL2023"을 집어옵니다.
AWS가 새 AMI를 내는 순간, 다음 노드부터 조용히 그 AMI로 뜹니다.
커널 업데이트가 예고 없이 들어오는 구조였고, 실제로 이것 때문에
깨진 사례가 있어서 v1에서 **명시 선택**을 강제했습니다.

```yaml
amiSelectorTerms:
  - alias: al2023@latest          # 명시적으로 "최신을 원한다"
  # - alias: al2023@v20250101     # 또는 버전 고정
```

## terraform-aws-modules/eks v21로 옮길 때

이 디렉터리는 공부용으로 리소스를 직접 씁니다. 운영에서는 공식 모듈이
합리적입니다. v20 → v21에서 바뀐 것:

- `cluster_name` → `name`, `cluster_version` → `kubernetes_version`
- `cluster_endpoint_public_access` → `endpoint_public_access`
- `eks_managed_node_groups`의 하위 키 다수 변경
- `access_entries`가 1급 입력으로

`moved` 블록으로 state를 옮길 수 있지만 리소스 주소가 많이 바뀌어서
`terraform plan`을 꼭 먼저 읽으세요.

## helm provider v3 주의

v2 → v3에서 블록이 **속성**으로 바뀌었습니다.

```hcl
# v2
set {
  name  = "replicas"
  value = 2
}

# v3
set = [{
  name  = "replicas"
  value = "2"
}]
```

Helm 4도 나왔습니다. 차트 호환성을 먼저 확인하세요.

## Floci 주의

| 리소스 | 비고 |
|---|---|
| `aws_iam_role` / policy | 동작 |
| `aws_eks_cluster` | **거의 확실히 미지원** |
| Access Entry / Pod Identity | 미지원 (2023~24 기능) |
| 애드온 | 미지원 |
| Karpenter | 실제 K8s가 필요 |

**정리**: 이 모듈은 Floci로 못 합니다.
두 가지 길이 있습니다.

1. **실제 AWS** — 클러스터 하나를 2~3시간. 컨트롤 플레인 $0.10/h +
   t3.medium 2대. 한 번 세션에 $1 내외입니다. LAB 02를 하려면 이 길뿐입니다.
2. **kind / k3d** — Karpenter를 뺀 K8s 실습(LAB 06의 YAML 검증,
   Access Entry 개념 설명)은 로컬 클러스터로 대체할 수 있습니다.
   `k3d cluster create tfm` 후 `kubectl apply --dry-run=server`로
   v1 스키마 거부를 확인할 수 있습니다.

`make smoke M=08`로 먼저 확인하세요.
