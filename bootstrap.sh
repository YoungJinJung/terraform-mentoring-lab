#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# terraform/_shared/*.tf 를 각 모듈 디렉터리에 복사해 둡니다.
#
# 왜 필요한가: Terraform은 디렉터리 하나를 한 모듈로 봅니다.
# ../_shared 를 자동으로 읽지 않습니다.
#
# 복사본은 .gitignore 되어 있고 파일 머리에 "자동 생성" 표시가 붙습니다.
# 고쳐야 할 건 항상 terraform/_shared/ 쪽입니다.
#
#   ./bootstrap.sh          # 깔기 (이미 있으면 갱신)
#   ./bootstrap.sh --clean  # 걷어내기
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED="$ROOT/terraform/_shared"
SHARED_FILES=(versions.tf provider.tf variables.tf)

clean=false
[[ "${1:-}" == "--clean" ]] && clean=true

shopt -s nullglob
for dir in "$ROOT"/terraform/[0-9][0-9]-*/; do
  name="$(basename "$dir")"

  # 모듈 4는 .tf 가 없는 설정 전용 디렉터리입니다
  if [[ "$name" == 04-* && "$clean" == false ]]; then
    continue
  fi

  for f in "${SHARED_FILES[@]}"; do
    dest="${dir}_shared_${f}"

    if $clean; then
      if [[ -e "$dest" ]]; then
        rm -f "$dest"
        echo "  - ${name}/_shared_${f}"
      fi
      continue
    fi

    # Provider를 추가 선언한 모듈은 자체 versions.tf가 shared 파일을 대체합니다.
    if [[ "$f" == "versions.tf" && -f "${dir}versions.tf" ]]; then
      rm -f "$dest"
      continue
    fi

    {
      echo "# ┌──────────────────────────────────────────────────────────┐"
      echo "# │ 자동 생성 — 고치지 마세요.                               │"
      echo "# │ 원본: terraform/_shared/${f}"
      echo "# │ 갱신: ./bootstrap.sh"
      echo "# └──────────────────────────────────────────────────────────┘"
      echo
      cat "$SHARED/$f"
    } > "$dest"
    echo "  + ${name}/_shared_${f}"
  done
done

if $clean; then
  echo "걷어냈습니다."
  exit 0
fi

cat <<'MSG'

준비됐습니다. 다음 순서로 가세요.

  1) 랩 띄우기
       cd lab && make up

  2) Floci가 뭘 지원하는지 먼저 확인
       make smoke            # docs/FLOCI-SUPPORT.md 를 만듭니다

  3) 모듈 1부터
       cd ../terraform/01-foundation
       eval "$(cat ../../lab/scripts/env.sh)"
       terraform init && terraform apply

자료는 docs/index.html 부터 보세요.
MSG
