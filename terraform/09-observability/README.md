# 모듈 9 · 관측 (Observability)

> 자료: [`docs/part9-observability.html`](../../docs/part9-observability.html)

이 모듈의 주제는 **무엇을 보지 않을 것인가**입니다.
관측 비용은 거의 항상 "다 켜두었기 때문에" 생깁니다.

## 이 디렉터리에서 하는 것

| 실습 | 내용 |
|---|---|
| LAB 01 | 로그 그룹 + 메트릭 필터 + 알람 + 대시보드 한 벌 |
| LAB 02 | `treat_missing_data` 네 값을 바꿔가며 알람 상태 관찰 |
| LAB 03 | 같은 집계를 Logs Insights vs 메트릭 필터로 — **비용 비교** |
| LAB 04 | 복합 알람으로 배포 중 오탐 없애기 |
| LAB 05 | Canary로 "안에서는 정상인데 밖에서는 장애" 재현 |

## 해보기

```bash
eval "$(cat ../../lab/scripts/env.sh)"
terraform init && terraform apply

terraform output dashboard_url
```

## LAB 02 — `treat_missing_data`

| 값 | 데이터 없을 때 | 쓸 곳 |
|---|---|---|
| `missing` (기본) | 직전 상태 유지 | 애매할 때 — 그래서 기본값이 제일 안 좋습니다 |
| `notBreaching` | OK로 간주 | **에러 카운트** — 에러가 없으면 데이터도 없음 |
| `breaching` | ALARM으로 간주 | **하트비트** — 데이터가 없는 게 곧 장애 |
| `ignore` | 상태 변경 안 함 | 간헐적으로 보고하는 지표 |

이 디렉터리에 둘 다 있습니다.

- `error_rate` → `notBreaching` (에러 0이 정상)
- `heartbeat` → `breaching` (요청 0은 비정상)

같은 "데이터 없음"이 하나는 정상, 하나는 장애입니다.
이걸 구분하지 않으면 **조용한 장애**가 생깁니다.

### default_value도 같이 보세요

메트릭 필터에 `default_value = 0`을 줬습니다. 안 주면 에러가 없는
기간에 데이터 포인트가 **아예 없고**, 알람은 INSUFFICIENT_DATA에
머뭅니다. 그러면 "정상"과 "로그 수집 중단"이 같은 모습이 됩니다.

## LAB 03 — 비용 실험

"지난 1시간 에러 수"를 두 방법으로 구합니다.

```bash
# 방법 A — Logs Insights
aws logs start-query \
  --log-group-name /app/api \
  --start-time $(( $(date +%s) - 3600 )) \
  --end-time   $(date +%s) \
  --query-string 'fields @timestamp | filter @message like /ERROR/ | stats count()'
# 결과의 bytesScanned 를 보세요 — 이게 과금 기준입니다
```

```bash
# 방법 B — 메트릭 필터로 만든 지표
aws cloudwatch get-metric-statistics \
  --namespace "tfm-dev/App" --metric-name ErrorCount \
  --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time   "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 300 --statistics Sum
# 스캔 없음. 커스텀 지표 하나만 과금됩니다
```

대시보드가 5분마다 자동 갱신되면 방법 A는 **하루 288번 로그를 다시
스캔**합니다. 로그가 하루 50GB면 스캔 비용이 저장 비용을 넘습니다.

### 정리

| | 메트릭 필터 | Logs Insights |
|---|---|---|
| 언제 계산 | 로그가 들어올 때 한 번 | 쿼리할 때마다 |
| 과금 | 커스텀 지표 수 | 스캔한 GB |
| 과거 데이터 | **안 됩니다** (필터 생성 이후만) | 보존 기간 전체 |
| 임의 질문 | 못 함 | 가능 |

**알고 있는 질문 → 메트릭 필터. 조사 → Insights.**
대시보드에 Insights 위젯을 깔아두는 게 가장 흔한 비용 사고입니다.

## 로그 비용 구조

```
총비용 = 수집(GB) + 저장(GB·월) + 스캔(GB)
```

줄이는 순서:

1. **안 찍기** — DEBUG 로그를 운영에서 끄기. 가장 효과가 큽니다
2. **보존 기간** — 30일로 충분한 걸 영구로 두지 않기
3. **저장 클래스** — 규정용 로그는 `INFREQUENT_ACCESS`
4. **스캔 줄이기** — 반복 질문은 메트릭 필터로
5. **샘플링** — 액세스 로그는 일부만

이 디렉터리의 `log_groups` 기본값이 1~3번을 보여줍니다.
`/app/audit`은 365일 + IA, `/app/web`은 14일 + 표준입니다.

## LAB 04 — 알람 피로

배포할 때마다 5xx가 몇 개 뜨고 알람이 울리면, 두 달 뒤 팀은
그 알람을 음소거합니다. 그리고 진짜 장애를 놓칩니다.

이 디렉터리의 `page` 복합 알람은 "5xx 증가 AND p99 상승"일 때만 울립니다.
배포 중 짧은 5xx는 지연 상승을 동반하지 않으므로 걸러집니다.

더 나아가 `actions_suppressor`를 쓰면 "배포 진행 중" 알람이 ALARM인 동안
모든 알림을 억제할 수 있습니다 (코드에 주석으로 남겨 두었습니다).

### 알람을 세 등급으로

| 등급 | 조건 | 행동 |
|---|---|---|
| PAGE | 사용자가 지금 영향받음 | 새벽에도 전화 |
| TICKET | 곧 문제가 됨 (디스크 80%) | 근무 시간에 처리 |
| INFO | 알면 좋음 | 대시보드만 |

대부분의 조직이 모든 알람을 PAGE로 만들어 놓고 전부 무시합니다.

## Datadog / 서드파티

`datadog.tf.example`을 보세요. provider v4에서 AWS 연동 리소스 4개가
`datadog_integration_aws_account` 하나로 합쳐졌습니다. v3 코드를 올리면
"리소스 타입 없음"이 납니다.

비용 통제 포인트는 `namespace_filters`와 `tag_filters`입니다.
안 걸면 계정 전체 지표를 수집하고, Datadog 청구서는 호스트 수가 아니라
**커스텀 지표 수**에서 터집니다.

## Floci 주의

| 리소스 | 비고 |
|---|---|
| `aws_cloudwatch_log_group` | 보통 동작 |
| `aws_cloudwatch_log_metric_filter` | 생성은 되지만 **실제 집계는 안 됩니다** |
| `aws_cloudwatch_metric_alarm` | 생성은 되지만 평가 안 됨 |
| `aws_cloudwatch_dashboard` | 생성만 |
| `aws_sns_topic` | 보통 동작 |
| Synthetics Canary | 미지원 → `enable_canary = false` |

**정리**: HCL 구조 연습은 Floci로 되지만, 이 모듈의 핵심인
"알람이 실제로 어떻게 동작하는가"는 Floci로 확인할 수 없습니다.
LAB 02~04는 실제 AWS에서 하세요 — 로그 그룹 몇 개와 알람 몇 개는
프리 티어 범위이거나 몇 센트입니다.

`make smoke M=09`로 먼저 확인하세요.
