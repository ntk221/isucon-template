# 初回だけ
include mk/vars.mk

# 取り込まないもの (WEBAPP からのパス)。.gitignore にも同じものを書くので、サーバ側でも無視される
SKIP   := $(sort $(patsubst $(REPO)/$(WEBAPP)/%,/%,$(EXCLUDE) $(EXEC)))
IGNORE := !/$(WEBAPP)/ $(patsubst /%,/$(WEBAPP)/%,$(SKIP))

.PHONY: keys webapp-pull etc-pull bootstrap

keys: ## isu1 に GitHub 用の鍵を作り、公開鍵を表示 (Deploy key に登録する)
	ssh $(HOST) 'test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -q'
	ssh $(HOST) 'ssh-keygen -F github.com >/dev/null || ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null'
	ssh $(HOST) 'cat ~/.ssh/id_ed25519.pub'
	@echo "この公開鍵を GitHub の Deploy key に登録する (gh repo deploy-key add <file> --title $(HOST))"

webapp-pull: ## isu1 の webapp を手元にコピーし、.gitignore の末尾に配布物の行を書く
	rsync -rl --exclude .git $(addprefix --exclude ,$(SKIP)) $(HOST):$(REPO)/$(WEBAPP)/ $(WEBAPP)/
	sed -i.bak '/^# >>> webapp-pull/,/^# <<< webapp-pull/d' .gitignore && rm .gitignore.bak
	printf '%s\n' '# >>> webapp-pull が mk/vars.mk の EXEC / EXCLUDE から書く (手で直さない)' $(foreach p,$(IGNORE),'$(p)') '# <<< webapp-pull' >> .gitignore
	du -sh $(WEBAPP)

etc-pull: ## isu1 の nginx / mysql / systemd / env.sh を手元にコピー
	rsync -rl --rsync-path='sudo rsync' --exclude /ssl/ $(HOST):/etc/nginx/ etc/nginx/
	rsync -rl --rsync-path='sudo rsync' --exclude debian.cnf $(HOST):/etc/mysql/ etc/mysql/
	mkdir -p etc/systemd/system
	rsync -l --rsync-path='sudo rsync' $(HOST):/etc/systemd/system/$(SERVICE).service etc/systemd/system/
	rsync $(HOST):$(REPO)/env.sh env.sh

bootstrap: ## isu1 の REPO を git 管理にして origin/main を checkout
	git fetch -q origin
	@test -n "$$(git ls-tree --name-only origin/main $(WEBAPP))" || { echo "origin/main に $(WEBAPP)/ が無い (make webapp-pull → commit/push してから)"; exit 1; }
	ssh $(HOST) 'cd $(REPO) && git init -q && (git remote add origin $(REPO_URL) 2>/dev/null || git remote set-url origin $(REPO_URL))'
	ssh $(HOST) 'cd $(REPO) && git fetch origin && git checkout -f --detach origin/main && git status -s'
