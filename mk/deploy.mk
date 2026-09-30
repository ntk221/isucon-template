include mk/vars.mk

BRANCH     ?= main
N          ?= 100

.PHONY: deploy deploy-db log

deploy:
	git push origin $(BRANCH)
	ssh $(HOST) 'cd $(REPO) && git fetch origin && git checkout -f --detach origin/$(BRANCH)'
	ssh $(HOST) 'sudo rsync -rl $(REPO)/etc/ /etc/ && sudo systemctl daemon-reload'
	ssh $(HOST) 'cd $(APP_DIR) && PATH=/usr/local/go/bin:$$PATH go build -o $(BIN) .'
	ssh $(HOST) 'sudo systemctl restart $(SERVICE)'
	ssh $(HOST) 'sudo nginx -t && sudo systemctl reload nginx'
	ssh $(HOST) 'curl -skf --retry 5 --retry-delay 1 --retry-all-errors -o /dev/null $(SMOKE_URL)'
	ssh $(HOST) 'sudo truncate -c -s0 /var/log/nginx/access.log /var/log/mysql/slow.log'
	@echo "deployed $(BRANCH)@$$(git rev-parse --short origin/$(BRANCH))"

deploy-db:
	git push origin $(BRANCH)
	ssh $(HOST) 'cd $(REPO) && git fetch origin && git checkout -f --detach origin/$(BRANCH)'
	ssh $(HOST) 'sudo rsync -rl $(REPO)/etc/ /etc/'
	ssh $(HOST) 'sudo systemctl restart $(DB_SERVICE)'

log:
	ssh $(HOST) 'sudo journalctl -u $(SERVICE) -n $(N) --no-pager'
