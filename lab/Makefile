SHELL := /bin/bash
.DEFAULT_GOAL := help
COMPOSE := docker compose

help: ## 명령 목록
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

up: ## Floci + 콘솔 기동
	$(COMPOSE) up -d
	@echo "  콘솔  http://localhost:4500"
	@echo "  API   http://localhost:4566"

cicd: ## + Jenkins
	$(COMPOSE) --profile cicd up -d

gitops: ## + Gitea + Atlantis
	$(COMPOSE) --profile gitops up -d

down: ## 중지
	$(COMPOSE) --profile cicd --profile gitops down

reset: ## 중지 + 데이터 전부 삭제
	$(COMPOSE) --profile cicd --profile gitops down -v

logs: ## 로그 따라가기
	$(COMPOSE) logs -f --tail=100

smoke: ## 실습 가능 범위 실측 → docs/FLOCI-SUPPORT.md
	@./scripts/smoke-test.sh $(M)

env: ## 쉘에 적용할 환경변수 출력 (eval "$$(make env)")
	@cat scripts/env.sh

.PHONY: help up cicd gitops down reset logs smoke env
