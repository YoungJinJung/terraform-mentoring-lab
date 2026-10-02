# 모듈 1 · 기초

> 자료: [`docs/part1-terraform-basics.html`](../../docs/part1-terraform-basics.html)

## 이 디렉터리에서 하는 것

| 실습 | 내용 |
|---|---|
| LAB 01 | 변수·local·output, `for_each` vs `count` 차이를 **plan으로 직접 확인** |
| LAB 02 | S3 backend 구성과 `init -migrate-state` |
| LAB 03 | 모듈 뼈대 만들기 (이후 모듈이 재사용) |

## 해보기

```bash
eval "$(cat ../../lab/scripts/env.sh)"
terraform init
terraform apply

# ★ 핵심 실험 — 가운데 항목을 지우고 plan을 비교하세요
terraform plan -var 'demo_buckets=["alpha","charlie"]'
```

`for_each` 쪽은 `bravo` 하나만 사라지고, `count` 쪽은 **`charlie`까지 재생성**됩니다.
이게 "기본은 `for_each`"인 이유입니다.

## Floci 주의

`use_lockfile`은 S3 조건부 쓰기(`If-None-Match`)를 요구합니다.
`make smoke M=01`로 지원 여부를 먼저 확인하세요. 안 되면 backend 실습만
실제 AWS에서 하거나, 로컬 state로 진행합니다.
