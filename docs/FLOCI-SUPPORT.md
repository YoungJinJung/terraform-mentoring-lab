# Floci 지원 현황

> ⚠ **이 파일은 아직 측정되지 않은 자리표시자입니다.**
>
> ```bash
> cd lab && make up && make smoke
> ```
>
> 를 돌리면 `lab/scripts/smoke-test.sh`가 Floci의 실제 API를 찔러보고
> 이 파일을 **측정값으로 덮어씁니다.**

## 왜 측정하는가

Floci는 활발히 개발 중인 프로젝트입니다. 어떤 API가 되고 안 되는지는
버전마다 바뀝니다. 그래서 자료에 "이건 안 됩니다"라고 적어두면
금방 틀린 말이 됩니다.

대신 **멘티가 직접 측정하게** 만들었습니다. 각 모듈 README의
"Floci 주의" 표는 제 예상이고, 이 파일은 **그 환경의 사실**입니다.
둘이 다르면 이 파일이 맞습니다.

## 예상 (측정 전)

| 모듈 | 예상 적합도 | 이유 |
|---|---|---|
| 1 · 기초 | 높음 | S3·IAM 기본. `use_lockfile`은 조건부 쓰기 지원 여부에 달림 |
| 2 · VPC | 중간 | VPC/서브넷/라우팅은 되는 편. **VPC Lattice는 거의 확실히 미지원** |
| 3 · IAM/SOPS | 중간 | 리소스는 만들어지지만 **정책 평가를 안 합니다** |
| 4 · Atlantis | **가장 높음** | Atlantis는 Floci와 무관하게 동작 |
| 5 · CI/CD | 낮음 | CodeBuild/CodePipeline 미지원. Jenkins 로컬은 됨 |
| 6 · EC2 | 낮음 | 리소스는 생기지만 실제 인스턴스가 안 뜸 |
| 7 · ECS | 낮음 | 네이티브 Blue/Green(2025-07)은 미지원 |
| 8 · EKS | 매우 낮음 | 실제 클러스터가 필요 |
| 9 · 관측 | 낮음 | 알람이 **평가되지 않음** |

## 읽는 법

측정 후 이 파일은 이런 모양이 됩니다.

```
### 모듈 2 · VPC
✅ ec2 create-vpc
✅ ec2 create-subnet
✅ ec2 describe-route-tables
❌ vpc-lattice list-service-networks   (501 Not Implemented)
⏭️  ec2 create-nat-gateway              (건너뜀 — 선행 리소스 없음)
```

`❌`가 붙은 항목은 **실제 AWS에서 해야 하는 실습**입니다.
각 모듈 README의 맨 아래에 "실제 AWS가 필요한 LAB"이 적혀 있습니다.
