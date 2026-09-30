# 問題ごとに書く値。決め方は .claude/skills/isucon-setup/SKILL.md の手順 3
HOST        := isu1
SERVICE     :=
EXEC        :=
SMOKE_URL   := http://localhost/
DB_SERVICE  := mysql
EXCLUDE     := node_modules
REPO_URL    :=
GITHUB_USER := ntk221

# 普段は変えない。配布物がホームの外にある問題だけ直す
REPO        := /home/isucon

REQUIRED := HOST SERVICE EXEC SMOKE_URL DB_SERVICE REPO_URL REPO
$(foreach v,$(REQUIRED),$(if $(strip $($(v))),,$(error mk/vars.mk の $(v) が空。「サーバーを調べる」の結果で埋める)))
$(if $(filter $(REPO)/%,$(EXEC)),,$(error mk/vars.mk の EXEC ($(EXEC)) が REPO ($(REPO)) の下にない))

# EXEC から決まる
APP_DIR := $(patsubst %/,%,$(dir $(EXEC)))
BIN     := $(notdir $(EXEC))
WEBAPP  := $(firstword $(subst /, ,$(patsubst $(REPO)/%,%,$(EXEC))))
