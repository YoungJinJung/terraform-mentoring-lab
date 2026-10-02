# 모듈 3 · IAM & 비밀 관리

> 자료: [`docs/part3-iam-secrets.html`](../../docs/part3-iam-secrets.html)

## 이 디렉터리에서 하는 것

| 실습 | 내용 |
|---|---|
| LAB 01 | OIDC 신뢰 정책을 직접 쓰고, **일부러 틀리게** 해서 왜 막히는지 본다 |
| LAB 02 | plan 역할 / apply 역할 분리 + 권한 경계 |
| LAB 03 | SOPS 암호화 → `ephemeral`로 읽기 → state에 안 남는 것을 확인 |

## 먼저 볼 것 — immutable subject claim

```
예전:  repo:YoungJinJung/terraform-mentoring-lab:ref:refs/heads/main
새것:  repo:YoungJinJung@12345/terraform-mentoring-lab@67890:ref:refs/heads/main
```

조직·리포 이름은 바꿀 수 있고, 삭제한 이름은 **남이 다시 가져갈 수 있습니다.**
숫자 ID는 못 바꿉니다. 그래서 AWS·GitHub이 권하는 쪽은 새 형식입니다.

ID 확인:

```bash
curl -s https://api.github.com/users/YoungJinJung | jq .id
curl -s https://api.github.com/repos/YoungJinJung/terraform-mentoring-lab | jq .id
```

`terraform.tfvars`에 넣습니다.

```hcl
github_org_id  = "12345"
github_repo_id = "67890"
```

## 해보기

```bash
eval "$(cat ../../lab/scripts/env.sh)"
terraform init && terraform apply

# 신뢰 정책이 실제로 뭘 허용하는지
terraform output oidc_subjects_allowed
```

### 일부러 틀려보기

`main.tf`의 sub 조건을 `repo:${var.github_org}/*`로 바꿔보세요.
plan은 통과합니다. **문법이 아니라 설계가 틀린 것**이고, Terraform은
그걸 못 잡아줍니다 — 이게 모듈 4에서 conftest 정책 검사를 붙이는 이유입니다.

`aud` 조건을 아예 지워보고, 왜 그게 더 위험한지 설명해 보세요.

## state 유출 확인 — 이 실습의 핵심

```bash
# ephemeral을 쓴 경우
terraform show -json | jq '.. | strings | select(test("ENC\\[|supersecret"))'
# → 아무것도 안 나와야 정상

# 비교용: data "sops_file"로 바꿔서 apply한 뒤 같은 명령을 돌려보세요.
# 평문이 그대로 나옵니다.
```

## Floci 주의

| 리소스 | 비고 |
|---|---|
| `aws_iam_role` / `policy` | 대체로 동작 — 단, **정책 평가는 하지 않습니다**. 잘못된 정책도 통과합니다 |
| `aws_iam_openid_connect_provider` | `create_oidc_provider = false`로 두는 게 안전 |
| `sts:AssumeRoleWithWebIdentity` | 실제 토큰 검증 없음 → OIDC 실습은 **실제 AWS 필요** |
| Secrets Manager | 보통 동작 |

`make smoke M=03`으로 먼저 확인하세요.

**정리**: 이 모듈은 "HCL을 쓰는 연습"은 Floci로, "정책이 실제로 막는지"는
실제 AWS에서 해야 합니다. 그 둘을 구분하는 게 이 모듈의 교육 목표이기도 합니다.
