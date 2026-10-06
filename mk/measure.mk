# 計測 (alp / pt-query-digest で集計し、CPU プロファイルを合算して log/ に保存)
include mk/vars.mk

LOG_DIR    := log
BENCH      := $(shell date +%s)
PROF_TMP   := $(LOG_DIR)/.pprof
# CPU プロファイルの置き場所は、tools/pprof-loop.sh の DIR だけで決める
PROF_DIR   := $(shell sed -n 's/^DIR=//p' tools/pprof-loop.sh)

.PHONY: install-tools prep measure

install-tools: ## nginx の台に alp を、DB の台に pt-query-digest を入れる
	ssh $(WEB_HOST) 'command -v alp >/dev/null || (curl -sL https://github.com/tkuchiki/alp/releases/latest/download/alp_linux_$$(dpkg --print-architecture).tar.gz | tar xz -C /tmp alp && sudo install /tmp/alp /usr/local/bin/alp)'
	ssh $(DB_HOST) 'command -v pt-query-digest >/dev/null || (sudo apt-get update -qq && sudo apt-get install -y -qq percona-toolkit)'

prep: ## アクセスログ / slow log / CPU プロファイルを空にする
	ssh $(WEB_HOST) 'sudo truncate -c -s0 $(ACCESS_LOG)'
	ssh $(DB_HOST) 'sudo truncate -c -s0 $(SLOW_LOG)'
	for h in $(APP_HOSTS); do ssh $$h 'sudo systemctl restart isu-pprof' || exit 1; done

measure: ## alp / slow query の集計、CPU プロファイル、今のコミットを log/ に保存
	mkdir -p $(LOG_DIR)
	ssh $(WEB_HOST) 'sudo alp ltsv --file $(ACCESS_LOG) --config $(REPO)/tools/alp.yaml' > $(LOG_DIR)/$(BENCH)-alp.tsv
	ssh $(DB_HOST) 'sudo pt-query-digest --output json --limit 50 $(SLOW_LOG) 2>/dev/null' \
	  | jq -r '.classes[] | [.fingerprint, .query_count, .metrics.Query_time.sum, .metrics.Query_time.avg, .metrics.Rows_examined.sum] | @tsv' > $(LOG_DIR)/$(BENCH)-slow.tsv
	git rev-parse --short HEAD > $(LOG_DIR)/$(BENCH)-commit.txt
	rm -rf $(PROF_TMP) && mkdir -p $(PROF_TMP)
	for h in $(APP_HOSTS); do mkdir -p $(PROF_TMP)/$$h && rsync -r --include '*.pprof' --exclude '*' $$h:$(PROF_DIR)/ $(PROF_TMP)/$$h/ 2>/dev/null; done; true
	@if ! ls $(PROF_TMP)/*/*.pprof >/dev/null 2>&1; then echo "CPU プロファイルがない (アプリが pprof の口を開けていない)"; \
	elif ! command -v go >/dev/null; then echo "手元に go がないので、CPU プロファイルを合算できない"; \
	else go tool pprof -symbolize=none -proto $(PROF_TMP)/*/*.pprof > $(LOG_DIR)/$(BENCH)-cpu.pprof && \
	  tools/pprof-text.sh $(LOG_DIR) $(BENCH) $(REPO) > $(LOG_DIR)/$(BENCH)-pprof.txt; fi
	rm -rf $(PROF_TMP)
	@echo "== alp"; head -15 $(LOG_DIR)/$(BENCH)-alp.tsv
	@echo "== slow query"; head -10 $(LOG_DIR)/$(BENCH)-slow.tsv | cut -c1-160
	@test ! -f $(LOG_DIR)/$(BENCH)-pprof.txt || { echo "== cpu (main. の関数、cum の大きい順)"; awk '/^## top \(cum\)/ {f = 1; next} /^## / {f = 0} f && $$6 ~ /^main\./ {printf "%10s %7s  %s\n", $$4, $$5, $$6}' $(LOG_DIR)/$(BENCH)-pprof.txt | head -10; }
	@echo "saved $(LOG_DIR)/$(BENCH)-* (commit $$(cat $(LOG_DIR)/$(BENCH)-commit.txt))"
