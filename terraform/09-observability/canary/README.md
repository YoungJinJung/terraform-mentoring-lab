# Canary 번들 만들기

`aws_synthetics_canary`는 zip 파일을 요구합니다. 디렉터리 구조가 정해져 있습니다.

```
nodejs/node_modules/pageLoadBlueprint.js      ← handler = "pageLoadBlueprint.handler"
```

## 만들기

```bash
mkdir -p nodejs/node_modules
cat > nodejs/node_modules/pageLoadBlueprint.js <<'JS'
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const pageLoadBlueprint = async function () {
  const url = process.env.TARGET_URL || 'https://example.com';
  const page = await synthetics.getPage();

  const response = await synthetics.executeStep('loadPage', async () => {
    return await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  });

  if (!response || response.status() >= 400) {
    throw new Error(`실패: ${response ? response.status() : 'no response'}`);
  }

  // 스크린샷은 S3에 쌓입니다 — 보존 기간을 짧게 두세요
  await synthetics.takeScreenshot('loaded', 'result');

  // 내용까지 확인합니다. 200이지만 에러 페이지인 경우를 잡습니다.
  const body = await page.content();
  if (body.includes('Internal Server Error')) {
    throw new Error('200이지만 에러 페이지입니다');
  }
};

exports.handler = async () => {
  return await pageLoadBlueprint();
};
JS

zip -r canary.zip nodejs
```

## 왜 Canary를 쓰는가

지표와 로그는 **안에서 보는 것**입니다. 다음 상황에서 안쪽 지표는
전부 정상입니다.

- TLS 인증서 만료 → ALB는 정상, 사용자만 접속 불가
- Route 53 레코드 실수 → 트래픽이 아예 안 들어옴 → 5xx도 0
- CloudFront 캐시 설정 오류 → 옛 버전이 계속 서빙됨
- WAF 규칙이 정상 사용자를 차단 → 403은 WAF 지표에만

"RequestCount가 0이다"를 알람으로 잡는 것(`heartbeat` 알람)과
Canary는 같은 공백을 메우는 두 방법입니다. 둘 다 있는 게 좋습니다.

## 비용

`rate(5 minutes)`면 월 약 8,640회. 1분으로 줄이면 5배입니다.
Canary는 호출당 과금 + 아티팩트 S3 저장 + Lambda 실행이 붙습니다.
"핵심 경로 2~3개를 5분 주기"가 보통 적당한 지점입니다.
