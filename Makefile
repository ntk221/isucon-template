DEPLOY  := deploy deploy-db log
SETUP   := keys webapp-pull etc-pull bootstrap
ANALYZE := setup prep analyze
PERF    := perf-up perf-ip perf-deploy perf-allow-ip perf-open perf-allow perf-agent perf-agent-off perf-push perf-down

.DEFAULT_GOAL := help
.PHONY: help $(DEPLOY) $(SETUP) $(ANALYZE) $(PERF)

help:
	@echo "mk/deploy.mk   デプロイ          $(DEPLOY)"
	@echo "mk/setup.mk    初回だけ          $(SETUP)"
	@echo "mk/analyze.mk  ログの集計        $(ANALYZE)"
	@echo "mk/perf.mk     計測用サーバ      $(PERF)"

$(DEPLOY):
	@$(MAKE) --no-print-directory -f mk/deploy.mk $@
$(SETUP):
	@$(MAKE) --no-print-directory -f mk/setup.mk $@
$(ANALYZE):
	@$(MAKE) --no-print-directory -f mk/analyze.mk $@
$(PERF):
	@$(MAKE) --no-print-directory -f mk/perf.mk $@
