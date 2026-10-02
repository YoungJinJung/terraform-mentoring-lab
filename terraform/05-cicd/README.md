# 모듈 5 · CI/CD

> 자료: [`docs/part5-cicd.html`](../../docs/part5-cicd.html)

**같은 파이프라인을 세 가지로 구현해 둔 디렉터리입니다.** 나란히 읽는 게 핵심입니다.

| 구현 | 파일 | 승인 | 자격증명 | plan 전달 |
|---|---|---|---|---|
| CodePipeline V2 | `main.tf` + `buildspec-*.yml` | Manual Approval 스테이지 | 서비스 역할 | S3 아티팩트 |
| GitHub Actions | `workflows/terraform.yml` | Environment reviewers | **OIDC (장기 키 없음)** | upload/download-artifact |
| Jenkins | `Jenkinsfile` | `input` 스텝 | 인스턴스 역할 / IRSA | stash/unstash |

## 이 디렉터리에서 하는 것

| 실습 | 내용 |
|---|---|
| LAB 01 | Jenkins(`make cicd`)로 plan → 승인 → apply 한 바퀴 |
| LAB 02 | `apply` 단계를 "저장된 plan" 대신 `-auto-approve`로 바꿔보고 왜 위험한지 |
| LAB 03 | CodeBuild Lambda compute vs General1 — 빌드 시간·비용 비교 |
| LAB 04 | Actions 워크플로를 실제 리포에 붙이고 OIDC로 plan 돌리기 |

## LAB 02 — 이 모듈에서 가장 중요한 실습

`buildspec-apply.yml`은 `terraform apply tfplan`을 씁니다.
`terraform apply -auto-approve`로 바꿔보세요.

차이:

| | `apply tfplan` | `apply -auto-approve` |
|---|---|---|
| 승인한 내용 == 적용한 내용 | **보장됨** | 보장 안 됨 |
| plan 이후 state가 바뀌었으면 | 거부 | 그냥 적용 |
| 누가 콘솔에서 뭘 지웠으면 | 멈춤 | 조용히 다시 만들거나 더 지움 |

승인 버튼을 누르는 사람이 본 화면과 실제 실행이 달라지는 구조를
"승인이 있다"고 부르면 안 됩니다.

## 비용 얘기 — plan 한 번에 얼마인가

하루 20번, plan 평균 90초 가정.

| 구성 | 대략 |
|---|---|
| CodeBuild `BUILD_GENERAL1_SMALL` | 분 단위 과금 → 90초도 2분으로 올림 |
| CodeBuild `BUILD_LAMBDA_1GB` | 초 단위 과금, 콜드스타트 거의 없음 |
| GitHub Actions (public repo) | 무료 |
| GitHub Actions (private) | 포함 분 소진 후 분당 과금 |
| Jenkins on EC2 | 인스턴스를 24시간 띄워두는 값 |

정확한 단가는 바뀌니 [CodeBuild 요금](https://aws.amazon.com/codebuild/pricing/)을
직접 보세요. 요점은 **분 단위 올림 과금이라 짧은 작업이 비싸게 먹힌다**는 구조입니다.

## CodePipeline V1 vs V2

| | V1 | V2 |
|---|---|---|
| 과금 | 활성 파이프라인당 월 고정 | 액션 실행 시간 |
| 브랜치/경로 필터 | ✗ (별도 Lambda 필요) | ✓ `trigger` 블록 |
| 파이프라인 변수 | ✗ | ✓ |
| 스테이지 롤백 | ✗ | ✓ |

하루 몇 번 도는 인프라 파이프라인 → V2가 보통 저렴.
하루 수백 번 도는 앱 파이프라인 → V1이 저렴할 수 있음.

## `execution_mode`를 왜 QUEUED로 두는가

기본값 `SUPERSEDED`는 새 실행이 진행 중인 실행을 **덮어씁니다**.
앱 배포에는 합리적이지만 terraform에서는 apply가 중간에 끊기고
state lock이 남습니다. `QUEUED`는 줄을 세웁니다.

## Floci 주의

| 리소스 | 비고 |
|---|---|
| S3 아티팩트 버킷 | 동작 |
| IAM 역할 | 동작 (평가는 안 함) |
| CodeBuild / CodePipeline | **대체로 미지원** → `create_connection = false` 기본값 |
| CodeStar Connection | 미지원 (실제로도 콘솔 수동 단계가 필요) |

그래서 이 모듈의 실습 주력은 **Jenkins(로컬 컨테이너) + GitHub Actions(실제)**이고,
CodePipeline 쪽은 **코드를 읽고 비교하는 용도**입니다.
`make smoke M=05`로 지원 범위를 먼저 확인하세요.
