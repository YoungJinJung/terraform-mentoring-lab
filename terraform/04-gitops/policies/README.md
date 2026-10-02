# 정책 검사

## 혼자 돌려보기

```bash
cd ../../02-network
terraform plan -out tfplan
terraform show -json tfplan > /tmp/plan.json
conftest test --policy ../04-gitops/policies /tmp/plan.json
```

## 일부러 깨뜨려보기

`02-network/main.tf`에 아래를 넣고 다시 돌려보세요.

```hcl
resource "aws_vpc_security_group_ingress_rule" "oops" {
  security_group_id = aws_security_group.whatever.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}
```

`deny`가 하나 떠야 합니다.

## Atlantis에 붙이기

서버 측 설정(`lab/atlantis/repos.yaml`)에서 `policy_check: true`를 켜고
`policies` 섹션에 소유자를 지정합니다. `deny`가 있으면 apply가 막히고,
지정된 소유자만 `atlantis approve_policies`로 통과시킬 수 있습니다.

`warn`은 막지 않습니다 — 코멘트에만 남습니다. "막을 것"과
"보게 할 것"을 구분하는 게 정책 설계의 절반입니다.
