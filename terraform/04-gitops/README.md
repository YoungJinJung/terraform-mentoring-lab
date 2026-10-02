# 모듈 4 · PR 기반 인프라 운영 (Atlantis + GitHub)

> 자료: [`docs/part4-atlantis-github.html`](../../docs/part4-atlantis-github.html)

이 모듈은 AWS 리소스를 만드는 모듈이 아닙니다. **운영 방식**을 만드는 모듈입니다.
그래서 디렉터리 내용도 `.tf`가 아니라 설정과 정책입니다.

| 파일 | 역할 |
|---|---|
| `atlantis.yaml` | 리포 측 설정 — 어떤 디렉터리를 언제 계획할지 |
| `../../lab/atlantis/repos.yaml` | 서버 측 설정 — 리포가 **무엇을 덮어쓸 수 있는지** |
| `policies/terraform.rego` | plan JSON을 검사하는 conftest 정책 6종 |

## 이 디렉터리에서 하는 것

| 실습 | 내용 |
|---|---|
| LAB 01 | Gitea + Atlantis 띄우고 PR 하나로 plan → apply 끝까지 |
| LAB 02 | `apply_requirements`를 하나씩 빼면서 뭐가 통과되는지 확인 |
| LAB 03 | conftest 정책을 **일부러 위반**하는 PR을 올려서 막히는지 확인 |
| LAB 04 | `atlantis-data` 볼륨을 지우고 apply → 왜 실패하는지 |

## 해보기

```bash
cd ../../lab && make gitops
open http://localhost:4141/healthz
```

Gitea 설정은 [`.github/workflows-example/atlantis-webhook-note.md`](.github/workflows-example/atlantis-webhook-note.md) 참고.

## LAB 04가 중요한 이유

Atlantis는 plan 결과를 **디스크에 파일로** 저장했다가 apply 때 그 파일을 씁니다.
컨테이너를 재시작하거나 레플리카를 2로 올리면 `atlantis apply`가
"plan file not found"로 실패합니다.

```bash
cd ../../lab
docker compose --profile gitops down
docker volume rm lab_atlantis-data
make gitops
# 아까 PR에서 atlantis apply → 실패
```

그래서 Kubernetes에 올릴 때는 **StatefulSet + PVC, replicas: 1**입니다.
Deployment + replicas: 2는 조용히 깨지는 구성입니다.

## 서버 측 vs 리포 측

| | 서버 측 (`repos.yaml`) | 리포 측 (`atlantis.yaml`) |
|---|---|---|
| 누가 수정 | 플랫폼 팀 | 리포 소유자 (PR로) |
| 신뢰 | 신뢰됨 | **신뢰 안 됨** |
| 핵심 키 | `allowed_overrides`, `allow_custom_workflows` | `projects`, `workflow` |

`allow_custom_workflows: true`를 서버 측에서 켜면, 리포에 PR을 올릴 수 있는
사람이 **Atlantis 컨테이너 안에서 임의 명령을 실행**할 수 있습니다.
그 컨테이너는 apply 자격증명을 들고 있습니다. 끄고 쓰세요.

## 실제 GitHub으로 옮길 때

Atlantis 서버가 쓸 자격증명은 모듈 3의 OIDC가 아니라 **장기 역할**입니다
(웹훅은 GitHub Actions 런타임이 아니니 OIDC 토큰이 없습니다).
그래서 보통 이렇게 갑니다.

- Atlantis를 EKS/ECS에 올리고 IRSA 또는 Task Role로 권한 부여
- 그 역할에 모듈 3의 **권한 경계**를 그대로 붙이기
- GitHub App으로 연결 (PAT보다 권한을 좁게 줄 수 있습니다)

## Floci 주의

Atlantis 자체는 Floci와 무관하게 동작합니다. 안에서 돌아가는 terraform이
Floci를 바라볼 뿐입니다. 즉 **이 모듈은 Floci에서 거의 그대로 됩니다** —
랩 가치가 가장 높은 모듈입니다.
