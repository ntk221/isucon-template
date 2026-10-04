# 問題ごとに書く値。決め方は .claude/skills/isucon-setup/SKILL.md の手順 3
HOST        := isu1
SERVICE     :=
EXEC        :=
DB_SERVICE  := mysql
EXCLUDE     := node_modules
REPO_URL    :=

# CPU プロファイルを取り続けるか (on / off)。make deploy が見て、isu-pprof を起動・停止する。終了 30 分前に off にする
PROF        := on

# 普段は変えない。配布物がホームの外にある問題だけ直す
REPO        := /home/isucon
# CPU プロファイルの置き場所。tools/pprof-loop.sh の DIR と同じにする
PROF_DIR    := /tmp/pprof

REQUIRED := HOST SERVICE EXEC DB_SERVICE REPO_URL REPO
$(foreach v,$(REQUIRED),$(if $(strip $($(v))),,$(error mk/vars.mk の $(v) が空。「サーバーを調べる」の結果で埋める)))
$(if $(filter $(REPO)/%,$(EXEC)),,$(error mk/vars.mk の EXEC ($(EXEC)) が REPO ($(REPO)) の下にない))

# EXEC から決まる
APP_DIR := $(patsubst %/,%,$(dir $(EXEC)))
BIN     := $(notdir $(EXEC))
WEBAPP  := $(firstword $(subst /, ,$(patsubst $(REPO)/%,%,$(EXEC))))
