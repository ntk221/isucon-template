# デプロイ
include mk/vars.mk

BRANCH     ?= main
N          ?= 100

.PHONY: deploy deploy-db log

deploy: ## push → isu1 で checkout・etc 反映・build・再起動・smoke・ログを空に (BRANCH=)
	git push origin $(BRANCH)
	ssh $(HOST) 'cd $(REPO) && git fetch origin && git checkout -f --detach origin/$(BRANCH)'
	ssh $(HOST) 'sudo rsync -rl $(REPO)/etc/ /etc/ && sudo systemctl daemon-reload'
	ssh $(HOST) 'cd $(APP_DIR) && PATH=/usr/local/go/bin:$$PATH go build -o $(BIN) .'
	ssh $(HOST) 'sudo systemctl restart $(SERVICE)'
	ssh $(HOST) 'sudo nginx -t && sudo systemctl reload nginx'
	ssh $(HOST) 'curl -skf --retry 5 --retry-delay 1 --retry-all-errors -o /dev/null $(SMOKE_URL)'
	ssh $(HOST) 'sudo truncate -c -s0 /var/log/nginx/access.log /var/log/mysql/slow.log'
	@echo "deployed $(BRANCH)@$$(git rev-parse --short origin/$(BRANCH))"

deploy-db: ## push → isu1 で etc 反映・DB 再起動 (my.cnf を変えたときだけ)
	git push origin $(BRANCH)
	ssh $(HOST) 'cd $(REPO) && git fetch origin && git checkout -f --detach origin/$(BRANCH)'
	ssh $(HOST) 'sudo rsync -rl $(REPO)/etc/ /etc/'
	ssh $(HOST) 'sudo systemctl restart $(DB_SERVICE)'

log: ## アプリの journalctl 直近 N 行 (N=100)
	ssh $(HOST) 'sudo journalctl -u $(SERVICE) -n $(N) --no-pager'
