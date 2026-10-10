# terraform-mentoring-lab

Terraform 멘토링 자료와 실습 환경을 한 리포에 담았습니다.
자료 9개 모듈, 면접 문항 121개, 로컬에서 도는 실습 환경, 그리고
각 모듈에 대응하는 Terraform 코드입니다.

```
docs/        자료 (HTML) — 모듈 9개 + 문제은행 + draw.io 다이어그램
lab/         로컬 실습 환경 (Floci + Atlantis + Jenkins)
terraform/   모듈별 실습 코드
upstream/    원본 참조 리포 (git submodule)
```

---

## 빠른 시작

```bash
git clone --recurse-submodules https://github.com/YoungJinJung/terraform-mentoring-lab.git
cd terraform-mentoring-lab

./bootstrap.sh              # 공유 provider/변수를 각 모듈에 심링크
cd lab && make up           # Floci + 웹 콘솔
make smoke                  # ★ 무엇이 되고 무엇이 안 되는지 측정
```

`make smoke`는 `docs/FLOCI-SUPPORT.md`를 **측정값으로** 덮어씁니다.
먼저 돌리세요 — 안 되는 걸 붙들고 한 시간 날리는 걸 막아 줍니다.

자료는 [`docs/index.html`](docs/index.html)을 브라우저로 열면 됩니다.

---

## 자료

| 모듈 | 자료 | 코드 | 시간 |
|---|---|---|---|
| 1 · 기초 | [part1](docs/part1-terraform-basics.html) | [`01-foundation`](terraform/01-foundation) | 4.5h |
| 2 · VPC · Lattice | [part2](docs/part2-vpc-networking.html) | [`02-network`](terraform/02-network) | 4.5h |
| 3 · IAM / SOPS | [part3](docs/part3-iam-secrets.html) | [`03-identity`](terraform/03-identity) | 4.0h |
| 4 · Atlantis + GitHub | [part4](docs/part4-atlantis-github.html) | [`04-gitops`](terraform/04-gitops) | 3.5h |
| 5 · CI/CD | [part5](docs/part5-cicd.html) | [`05-cicd`](terraform/05-cicd) | 3.0h |
| 6 · EC2 | [part6](docs/part6-ec2.html) | [`06-ec2`](terraform/06-ec2) | 2.0h |
| 7 · ECS | [part7](docs/part7-ecs.html) | [`07-ecs`](terraform/07-ecs) | 3.0h |
| 8 · EKS | [part8](docs/part8-eks.html) | [`08-eks`](terraform/08-eks) | 3.5h |
| 9 · Observability | [part9](docs/part9-observability.html) | [`09-observability`](terraform/09-observability) | 2.5h |

합계 30.5시간 (이론 16.5 / 실습 14.0).
[문제은행](docs/question-bank.html)에 121문항이 모듈·난이도별로 들어 있습니다.
[`docs/diagrams/terraform-mentoring-aws.drawio`](docs/diagrams/terraform-mentoring-aws.drawio)는
AWS 공식 아이콘으로 그린 12장짜리 아키텍처 세트입니다 — draw.io에서 열립니다.

---

## 실습 환경

```bash
cd lab

make up        # Floci(:4566) + 웹 콘솔(:4500)
make gitops    # + Gitea(:3000) + Atlantis(:4141)    → 모듈 4
make cicd      # + Jenkins(:8080)                     → 모듈 5
make smoke     # 지원 API 측정 → docs/FLOCI-SUPPORT.md
make down      # 정리
make reset     # 볼륨까지 삭제
```

### ⚠ 보안 주의 — 읽고 넘어가세요

- **Floci 웹 콘솔에는 인증이 없습니다.** 모든 포트를 `127.0.0.1`에만
  바인딩해 두었습니다. `0.0.0.0`으로 바꾸지 마세요.
- **Floci는 `/var/run/docker.sock`을 마운트합니다.** Lambda·RDS 같은 걸
  실제 컨테이너로 띄우기 위해서인데, 그만큼 권한이 셉니다.
  신뢰하는 머신에서만 쓰세요.
- `lab/scripts/env.sh`는 가짜 AWS 자격증명(`test`/`test`)을 export합니다.
  **그 셸에서 실제 AWS를 건드리지 마세요.** 쓰고 나면 셸을 닫는 게 안전합니다.
- 랩용 GitHub/Gitea 토큰은 실습 전용으로 발급하고 끝나면 폐기하세요.

### 전환 — 로컬 ↔ 실제 AWS

모든 모듈이 같은 스위치를 씁니다.

```bash
terraform apply                      # 기본: Floci
terraform apply -var 'use_floci=false'   # 실제 AWS
```

`terraform/_shared/provider.tf`가 `use_floci`에 따라 엔드포인트·검증
건너뛰기를 한 번에 바꿉니다. 모듈 코드에는 로컬/실제 분기가 없습니다.

---

## Floci로 되는 것과 안 되는 것

이 멘토링 자료는 **일부러 최신 기능까지** 다룹니다 (2025-07 ECS 네이티브
Blue/Green, 2026-07 GitHub OIDC immutable claim, Karpenter v1, EKS Access
Entry 등). 그래서 에뮬레이터가 못 따라오는 지점이 분명히 있습니다.

| 모듈 | 로컬 적합도 | 실제 AWS가 필요한 것 |
|---|---|---|
| 4 · Atlantis | ★★★★★ | 없음 — 통째로 로컬 |
| 1 · 기초 | ★★★★☆ | `use_lockfile` (S3 조건부 쓰기) |
| 2 · VPC | ★★★☆☆ | VPC Lattice, NAT 실트래픽 |
| 3 · IAM / SOPS | ★★★☆☆ | **정책이 실제로 막는지** |
| 5 · CI/CD | ★★☆☆☆ | CodeBuild / CodePipeline |
| 7 · ECS | ★★☆☆☆ | 네이티브 Blue/Green 전환 |
| 9 · 관측 | ★★☆☆☆ | 알람 평가, Canary |
| 6 · EC2 | ★★☆☆☆ | Instance Refresh, IMDS |
| 8 · EKS | ★☆☆☆☆ | 거의 전부 |

이 표는 **예상**입니다. `make smoke`로 측정한 `docs/FLOCI-SUPPORT.md`가 사실입니다.

### 그래서 어떻게 운영하나

로컬에서 HCL 작성·`plan` diff 읽기·모듈 구조를 연습하고,
**"실제로 막히는가 / 실제로 전환되는가"는 실제 AWS에서** 확인합니다.
세션당 비용은 대개 커피 한 잔 수준입니다.

| 세션 | 대략 |
|---|---|
| EKS 클러스터 2~3시간 (컨트롤 플레인 + t3.medium 2대) | $1 내외 |
| Fargate 2태스크 + ALB 2시간 | $1 내외 |
| EC2 t3.micro 2대 + ALB 2시간 | $1 미만 |

**매 세션 끝에 `terraform destroy`.** 그리고 AWS Budgets 알림을 먼저 걸어두세요.
`support_type = "EXTENDED"`(EKS 기본값)를 모르고 두면 클러스터 하나에
연 $4,400이 추가됩니다 — 모듈 8 README를 보세요.

---

## 멘티용 사전 준비

- [ ] 격리된 AWS 계정 또는 전용 IAM 사용자
- [ ] AWS Budgets 알림 (금액은 각자 기준으로)
- [ ] Docker Desktop / colima — 랩용
- [ ] `terraform` 1.16+, `aws`, `sops`, `kubectl`, `helm`, `jq`
- [ ] GitHub 계정 (모듈 3·4·5)

```bash
# 설치 확인
for c in terraform aws sops kubectl helm jq docker; do
  printf '%-10s ' "$c"; command -v "$c" >/dev/null && "$c" --version 2>&1 | head -1 || echo "없음"
done
```

---

## 리포 안내

### `./bootstrap.sh`가 하는 일

Terraform은 디렉터리 하나를 한 모듈로 봅니다. `../_shared`를 자동으로
읽지 않습니다. 복사하면 9곳이 따로 늙으므로, 심링크를 깔아 둡니다.

```
terraform/02-network/_shared_provider.tf -> ../_shared/provider.tf
```

`./bootstrap.sh --clean`으로 걷어냅니다.

### `upstream/`

실습 참고용 원본 리포 8개를 submodule로 참조합니다.
복사가 아니라 포인터입니다 — [`upstream/README.md`](upstream/README.md).

### `.gitignore`가 특별히 막는 것

- `*.tfvars` — 계정 ID·CIDR·ARN이 들어갑니다 (`.example`만 커밋)
- `tfplan`, `plan.json` — **평문입니다**
- `.env` — 랩 토큰

---

## 라이선스

코드와 자료는 MIT입니다 ([LICENSE](LICENSE)).
`upstream/` 아래 서브모듈은 각 리포의 라이선스를 따릅니다.
