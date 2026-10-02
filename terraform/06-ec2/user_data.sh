#!/bin/bash
set -euxo pipefail

# ─────────────────────────────────────────────────────────────────────
# user_data는 "인스턴스가 처음 뜰 때 한 번" 돌아갑니다.
# 이 파일을 고쳐도 기존 인스턴스는 바뀌지 않습니다 — Instance Refresh가
# 필요합니다. LAB 03에서 직접 확인합니다.
#
# 또 하나: user_data는 IMDS로 누구나 읽을 수 있습니다
#   TOKEN=$(curl -X PUT ... /latest/api/token)
#   curl -H "X-aws-ec2-metadata-token: $TOKEN" .../latest/user-data
# → 비밀을 여기 넣지 마세요. Secrets Manager / SSM에서 받아오세요.
# ─────────────────────────────────────────────────────────────────────

PORT=${app_port}
MSG="${message}"

dnf -y install python3

# IMDSv2로 자기 정보를 읽습니다. 이 호출 형태를 기억해 두세요 —
# IMDSv1(토큰 없는 GET)은 LT에서 막아두었으므로 실패합니다.
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

mkdir -p /opt/app
cat > /opt/app/server.py <<PY
import http.server, socketserver, os
MSG, IID, AZ = os.environ["MSG"], os.environ["IID"], os.environ["AZ"]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = b"ok"
        else:
            body = f"{MSG}\n{IID} @ {AZ}\n".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("", int(os.environ["PORT"])), H) as s:
    s.serve_forever()
PY

cat > /etc/systemd/system/app.service <<UNIT
[Unit]
Description=demo app
After=network.target

[Service]
Environment=PORT=$PORT
Environment=MSG=$MSG
Environment=IID=$IID
Environment=AZ=$AZ
ExecStart=/usr/bin/python3 /opt/app/server.py
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now app
