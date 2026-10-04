# 可視化サーバ (使う場合だけ)
include mk/vars.mk

PERF_HOST   := perf
PERF_STACK  := isucon-perf
OTELCOL     := 0.142.0
LOG_DIR     := log
BENCH       ?= $(shell ls $(LOG_DIR)/*-result.tsv 2>/dev/null | sort | tail -1 | sed 's|.*/||; s|-result.tsv||')
IP          ?=

PERF_IP := $(shell ssh -G $(PERF_HOST) 2>/dev/null | awk '/^hostname /{print $$2}')
ifeq ($(PERF_IP),$(PERF_HOST))
PERF_IP :=
endif
CH_PASS   := $(shell grep '^CLICKHOUSE_PASSWORD=' perf/.env 2>/dev/null | cut -d= -f2-)
CH_INSERT  = curl -sSf --user isucon:$(CH_PASS) "http://$(PERF_IP):8123/?query=INSERT%20INTO%20isucon.$(1)%20FORMAT%20TSV" --data-binary @-
PERF_SG    = aws cloudformation describe-stacks --stack-name $(PERF_STACK) --query 'Stacks[0].Outputs[?OutputKey==`SecurityGroupId`].OutputValue' --output text
NEED_PERF  = @test -n "$(PERF_IP)" || { echo "~/.ssh/config に Host $(PERF_HOST) が無い (make perf-ip で IP を確認して追記する)"; exit 1; }

.PHONY: perf-up perf-ip perf-deploy perf-allow-ip perf-open perf-allow perf-agent perf-agent-off perf-push perf-down

perf-up: ## 可視化サーバを CloudFormation で作る
	aws cloudformation deploy --stack-name $(PERF_STACK) --template-file perf/perf.yaml \
	  --parameter-overrides GitHubUsername=$(GITHUB_USER) MyIp=$$(curl -s https://checkip.amazonaws.com)/32
	@echo "次に make perf-ip で IP を確認し、~/.ssh/config の Host $(PERF_HOST) に書く"

perf-ip: ## 可視化サーバの IP を表示
	@aws cloudformation describe-stacks --stack-name $(PERF_STACK) --query 'Stacks[0].Outputs[?OutputKey==`PublicIp`].OutputValue' --output text

perf-deploy: ## perf/ を送って docker compose up
	rsync -az --exclude .env.example perf/ $(PERF_HOST):~/perf/
	ssh $(PERF_HOST) 'cd ~/perf && docker compose up -d --remove-orphans && docker compose ps'

perf-allow-ip: ## IP= の人に Grafana / ClickHouse / Pyroscope を開ける
	@test -n "$(IP)" || { echo "IP=x.x.x.x を指定する (本人が curl -s https://checkip.amazonaws.com で調べる)"; exit 1; }
	for p in 3000 8123 4040; do aws ec2 authorize-security-group-ingress --group-id $$($(PERF_SG)) --protocol tcp --port $$p --cidr $(IP)/32; done

perf-open: ## Grafana / ClickHouse / Pyroscope の URL を表示
	$(NEED_PERF)
	@echo "Grafana    http://$(PERF_IP):3000/d/isucon  (admin / perf/.env の GRAFANA_PASSWORD)"
	@echo "ClickHouse http://$(PERF_IP):8123/play      (isucon / perf/.env の CLICKHOUSE_PASSWORD)"
	@echo "Pyroscope  http://$(PERF_IP):4040"

perf-allow: ## isu1 から可視化サーバへの送信 (4040 / 4318) を許可
	ip=$$(ssh $(HOST) 'curl -s https://checkip.amazonaws.com') && \
	  aws ec2 authorize-security-group-ingress --group-id $$($(PERF_SG)) --ip-permissions \
	    "IpProtocol=tcp,FromPort=4040,ToPort=4040,IpRanges=[{CidrIp=$$ip/32}]" \
	    "IpProtocol=tcp,FromPort=4318,ToPort=4318,IpRanges=[{CidrIp=$$ip/32}]"

perf-agent: ## isu1 に otelcol を入れて CPU 等を可視化サーバへ送る
	$(NEED_PERF)
	ssh $(HOST) 'command -v otelcol-contrib >/dev/null || (curl -sLo /tmp/otelcol.deb https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v$(OTELCOL)/otelcol-contrib_$(OTELCOL)_linux_$$(dpkg --print-architecture).deb && sudo apt-get install -y -qq /tmp/otelcol.deb)'
	sed 's/{{PERF_IP}}/$(PERF_IP)/g' perf/otelcol/agent.yaml | ssh $(HOST) 'sudo tee /etc/otelcol-contrib/config.yaml >/dev/null'
	ssh $(HOST) 'sudo systemctl enable otelcol-contrib && sudo systemctl restart otelcol-contrib'

perf-agent-off: ## isu1 の otelcol を止める
	ssh $(HOST) 'sudo systemctl disable --now otelcol-contrib 2>/dev/null || true'

perf-push: ## 最新 (BENCH=) の log/ の結果を ClickHouse に送る
	$(NEED_PERF)
	@test -n "$(BENCH)" || { echo "$(LOG_DIR)/ に make measure の結果が無い"; exit 1; }
	sed 's/\\/\\\\/g' $(LOG_DIR)/$(BENCH)-alp.tsv | awk -v b=$(BENCH) '{print b "\t" $$0}' | $(call CH_INSERT,alp)
	awk -v b=$(BENCH) '{print b "\t" $$0}' $(LOG_DIR)/$(BENCH)-slow.tsv | $(call CH_INSERT,slow)
	awk -v b=$(BENCH) '{print b "\t" $$0}' $(LOG_DIR)/$(BENCH)-result.tsv | $(call CH_INSERT,results)
	@echo "sent bench=$(BENCH) -> http://$(PERF_IP):3000/d/isucon"

perf-down: ## 可視化サーバを削除
	aws cloudformation delete-stack --stack-name $(PERF_STACK)
	@echo "削除の完了待ち: aws cloudformation wait stack-delete-complete --stack-name $(PERF_STACK)"
