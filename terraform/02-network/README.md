# 모듈 2 · VPC와 애플리케이션 네트워킹

> 자료: [`docs/part2-vpc-networking.html`](../../docs/part2-vpc-networking.html)

## 핵심 실습

```bash
terraform apply                              # single (기본)
terraform plan -var nat_strategy=per_az      # 몇 개가 추가되나요?
terraform plan -var nat_strategy=none        # NAT·EIP·0.0.0.0/0 경로가 사라집니다
```

`local.nat_keys` 표현식 하나가 이 세 가지를 모두 처리합니다. 조건부 리소스 생성의
전형적인 패턴이라 읽어볼 가치가 있습니다.

## Floci에서 되는 것 / 안 되는 것

| 항목 | 로컬 | 비고 |
|---|:--:|---|
| VPC·서브넷·라우팅·SG 생성 | ✅ | API 객체로는 만들어집니다 |
| **실제 통신 (ping·curl)** | ❌ | 패킷이 흐르지 않습니다 |
| VPC Peering 구성 | ⚠️ | 객체는 만들어지나 통신 검증 불가 |
| **VPC Lattice** | ❌ | Floci 지원 서비스 목록에 없음 |

`make smoke M=02`로 현재 환경의 실제 결과를 확인하세요.

통신 검증이 필요한 LAB 02(Peering ping 실험)는 실제 AWS에서 10분이면 됩니다.
VPC 두 개 + EC2 두 대라 비용이 거의 없습니다.
