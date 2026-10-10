# upstream/ — 참조 리포

실습 참고 자료의 원본 리포들을 **git submodule로** 참조합니다.
복사본이 아니라 포인터이므로, 원본이 바뀌면
`git submodule update --remote`로 따라갈 수 있습니다.

## 가져오기

```bash
git submodule update --init --recursive
```

처음 클론할 때 한 번에 하려면:

```bash
git clone --recurse-submodules https://github.com/YoungJinJung/terraform-mentoring-lab.git
```

## 목록

| 서브모듈 | 쓰이는 모듈 | 내용 |
|---|---|---|
| `terraform-provisioning` | 1·2·3·6·7·8 | VPC·EKS·ECS 프로비저닝 레퍼런스 |
| `atlantis-deploy` | 4 | Atlantis 배포 매니페스트 |
| `jenkins-deploy-script` | 5 | Jenkins 배포 스크립트 |
| `demoapp-deploy` | 5·7·8 | 배포 대상 샘플 앱 |
| `springboot-sample` | 7·8 | 컨테이너화할 Spring Boot 앱 |
| `k8s-common-chart` | 8 | 공통 Helm 차트 |
| `k8s-app-chart` | 8 | 앱 Helm 차트 |
| `k8s-chart-value` | 8 | 환경별 values |

## 서브모듈로 둔 이유

| | 복사 | 서브모듈 |
|---|---|---|
| 원본 업데이트 추적 | 안 됨 | `--remote`로 가능 |
| 저작자 이력 | 사라짐 | 유지 |
| 리포 크기 | 커짐 | 포인터만 |
| 클론 한 번에 | 됨 | `--recurse-submodules` 필요 |

멘티가 "원본은 어디서 왔는지"를 추적할 수 있는 게 더 중요하다고 봤습니다.

## 주의 — 이건 레퍼런스입니다

`terraform/` 아래 모듈이 **이 멘토링의 실습 코드**입니다.
`upstream/`은 "원본은 이렇게 생겼다"를 보기 위한 것이고,
그대로 apply하면 과정 자료와 다른 리소스가 생깁니다.
