HOST        := isu1
REPO        := /home/isucon
SERVICE     :=
BIN         :=
APP_DIR     :=
DB_SERVICE  := mysql
SMOKE_URL   := http://localhost/
WEBAPP      :=
EXCLUDE     := node_modules
PATTERN     :=
REPO_URL    :=
GITHUB_USER := ntk221

REQUIRED := HOST REPO SERVICE BIN APP_DIR DB_SERVICE SMOKE_URL WEBAPP PATTERN REPO_URL
$(foreach v,$(REQUIRED),$(if $(strip $($(v))),,$(error mk/vars.mk の $(v) が空。「サーバーを調べる」の結果で埋める)))
