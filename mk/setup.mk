# 初回だけ
include mk/vars.mk

# 配布物と設定の取り込み元。初回は全部の台が同じ中身なので、最初のアプリの台から取る
SRC    := $(firstword $(APP_HOSTS))

# 取り込まないもの (WEBAPP からのパス)。.gitignore にも同じものを書くので、サーバ側でも無視される
SKIP   := $(sort $(patsubst $(REPO)/$(WEBAPP)/%,/%,$(EXCLUDE) $(EXEC)))
IGNORE := !/$(WEBAPP)/ $(patsubst /%,/$(WEBAPP)/%,$(SKIP))
PULL   := -rl --exclude .git $(addprefix --exclude ,$(SKIP)) $(SRC):$(REPO)/$(WEBAPP)/ $(WEBAPP)/
# 取り込む量 (EXCLUDE を除いた後) の上限。超えると取り込まずに止まる
LIMIT_MB ?= 100

.PHONY: keys webapp-pull etc-pull bootstrap

keys: ## 全部の台に GitHub 用の鍵を作る (あれば作らない)。公開鍵は台ごとに Deploy key に登録する
	for h in $(HOSTS); do ssh $$h 'test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -q' || exit 1; done
	for h in $(HOSTS); do ssh $$h 'ssh-keygen -F github.com >/dev/null || ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null' || exit 1; done
	for h in $(HOSTS); do echo "== $$h"; ssh $$h 'cat ~/.ssh/id_ed25519.pub' || exit 1; done
	@echo "台ごとの公開鍵を、1 本ずつ GitHub の Deploy key に登録する (gh repo deploy-key add <file> --title <台>)"

webapp-pull: ## 最初のアプリの台の webapp を手元にコピーし、.gitignore の末尾に配布物の行を書く (LIMIT_MB=100 を超えるなら止まる)
	@mb=$$(rsync -n --stats $(PULL) | awk '/^total size is/{gsub(/,/,"",$$4); print int($$4/1048576)}'); \
	  test -n "$$mb" || { echo "rsync の dry-run に失敗した"; exit 1; }; \
	  echo "取り込む量: $${mb}MB (EXCLUDE を除いた後)"; \
	  test "$$mb" -le $(LIMIT_MB) || { echo "LIMIT_MB=$(LIMIT_MB) を超えるので取り込まない。大きいものを mk/vars.mk の EXCLUDE に足す (除外前の大きさ):"; ssh $(SRC) 'cd $(REPO)/$(WEBAPP) && du -h -d 3 . | sort -rh | head -15'; exit 1; }
	rsync $(PULL)
	sed -i.bak '/^# >>> webapp-pull/,/^# <<< webapp-pull/d' .gitignore && rm .gitignore.bak
	printf '%s\n' '# >>> webapp-pull が mk/vars.mk の EXEC / EXCLUDE から書く (手で直さない)' $(foreach p,$(IGNORE),'$(p)') '# <<< webapp-pull' >> .gitignore

etc-pull: ## 最初のアプリの台の nginx / mysql / systemd / env.sh を手元にコピー
	rsync -rl --rsync-path='sudo rsync' --exclude /ssl/ --exclude /tls/ $(SRC):/etc/nginx/ etc/nginx/
	rsync -rl --rsync-path='sudo rsync' --exclude debian.cnf $(SRC):/etc/mysql/ etc/mysql/
	mkdir -p etc/systemd/system
	rsync -l --rsync-path='sudo rsync' $(SRC):/etc/systemd/system/$(SERVICE).service etc/systemd/system/
	rsync $(SRC):$(REPO)/env.sh env.sh

bootstrap: ## 全部の台の REPO を git 管理にして origin/main を checkout
	git fetch -q origin
	@test -n "$$(git ls-tree --name-only origin/main $(WEBAPP))" || { echo "origin/main に $(WEBAPP)/ が無い (make webapp-pull → commit/push してから)"; exit 1; }
	for h in $(HOSTS); do ssh $$h 'cd $(REPO) && git init -q && (git remote add origin $(REPO_URL) 2>/dev/null || git remote set-url origin $(REPO_URL))' || exit 1; done
	for h in $(HOSTS); do echo "== $$h"; ssh $$h 'cd $(REPO) && git fetch origin && git checkout -f --detach origin/main && git status -s' || exit 1; done
