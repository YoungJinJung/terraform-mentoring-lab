# 모듈 6 · EC2 / ALB / Auto Scaling

> 자료: [`docs/part6-ec2.html`](../../docs/part6-ec2.html)

## 이 디렉터리에서 하는 것

| 실습 | 내용 |
|---|---|
| LAB 01 | LT + ASG + ALB 한 벌 세우고 `curl`로 인스턴스가 번갈아 나오는지 확인 |
| LAB 02 | IMDSv2를 **끄고** SSRF 흉내를 내서 자격증명이 어떻게 새는지 |
| LAB 03 | `app_message`를 바꿔 apply → **인스턴스가 왜 안 바뀌는지** → Instance Refresh |
| LAB 04 | TG를 일부러 unhealthy로 만들고 `health_check_type` 차이 확인 |
| LAB 05 | `auto_rollback = false`로 바꾸고 깨진 AMI로 refresh → 멈춘 상태 관찰 |

## 해보기

```bash
eval "$(cat ../../lab/scripts/env.sh)"
cp terraform.tfvars.example terraform.tfvars   # 모듈 2 출력으로 채우기
terraform init && terraform apply

terraform output curl_me
```

## LAB 02 — IMDSv2가 막는 것

`main.tf`의 `http_tokens`를 `"optional"`로 바꿔 apply한 뒤, SSM으로 들어가서:

```bash
# IMDSv1 — GET 한 번으로 끝납니다
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

역할 이름이 나오고, 한 번 더 GET하면 **임시 자격증명 전체**가 나옵니다.
앱에 `?url=` 파라미터로 아무 주소나 긁어오는 코드가 하나 있으면
공격자는 이 두 번의 GET만으로 AWS 자격증명을 가져갑니다. 2019년 Capital One
사건의 구조가 정확히 이것입니다.

`"required"`로 되돌리면:

```bash
curl -s http://169.254.169.254/latest/meta-data/   # → 401
TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/
```

`PUT`을 해야 합니다. 대부분의 SSRF는 GET만 보낼 수 있으므로 여기서 멈춥니다.
`hop_limit = 1`은 추가로 "컨테이너 안에서 호스트 IMDS 찍기"를 막습니다.

## LAB 03 — 이 모듈의 핵심

```bash
terraform apply -var 'app_message=hello from v2'
```

plan은 **Launch Template 새 버전**을 만든다고 나옵니다.
그런데 `curl`을 해보면 여전히 v1입니다.

이유: ASG는 "다음에 뜨는 인스턴스"에 LT를 적용합니다. 이미 떠 있는 건
건드리지 않습니다. `instance_refresh` 블록이 그 역할을 합니다.

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$(terraform output -raw asg_name)" \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete]'
```

`instance_refresh` 블록을 지우고 같은 실습을 해보면 영원히 v1입니다.
그리고 반년 뒤 누군가 스케일 아웃을 하면 **v1과 v2가 섞여 돕니다.**
이게 "분명히 배포했는데 간헐적으로 옛 동작이 나온다"의 정체입니다.

## 왜 키 페어가 없는가

`key_name`이 어디에도 없습니다. SSM Session Manager로 들어갑니다.

```bash
aws ssm start-session --target i-xxxxxxxx
```

22번 포트를 안 열고, 베스티온이 없고, 키 파일을 관리하지 않고,
접속 로그가 CloudTrail에 남습니다. 새로 만드는 환경에서 SSH 키를
설계에 넣을 이유가 거의 없습니다.

## Floci 주의

| 리소스 | 비고 |
|---|---|
| `aws_security_group*` | 대체로 동작 |
| `aws_iam_role` / instance profile | 동작 |
| `aws_launch_template` | 보통 동작 |
| `aws_ami` 데이터 소스 | **빈 결과일 수 있음** → `ami_id` 변수로 더미 지정 |
| `aws_lb` / target group / listener | 지원 범위가 들쭉날쭉 |
| `aws_autoscaling_group` | **실제 인스턴스는 안 뜹니다** — HTTP 응답 실습 불가 |
| Instance Refresh | 미지원 |
| SSM Session Manager | 미지원 |

**정리**: 이 모듈은 Floci 적합도가 낮은 편입니다. HCL 구조·plan diff 연습은
로컬에서, LAB 02/03/05는 **실제 AWS에서 t3.micro 2대로** 하는 게 맞습니다
(몇 시간이면 커피값 수준입니다). `make smoke M=06`으로 먼저 확인하세요.
