# eval "$(cat lab/scripts/env.sh)"
#
# 주의 — 이 변수들이 떠 있는 쉘에서 실제 AWS 작업을 하지 마세요.
# 엉뚱한 곳에 쏘거나, 반대로 실제 계정에 가짜 자격증명으로 붙으려 합니다.
# 실제 AWS를 쓸 때는 새 터미널을 열거나 `unset` 하세요.
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=ap-northeast-2
export AWS_PAGER=""
export TF_VAR_use_floci=true
