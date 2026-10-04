# 計測 (alp / pt-query-digest で集計して log/ に保存)
include mk/vars.mk

ACCESS_LOG := /var/log/nginx/access.log
SLOW_LOG   := /var/log/mysql/slow.log
LOG_DIR    := log
BENCH      := $(shell date +%s)

.PHONY: install-tools prep measure

install-tools: ## isu1 に alp / pt-query-digest を入れる
	ssh $(HOST) 'command -v alp >/dev/null || (curl -sL https://github.com/tkuchiki/alp/releases/latest/download/alp_linux_$$(dpkg --print-architecture).tar.gz | tar xz -C /tmp alp && sudo install /tmp/alp /usr/local/bin/alp)'
	ssh $(HOST) 'command -v pt-query-digest >/dev/null || (sudo apt-get update -qq && sudo apt-get install -y -qq percona-toolkit)'

prep: ## isu1 のアクセスログ / slow log を空にする
	ssh $(HOST) 'sudo truncate -c -s0 $(ACCESS_LOG) $(SLOW_LOG)'

measure: ## alp / slow query の集計と、今のコミットを log/ に保存
	mkdir -p $(LOG_DIR)
	ssh $(HOST) 'sudo alp ltsv --file $(ACCESS_LOG) --config $(REPO)/tools/alp.yaml' > $(LOG_DIR)/$(BENCH)-alp.tsv
	ssh $(HOST) 'sudo pt-query-digest --output json --limit 50 $(SLOW_LOG) 2>/dev/null' \
	  | jq -r '.classes[] | [.fingerprint, .query_count, .metrics.Query_time.sum, .metrics.Query_time.avg, .metrics.Rows_examined.sum] | @tsv' > $(LOG_DIR)/$(BENCH)-slow.tsv
	git rev-parse --short HEAD > $(LOG_DIR)/$(BENCH)-commit.txt
	@echo "== alp"; head -15 $(LOG_DIR)/$(BENCH)-alp.tsv
	@echo "== slow query"; head -10 $(LOG_DIR)/$(BENCH)-slow.tsv | cut -c1-160
	@echo "saved $(LOG_DIR)/$(BENCH)-* (commit $$(cat $(LOG_DIR)/$(BENCH)-commit.txt))"
