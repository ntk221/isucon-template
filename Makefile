DEPLOY  := deploy deploy-db log
SETUP   := install-tools keys webapp-pull etc-pull bootstrap schema-pull
MEASURE := prep measure show

.DEFAULT_GOAL := help
.PHONY: help $(DEPLOY) $(SETUP) $(MEASURE)

# 各ファイルの 1 行目 (# 役割) と、ターゲット行の ## 説明 を表示する
help:
	@for f in mk/deploy.mk mk/setup.mk mk/measure.mk; do \
	  echo "$$f  $$(sed -n '1s/^# //p' $$f)"; \
	  awk -F':.*## ' '/^[a-z-]+:.*## /{printf "  %-15s %s\n", $$1, $$2}' $$f; \
	done

$(DEPLOY):
	@$(MAKE) --no-print-directory -f mk/deploy.mk $@
$(SETUP):
	@$(MAKE) --no-print-directory -f mk/setup.mk $@
$(MEASURE):
	@$(MAKE) --no-print-directory -f mk/measure.mk $@
