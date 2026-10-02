# 모듈 7 · ECS on Fargate

> 자료: [`docs/part7-ecs.html`](../../docs/part7-ecs.html)

## 이 디렉터리에서 하는 것

| 실습 | 내용 |
|---|---|
| LAB 01 | 클러스터 + 서비스 + ALB 한 벌, 롤링 배포로 `app_version` 올려보기 |
| LAB 02 | `deployment_strategy`를 `BLUE_GREEN`으로 바꿔 전환 과정 관찰 |
| LAB 03 | 일부러 깨진 이미지로 배포 → 롤링은 circuit breaker, B/G는 bake time |
| LAB 04 | `CANARY`로 10% → 검증 → 100%, lifecycle hook 자리 확인 |
| LAB 05 | execution_role과 task_role을 **바꿔 끼워보고** 뭐가 깨지는지 |

## 해보기

```bash
eval "$(cat ../../lab/scripts/env.sh)"
terraform init && terraform apply

terraform output prod_url
```

## LAB 02 — 네이티브 Blue/Green

```bash
terraform apply -var 'deployment_strategy=BLUE_GREEN' -var 'bake_time_minutes=5'
# 그다음 새 버전 배포
terraform apply -var 'deployment_strategy=BLUE_GREEN' -var 'app_version=v2'
```

관찰할 것:

```bash
aws ecs describe-services --cluster "$(terraform output -raw cluster_name)" \
  --services "$(terraform output -raw service_name)" \
  --query 'services[0].deployments[].[status,rolloutState,desiredCount,runningCount]'

# 운영 포트와 테스트 포트를 번갈아 찔러보세요
watch -n1 'curl -s $(terraform output -raw prod_url) | head -1; \
           curl -s $(terraform output -raw test_url) | head -1'
```

새 버전이 **테스트 리스너(:8080)에만 먼저** 올라오고,
운영 리스너(:80)는 아직 옛 버전입니다. bake time 동안 이 상태가 유지되고,
그 사이 알람이 울리면 전환 없이 끝납니다.

### 2025-07 전과 후

| | 이전 (CodeDeploy) | 현재 (네이티브) |
|---|---|---|
| 리소스 수 | `aws_codedeploy_app`, `_deployment_group`, `_deployment_config` + appspec.yaml | `deployment_configuration` 블록 하나 |
| `deployment_controller.type` | `CODE_DEPLOY` | `ECS` |
| 태스크 정의 갱신 | CodeDeploy가 appspec으로 | ECS가 직접 |
| 전환 비율 제어 | CodeDeploy 배포 설정 | `strategy` + `bake_time_in_minutes` |
| Terraform 지원 | 오래됨 | aws provider **v6.4.0+** |

오래된 자료를 보고 CodeDeploy 쪽으로 가면 리소스 3개와 YAML 하나를
더 들고 다녀야 합니다. 새로 만든다면 네이티브 쪽입니다.

## LAB 03 — circuit breaker는 롤링 전용

```bash
# 롤링 + 깨진 이미지
terraform apply -var 'deployment_strategy=ROLLING' \
                -var 'image=public.ecr.aws/docker/library/nginx:does-not-exist'
```

circuit breaker가 몇 분 뒤 자동 롤백합니다.

같은 걸 `BLUE_GREEN`으로 하면 **circuit breaker가 없습니다.**
대신 새 태스크가 헬시가 안 되므로 전환 자체가 일어나지 않고,
운영 트래픽은 계속 옛 버전으로 갑니다. 결과적으로 안전하지만
"롤백했다"는 로그가 안 남습니다 — 알람을 따로 붙여야 합니다.

## LAB 05 — 역할 두 개의 차이

| | execution_role | task_role |
|---|---|---|
| 쓰는 주체 | ECS 에이전트 (컨테이너 **밖**) | 앱 코드 (컨테이너 **안**) |
| 전형적 권한 | ECR pull, CloudWatch Logs, Secrets 주입 | S3, DynamoDB, SQS |
| 없으면 | 태스크가 **시작조차 못 함** | 앱이 AWS 호출 시 AccessDenied |

`execution_role_arn`을 지우고 apply해 보세요. 태스크가
`CannotPullContainerError`로 멈춥니다. 반대로 `task_role_arn`만 지우면
태스크는 뜨지만 앱의 AWS 호출이 실패합니다.

면접에서 "이 둘의 차이"는 거의 항상 나옵니다.

## 비용 메모

| 선택 | 영향 |
|---|---|
| `cpu_architecture = "ARM64"` | x86 대비 약 20% 저렴. 이미지를 arm64로 빌드해야 합니다 |
| `spot_weight > 0` | Fargate Spot은 크게 저렴하지만 2분 경고 후 회수 |
| `container_insights = true` (enhanced) | 태스크 단위 지표. 태스크가 많으면 비용이 눈에 보입니다 |
| `log_retention_days` | 기본 "never expire"를 그냥 두면 로그가 제일 비싼 항목이 됩니다 |

## Floci 주의

| 리소스 | 비고 |
|---|---|
| `aws_ecs_cluster` / `task_definition` | 보통 등록은 됩니다 |
| `aws_ecs_service` | 상태는 만들어지지만 **실제 태스크 동작은 제한적** |
| 네이티브 Blue/Green (2025-07) | **거의 확실히 미지원** — 가장 최신 기능이라 에뮬레이터가 못 따라옵니다 |
| ALB 전환 | 미지원 |
| ECS Exec | 미지원 |

**정리**: LAB 01의 HCL 작성·plan 확인까지는 Floci로, LAB 02~04는
**실제 AWS에서 Fargate 2태스크**로 하세요. Fargate 0.25vCPU 2개를
한두 시간 띄우는 비용이면 충분합니다.
`make smoke M=07`로 먼저 확인하세요.
