# 로컬 랩에서 웹훅 연결하기

GitHub에서 로컬 Atlantis로는 웹훅이 닿지 않습니다 (NAT 뒤에 있으니까).
랩에서는 두 가지 중 하나를 씁니다.

## 방법 A — Gitea (기본, 권장)

`make gitops`로 Gitea(`:3000`)와 Atlantis(`:4141`)가 같이 뜹니다.
둘이 같은 Docker 네트워크에 있으므로 웹훅이 바로 닿습니다.

1. http://localhost:3000 에서 계정 생성 → 리포 생성 → 이 리포를 push
2. 설정 → Applications → 토큰 발급 → `lab/.env`의 `GITEA_TOKEN`
3. `make gitops`로 재시작
4. 리포 Settings → Webhooks → `http://atlantis:4141/events`,
   Content type `application/json`, secret은 `GH_WEBHOOK_SECRET`과 동일

PR을 하나 올리면 Atlantis가 코멘트를 답니다.

## 방법 B — 실제 GitHub + 터널

`cloudflared tunnel --url http://localhost:4141` 같은 걸로 공개 URL을
만들고 `ATLANTIS_ATLANTIS_URL`에 넣습니다.

⚠ 이 방법은 **로컬 Atlantis를 인터넷에 노출**합니다. Atlantis는
설계상 git 자격증명과 클라우드 자격증명을 함께 들고 있는 프로세스입니다.
웹훅 secret을 반드시 설정하고, 실습이 끝나면 터널을 내리세요.
자격증명도 랩 전용으로만 쓰세요.
