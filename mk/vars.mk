# 問題ごとに書く値。決め方は .claude/skills/isucon-setup/SKILL.md の手順 3
SERVICE     :=
EXEC        :=
DB_SERVICE  := mysql
EXCLUDE     := node_modules
REPO_URL    :=

# 台の役割 (ssh の設定の Host 名)。1 台のうちは全部 isu1 のまま。台を分けるときは、この 3 行だけを書き換える
# アプリ (build / restart / CPU プロファイル)。isu1 isu2 のように並べられる
APP_HOSTS   := isu1
# nginx (reload / アクセスログ)
WEB_HOST    := isu1
# MySQL (deploy-db / slow log)
DB_HOST     := isu1

# 普段は変えない。配布物がホームの外にある問題だけ直す
REPO        := /home/isucon
ACCESS_LOG  := /var/log/nginx/access.log
SLOW_LOG    := /var/log/mysql/slow.log
MYSQL_SOCK  := /var/run/mysqld/mysqld.sock

REQUIRED := SERVICE EXEC DB_SERVICE REPO_URL APP_HOSTS WEB_HOST DB_HOST REPO
$(foreach v,$(REQUIRED),$(if $(strip $($(v))),,$(error mk/vars.mk の $(v) が空。「サーバーを調べる」の結果で埋める)))
$(if $(filter $(REPO)/%,$(EXEC)),,$(error mk/vars.mk の EXEC ($(EXEC)) が REPO ($(REPO)) の下にない))

# 役割から決まる。HOSTS は役割のどれかを持つ全部の台 (checkout と etc の反映、鍵、bootstrap をする)
HOSTS   := $(sort $(APP_HOSTS) $(WEB_HOST) $(DB_HOST))
# EXEC から決まる
APP_DIR := $(patsubst %/,%,$(dir $(EXEC)))
BIN     := $(notdir $(EXEC))
WEBAPP  := $(firstword $(subst /, ,$(patsubst $(REPO)/%,%,$(EXEC))))
