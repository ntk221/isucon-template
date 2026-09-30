include mk/vars.mk

.PHONY: final

final:
	ssh $(HOST) 'systemctl list-unit-files --no-legend | grep -E "$(PATTERN)|nginx|mysql|mariadb|otelcol" || true'
	ssh $(HOST) 'sudo grep -rnE "^\s*(access_log|slow_query_log)" /etc/nginx/ /etc/mysql/ || true'
	ssh $(HOST) 'grep -H PYROSCOPE $(REPO)/env.sh || echo "env.sh に PYROSCOPE の設定なし"'
	ssh $(HOST) 'cd $(REPO) && git status -s && git log --oneline -1'
	@echo "確認: access_log off / slow_query_log = 0 / 使わない言語の $(PATTERN).* が disabled / otelcol が disabled / git status が空 / 再起動しても動く"
