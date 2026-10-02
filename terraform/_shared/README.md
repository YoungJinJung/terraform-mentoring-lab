# _shared

모든 모듈이 심볼릭 링크로 공유하는 provider·버전·공통 변수입니다.

각 모듈 디렉터리에서:

```bash
ln -s ../_shared/provider.tf  provider.tf
ln -s ../_shared/versions.tf  versions.tf
ln -s ../_shared/variables.tf variables.tf
```

`bootstrap.sh`가 이 링크를 한 번에 걸어줍니다.
