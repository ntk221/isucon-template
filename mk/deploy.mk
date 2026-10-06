# デプロイ
include mk/vars.mk

# 既定は今 checkout しているブランチ。detached HEAD なら空になるので止める
BRANCH     ?= $(shell git branch --show-current)
N          ?= 100
NEED_BRANCH = @test -n "$(BRANCH)" || { echo "ブランチに checkout していない (detached HEAD)。BRANCH=xxx を指定する"; exit 1; }

.PHONY: deploy deploy-db log

deploy: ## 今のブランチを push → 全部の台で checkout・etc 反映 → アプリの台で build・再起動 (起動を確認) → nginx reload・ログと CPU プロファイルを空に
	$(NEED_BRANCH)
	git push origin $(BRANCH)
	for h in $(HOSTS); do ssh $$h 'cd $(REPO) && git fetch origin && git checkout -f --detach origin/$(BRANCH)' || exit 1; done
	for h in $(HOSTS); do ssh $$h 'sudo rsync -rl $(REPO)/etc/ /etc/ && sudo systemctl daemon-reload' || exit 1; done
	for h in $(APP_HOSTS); do ssh $$h 'cd $(APP_DIR) && PATH=/usr/local/go/bin:$$PATH go build -o $(BIN) . && sudo systemctl restart $(SERVICE)' || exit 1; done
	for h in $(APP_HOSTS); do ssh $$h 'sleep 2; systemctl is-active -q $(SERVICE)' || { echo "$$h の $(SERVICE) が起動していない"; ssh $$h 'sudo journalctl -u $(SERVICE) -n 20 --no-pager'; exit 1; }; done
	ssh $(WEB_HOST) 'sudo nginx -t && sudo systemctl reload nginx'
	ssh $(WEB_HOST) 'sudo truncate -c -s0 $(ACCESS_LOG)'
	ssh $(DB_HOST) 'sudo truncate -c -s0 $(SLOW_LOG)'
	for h in $(APP_HOSTS); do ssh $$h 'sudo systemctl enable -q isu-pprof && sudo systemctl restart isu-pprof' || exit 1; done
	@echo "deployed $(BRANCH)@$$(git rev-parse --short origin/$(BRANCH))"

deploy-db: ## 今のブランチを push → DB の台で checkout・etc 反映・DB 再起動 (my.cnf を変えたときだけ)
	$(NEED_BRANCH)
	git push origin $(BRANCH)
	ssh $(DB_HOST) 'cd $(REPO) && git fetch origin && git checkout -f --detach origin/$(BRANCH)'
	ssh $(DB_HOST) 'sudo rsync -rl $(REPO)/etc/ /etc/'
	ssh $(DB_HOST) 'sudo systemctl restart $(DB_SERVICE)'

log: ## アプリの台ごとに journalctl 直近 N 行 (N=100)
	for h in $(APP_HOSTS); do echo "== $$h"; ssh $$h 'sudo journalctl -u $(SERVICE) -n $(N) --no-pager'; done
