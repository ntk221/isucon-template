# 計測 (alp / pt-query-digest で集計し、CPU プロファイルを合算して log/<日時>/ に保存)
include mk/vars.mk

LOG_DIR    := log
# ベンチ 1 回分の置き場所。日時 (20261006-123712) にするのは、ポータルの履歴の時刻と突き合わせるため
BENCH      := $(shell date +%Y%m%d-%H%M%S)
OUT        := $(LOG_DIR)/$(BENCH)
# make show で表示するベンチ (log/ の下のフォルダ名)。省略すると最新
B          ?= $(notdir $(patsubst %/,%,$(lastword $(sort $(wildcard $(LOG_DIR)/*/)))))
SHOW       := $(LOG_DIR)/$(B)
PROF_TMP   := $(LOG_DIR)/.pprof
# CPU プロファイルの置き場所は、tools/pprof-loop.sh の DIR だけで決める
PROF_DIR   := $(shell sed -n 's/^DIR=//p' tools/pprof-loop.sh)
# 台の CPU の記録の置き場所は、tools/stat-loop.sh の DIR だけで決める
STAT_DIR   := $(shell sed -n 's/^DIR=//p' tools/stat-loop.sh)

.PHONY: prep measure show

prep: ## アクセスログ / slow log / CPU プロファイル / 台の CPU の記録を空にする
	ssh $(WEB_HOST) 'sudo truncate -c -s0 $(ACCESS_LOG)'
	ssh $(DB_HOST) 'sudo truncate -c -s0 $(SLOW_LOG)'
	for h in $(APP_HOSTS); do ssh $$h 'sudo systemctl restart isu-pprof' || exit 1; done
	for h in $(HOSTS); do ssh $$h 'sudo systemctl restart isu-stat' || exit 1; done

measure: ## alp / slow query の集計、CPU プロファイル、今のコミットを log/<日時>/ に保存
	mkdir -p $(OUT)
	ssh $(WEB_HOST) 'sudo alp ltsv --file $(ACCESS_LOG) --config $(REPO)/tools/alp.yaml' > $(OUT)/alp.tsv
	ssh $(DB_HOST) 'sudo pt-query-digest --output json --limit 50 $(SLOW_LOG) 2>/dev/null' \
	  | jq -r '.classes[] | [.fingerprint, .query_count, .metrics.Query_time.sum, .metrics.Query_time.avg, .metrics.Rows_examined.sum] | @tsv' > $(OUT)/slow.tsv
	git rev-parse --short HEAD > $(OUT)/commit.txt
	rm -rf $(PROF_TMP) && mkdir -p $(PROF_TMP)
	for h in $(APP_HOSTS); do mkdir -p $(PROF_TMP)/$$h && rsync -r --include '*.pprof' --exclude '*' $$h:$(PROF_DIR)/ $(PROF_TMP)/$$h/ 2>/dev/null; done; true
	@if ! ls $(PROF_TMP)/*/*.pprof >/dev/null 2>&1; then echo "CPU プロファイルがない (アプリが pprof の口を開けていない)"; \
	elif ! command -v go >/dev/null; then echo "手元に go がないので、CPU プロファイルを合算できない"; \
	else go tool pprof -symbolize=none -proto $(PROF_TMP)/*/*.pprof > $(OUT)/cpu.pprof && \
	  tools/pprof-text.sh $(LOG_DIR) $(BENCH) $(REPO) > $(OUT)/pprof.txt; fi
	rm -rf $(PROF_TMP)
	ssh $(WEB_HOST) 'bash $(REPO)/tools/bench-window.sh $(ACCESS_LOG)' > $(OUT)/window.txt
	for h in $(HOSTS); do rsync -q $$h:$(STAT_DIR)/stat.txt $(OUT)/stat-$$h.txt 2>/dev/null; done; true
	@if [ -s $(OUT)/window.txt ] && ls $(OUT)/stat-*.txt >/dev/null 2>&1; then tools/stat-summary.sh $$(cat $(OUT)/window.txt) $(OUT)/stat-*.txt > $(OUT)/host.txt; \
	else echo "台の CPU の記録がない (isu-stat が動いていないか、アクセスログが空)"; fi
	@$(MAKE) --no-print-directory -f mk/measure.mk show B=$(BENCH)

show: ## log/<日時>/ の結果を表示する (B=20261006-123712。省略すると最新)
	@test -n "$(B)" -a -d $(SHOW) || { echo "log/$(B) がない。ls log/ でフォルダ名を見て B=<日時> を付ける"; exit 1; }
	@tools/show.sh $(SHOW)
