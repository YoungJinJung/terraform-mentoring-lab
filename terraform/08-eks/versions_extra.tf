# 모듈 8만 tls 공급자를 추가로 씁니다 (IRSA용 OIDC thumbprint).
#
# _shared/versions.tf 는 bootstrap.sh 가 심링크로 가져옵니다.
# required_providers 는 여러 블록에 나눠 써도 병합됩니다.
terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
