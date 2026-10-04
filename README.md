# isucon

デプロイと計測 (`Makefile` と `mk/`) の一式。リポジトリは、サーバ上の `REPO` (既定値は `/home/isucon`) に置く。

```
isucon/                      ← サーバでは /home/isucon
├── Makefile                 # 入口。ターゲット名を見て mk/ のファイルに振り分ける (make help)
├── mk/                      # 役割ごとの Makefile。deploy / setup / measure
│   └── vars.mk              # 問題ごとに変わる値。当日はここを書き換える
├── env.sh                   # systemd の EnvironmentFile (make etc-pull で取り込む)
├── etc/                     # /etc をパスそのままで写す (make deploy で rsync)
├── tools/
│   ├── alp.yaml             # alp の集計設定
│   ├── pprof-loop.sh        # サーバで CPU プロファイルを 10 秒ずつ取り続ける (etc/systemd/system/isu-pprof.service が動かす)
│   └── pprof-text.sh        # 合算した CPU プロファイルを、AI が読めるテキストにする (make measure が手元で呼ぶ)
└── webapp/                  # 運営配布の webapp をそのまま (make webapp-pull)
```

## このテンプレートの使い方

前日までの準備が終わった状態のリポジトリ。問題に依存するもの (配布物、サーバの設定、`mk/vars.mk` の値) は入っていない。練習や本番のたびに、ここから新しいリポジトリを作る。

```
gh repo create <owner>/<repo> --template ntk221/isucon-template --private --clone
```

作ったあとは、当日の手順 (Notion の「isucon あれこれ」か、`.claude/skills/isucon-setup/`) に沿って進める。`mk/vars.mk` の必須の値が空のままだと、make は案内を出して止まる。

## ホスト名 (isu1 / isu2 / isu3)

`mk/vars.mk` の `HOST` に入っているのは ssh の設定の **Host 別名**で、IP や鍵は書かない。
Makefile は `ssh isu1 '...'` を呼ぶだけなので、サーバの IP が変わっても直すのは ssh の設定の `HostName` だけ。

ISUCON 用の ssh の設定は、普段の `~/.ssh/config` とは別の `~/.ssh/isucon_config` に書く (中身は `ssh_config.example`)。
`~/.ssh/config` には、先頭 (どの Host ブロックよりも前) に `Include ~/.ssh/isucon_config` の 1 行だけを足す。Host ブロックの中や後ろに書くと、その Host に当たったときしか読まれない。
本番は 3 台 (isu1〜3) に役割を振り分けるが、今の `mk/` は 1 台構成用。分けるときは「3 台に分けるとき」を見る。

## Makefile の構成

`make <ターゲット>` は、入口の `Makefile` がターゲット名を見て、担当のファイルに渡す。各ファイルは単独でも動く (`make -f mk/deploy.mk deploy`)。

| ファイル | 役割 | ターゲット |
|---|---|---|
| `mk/deploy.mk` | デプロイ | `deploy` `deploy-db` `log` |
| `mk/setup.mk` | 初回だけ | `keys` `webapp-pull` `etc-pull` `bootstrap` |
| `mk/measure.mk` | 計測 (ログの集計と CPU プロファイル) | `install-tools` `prep` `measure` |

- 問題ごとに変わる値 (`HOST` `SERVICE` `EXEC` など) は `mk/vars.mk` にまとめてあり、各ファイルが先頭で読み込む。当日に書き換えるのはこのファイルだけ
- そのファイルの中でしか使わない値 (ログの場所など) は、各ファイルの冒頭にある
- 実行時に上書きもできる (`make deploy HOST=isu2`)
- `make -n <ターゲット>` で、実際に走るコマンドを実行せずに見られる
- 各ファイルのコマンドは 1 行ずつ実行され、失敗した行で止まる

新しいサーバに入って最初の deploy までの手順は Claude Code の skill (`.claude/skills/isucon-setup/`) にまとめてある。

## ローカルに必要なもの

`ssh` `rsync` `git` `curl` `jq` `go`（`make measure` は、slow query の集計に jq を、CPU プロファイルの合算に `go tool pprof` を、ローカルで使う）。macOS でも動く。

## 普段のサイクル

```
make deploy                      # 今のブランチを push → pull → build → restart (起動を確認) → ログと CPU プロファイルを空に
（ポータルでベンチ）
make measure                     # alp / slow query の集計、CPU プロファイル、今のコミットを log/ に保存する
```

- deploy するのは今 checkout しているブランチ。別のブランチを出すときは `make deploy BRANCH=xxx`。良ければ main にマージ、戻すときは `git revert`
- デプロイ後にアプリが落ちたら `make log`（journalctl の直近 100 行。`N=300` で行数変更）
- `make measure` は `log/<unixtime>-{alp,slow}.tsv` に集計を、`log/<unixtime>-commit.txt` に今のコミットを保存する。何を変えたかは `git log`、スコアはポータルの履歴で見る
- CPU プロファイルは、サーバの `isu-pprof` が 10 秒ずつ `/tmp/pprof/` に取り続けている。`make measure` がそれを合算して `log/<unixtime>-cpu.pprof` に、テキストにしたもの (top / 直前との diff / 重い関数のソース) を `log/<unixtime>-pprof.txt` に保存する
  - アプリが `net/http/pprof` を `localhost:6060` で開けている必要がある (skill の手順 5)
  - 取り続けている間は、手で `curl .../debug/pprof/profile` しても `cpu profiling already in use` で取れない
  - 動かすか止めるかは `mk/vars.mk` の `PROF` (on / off) で決まり、`make deploy` が反映する
- ベンチの結果を AI に読ませるときは、`.claude/skills/isucon-read-log/` の skill を使う (「最新のベンチの log を読んで」)
- ベンチだけ回し直すときは `make prep`（ログを空にする）
- **measure する前に deploy / prep を叩くとそのベンチのログと CPU プロファイルは消える**
- `make deploy-db` は my.cnf を変えたときだけ（MySQL 再起動は遅い）

## 前日まで

1. 過去問で一度 `deploy → measure` を通しておく

## private-isu で練習するとき (1 台構成)

private-isu は 1 台なので、今の `mk/` がそのまま使える。`mk/vars.mk` を次のように書き換える。

```make
SERVICE := isu-go
EXEC    := /home/isucon/private_isu/webapp/golang/app
```

- 初期状態は `isu-ruby` が動いている: `ssh isu1 'sudo systemctl disable --now isu-ruby && sudo systemctl enable --now isu-go'`
- `~/private_isu` は git clone 済みで `.git` がある。`git add` する前に `rm -rf ~/private_isu/.git`（残すと submodule 扱いで中身が入らない）

## 当日 (最初の 30 分)

1. `~/.ssh/isucon_config` に isu1/isu2/isu3 を書く（本番は 3 台。1 台しかなければ全部 isu1 でよい。書き方は `ssh_config.example`）
2. 当日マニュアルの「参考実装の切り替え方法」から service 名を確認して、`mk/vars.mk` の `SERVICE` と `EXEC` を書き換える
   （`EXEC` は `ssh isu1 systemctl cat <service>` の `ExecStart` のパスをそのまま。`APP_DIR` `BIN` `WEBAPP` はそこから決まる）
3. `make keys` → 表示された公開鍵を GitHub の Deploy keys に登録
4. `make install-tools` （alp / pt-query-digest）
5. ローカルで `make webapp-pull etc-pull` → commit/push → `make bootstrap`
   （`webapp-pull` は先に dry-run で取り込む量を出し、`LIMIT_MB` (100) を超えるなら取り込まずに止まる。そのときは出てきた大きいディレクトリを `EXCLUDE` に足す）
   （`.gitignore` の配布物の行は `webapp-pull` が `mk/vars.mk` の `EXEC` / `EXCLUDE` から書くので、手では直さない）
6. アプリの `main.go` に `net/http/pprof` の口を開ける (`localhost:6060`。skill の手順 5)
7. `etc/nginx/nginx.conf` の `access_log` を `ltsv` に（`sites-enabled/*` や `conf.d/*` に別の `access_log` があればそちらも）、MySQL の slow log は `etc/mysql/mysql.conf.d/zz-isucon.cnf` で ON → `make deploy deploy-db`
8. 初回ベンチ → `make measure`

## 3 台に分けるとき

- DB を isu3 へ: `env.sh` の DB ホストを isu3 の内部 IP に、isu3 側で `bind-address` とユーザー権限 → `make deploy deploy-db`
- 今の `mk/` は 1 台構成用で、各ターゲットは `HOST` の 1 台だけを操作する。分けるときは、deploy / bootstrap / keys などにホストごとの行を書き足す (元のスケルトンは `git log` の最初のコミットの Makefile にある)
- app を isu2 にも: 上に加えて、`etc/nginx` の upstream に isu2 を追加 → `make deploy`

## 最終 (終了 30 分前)

1. `etc/nginx/nginx.conf` → `access_log off;`、`etc/mysql/mysql.conf.d/zz-isucon.cnf` → `slow_query_log = 0`、`mk/vars.mk` → `PROF := off`
2. `make deploy deploy-db`（`PROF := off` なら `make deploy` が `isu-pprof` を `disable --now` する。`etc/` からユニットを消すだけでは止まらない）
3. 使っていない他言語のサービスが `disabled` か、`ssh isu1 systemctl list-unit-files` で見る（`enabled` のままだと、再起動したときに同じポートを取り合う）
4. 余裕があれば 1 台再起動して動くか

## 注意

- `make deploy` は各サーバで `git checkout -f --detach origin/<branch>` する（ローカル変更は捨てられる、サーバ側は常に detached HEAD）。**サーバ上で直接編集しない**（したら即コミットして `git push origin HEAD:<branch>`）
- `make deploy` は push されたものだけをデプロイする。ローカルの未コミットの変更は含まれない (警告も出ない)
- `sudo rsync -rl etc/ /etc/` は `--delete` なし。etc/ から消したファイルは /etc に残る
- CGO を使うライブラリ (go-sqlite3 など) があるとローカルビルドは面倒なので、この構成はサーバ上でビルドする
