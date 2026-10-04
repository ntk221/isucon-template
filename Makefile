DEPLOY  := deploy deploy-db log
SETUP   := keys webapp-pull etc-pull bootstrap
MEASURE := install-tools prep measure
PERF    := perf-up perf-ip perf-deploy perf-allow-ip perf-open perf-allow perf-agent perf-agent-off perf-push perf-down

.DEFAULT_GOAL := help
.PHONY: help $(DEPLOY) $(SETUP) $(MEASURE) $(PERF)

# 各ファイルの 1 行目 (# 役割) と、ターゲット行の ## 説明 を表示する
help:
	@for f in mk/deploy.mk mk/setup.mk mk/measure.mk mk/perf.mk; do \
	  echo "$$f  $$(sed -n '1s/^# //p' $$f)"; \
	  awk -F':.*## ' '/^[a-z-]+:.*## /{printf "  %-15s %s\n", $$1, $$2}' $$f; \
	done

$(DEPLOY):
	@$(MAKE) --no-print-directory -f mk/deploy.mk $@
$(SETUP):
	@$(MAKE) --no-print-directory -f mk/setup.mk $@
$(MEASURE):
	@$(MAKE) --no-print-directory -f mk/measure.mk $@
$(PERF):
	@$(MAKE) --no-print-directory -f mk/perf.mk $@
