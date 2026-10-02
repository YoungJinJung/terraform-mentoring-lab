# ─────────────────────────────────────────────────────────────────────
# conftest 정책 — Atlantis policy_check 단계에서 plan JSON을 검사합니다.
#
#   terraform show -json tfplan > plan.json
#   conftest test --policy policies plan.json
#
# "리뷰어가 눈으로 잡던 것"을 기계가 잡게 만드는 단계입니다.
# ─────────────────────────────────────────────────────────────────────
package main

import rego.v1

# 변경되는 리소스만 추립니다 (no-op 제외).
changed := [r |
	some r in input.resource_changes
	some a in r.change.actions
	a != "no-op"
]

created_or_updated := [r |
	some r in changed
	some a in r.change.actions
	a in {"create", "update"}
]

# ── 1. 0.0.0.0/0 인바운드 금지 ─────────────────────────────────────
deny contains msg if {
	some r in created_or_updated
	r.type == "aws_security_group_rule"
	r.change.after.type == "ingress"
	"0.0.0.0/0" in r.change.after.cidr_blocks
	r.change.after.from_port != 443
	msg := sprintf("%s: 0.0.0.0/0 인바운드는 443만 허용합니다 (요청: %v)", [r.address, r.change.after.from_port])
}

deny contains msg if {
	some r in created_or_updated
	r.type == "aws_vpc_security_group_ingress_rule"
	r.change.after.cidr_ipv4 == "0.0.0.0/0"
	r.change.after.from_port != 443
	msg := sprintf("%s: 0.0.0.0/0 인바운드는 443만 허용합니다", [r.address])
}

# ── 2. S3 버킷은 암호화·퍼블릭 차단 필수 ───────────────────────────
deny contains msg if {
	some r in created_or_updated
	r.type == "aws_s3_bucket"
	not bucket_has_pab(r.change.after.bucket)
	msg := sprintf("%s: public_access_block 리소스가 같은 plan에 없습니다", [r.address])
}

bucket_has_pab(name) if {
	some r in input.resource_changes
	r.type == "aws_s3_bucket_public_access_block"
	r.change.after.bucket == name
}

# ── 3. IAM 와일드카드 ──────────────────────────────────────────────
deny contains msg if {
	some r in created_or_updated
	r.type in {"aws_iam_role_policy", "aws_iam_policy"}
	doc := json.unmarshal(r.change.after.policy)
	some st in doc.Statement
	st.Effect == "Allow"
	st.Action == "*"
	st.Resource == "*"
	msg := sprintf(`%s: Action="*" + Resource="*" Allow는 금지합니다`, [r.address])
}

# ── 4. 태그 ────────────────────────────────────────────────────────
required_tags := {"Project", "Environment", "ManagedBy"}

deny contains msg if {
	some r in created_or_updated
	r.type in {"aws_instance", "aws_db_instance", "aws_vpc", "aws_eks_cluster"}
	missing := required_tags - object.keys(object.get(r.change.after, "tags_all", {}))
	count(missing) > 0
	msg := sprintf("%s: 태그 누락 %v", [r.address, missing])
}

# ── 5. 삭제는 경고 (막지는 않음) ───────────────────────────────────
warn contains msg if {
	some r in changed
	"delete" in r.change.actions
	r.type in {"aws_db_instance", "aws_s3_bucket", "aws_eks_cluster"}
	msg := sprintf("%s 를 삭제합니다. 의도한 것인지 PR 설명에 적어주세요.", [r.address])
}

# ── 6. IMDSv1 금지 (모듈 6과 연결) ─────────────────────────────────
deny contains msg if {
	some r in created_or_updated
	r.type == "aws_instance"
	md := object.get(r.change.after, "metadata_options", [])
	count([m | some m in md; m.http_tokens == "required"]) == 0
	msg := sprintf("%s: metadata_options.http_tokens = \"required\" 가 필요합니다", [r.address])
}
