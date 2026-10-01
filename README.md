# isucon

デプロイ (`Makefile` と `mk/`) と計測基盤 (`perf/`) の一式。リポジトリは、サーバ上の `REPO` (既定値は `/home/isucon`) に置く。

```
isucon/                      ← サーバでは /home/isucon
├── Makefile                 # 入口。ターゲット名を見て mk/ のファイルに振り分ける (make help)
├── mk/                      # 役割ごとの Makefile。deploy / setup / analyze / perf
│   └── vars.mk              # 問題ごとに変わる値。当日はここを書き換える
├── env.sh                   # systemd の EnvironmentFile (make etc-pull で取り込む)
├── etc/                     # /etc をパスそのままで写す (make deploy で rsync)
├── tools/alp.yaml           # alp の集計設定
├── webapp/                  # 運営配布の webapp をそのまま (make webapp-pull)
└── perf/                    # 別 EC2 に立てる ClickHouse / Grafana / Pyroscope / otelcol
```

## このテンプレートの使い方

前日までの準備が終わった状態のリポジトリ。問題に依存するもの (配布物、サーバの設定、`mk/vars.mk` の値) は入っていない。練習や本番のたびに、ここから新しいリポジトリを作る。

```
gh repo create <owner>/<repo> --template ntk221/isucon-template --private --clone
```

作ったあとは、当日の手順 (Notion の「isucon 初期セットアップ」か、`.claude/skills/isucon-setup/`) に沿って進める。`mk/vars.mk` の必須の値が空のままだと、make は案内を出して止まる。

## ホスト名 (isu1 / isu2 / isu3)

`mk/vars.mk` の `HOST` に入っているのは `~/.ssh/config` の **Host 別名**で、IP や鍵は書かない。
Makefile は `ssh isu1 '...'` を呼ぶだけなので、サーバの IP が変わっても直すのは `~/.ssh/config` の `HostName` だけ。
本番は 3 台 (isu1〜3) に役割を振り分けるが、今の `mk/` は 1 台構成用。分けるときは「3 台に分けるとき」を見る。

## Makefile の構成

`make <ターゲット>` は、入口の `Makefile` がターゲット名を見て、担当のファイルに渡す。各ファイルは単独でも動く (`make -f mk/deploy.mk deploy`)。

| ファイル | 役割 | ターゲット |
|---|---|---|
| `mk/deploy.mk` | デプロイ | `deploy` `deploy-db` `log` |
| `mk/setup.mk` | 初回だけ | `keys` `webapp-pull` `etc-pull` `bootstrap` |
| `mk/analyze.mk` | ログの集計 | `install-tools` `prep` `analyze` |
| `mk/perf.mk` | 計測用サーバ (使う場合だけ) | `perf-up` `perf-ip` `perf-deploy` `perf-allow-ip` `perf-open` `perf-allow` `perf-agent` `perf-agent-off` `perf-push` `perf-down` |

- 問題ごとに変わる値 (`HOST` `SERVICE` `EXEC` など) は `mk/vars.mk` にまとめてあり、各ファイルが先頭で読み込む。当日に書き換えるのはこのファイルだけ
- そのファイルの中でしか使わない値 (ログの場所、計測用サーバの設定など) は、各ファイルの冒頭にある
- 実行時に上書きもできる (`make deploy HOST=isu2`)
- `make -n <ターゲット>` で、実際に走るコマンドを実行せずに見られる
- 各ファイルのコマンドは 1 行ずつ実行され、失敗した行で止まる

新しいサーバに入って最初の deploy までの手順は Claude Code の skill (`.claude/skills/isucon-setup/`) にまとめてある。

## ローカルに必要なもの

`ssh` `rsync` `git` `curl` `jq`（`make analyze` の集計はローカルで jq を使う）、perf を使うなら `aws` CLI。macOS でも動く。

## 普段のサイクル

```
make deploy                      # main を push → pull → build → restart → smoke → ログ空に
（ポータルでベンチ）
make analyze SCORE=12345 NOTE="posts に index"   # alp / slow query / スコアを log/ に保存する
make perf-push                   # 計測用サーバを使うなら、最新の log/ の結果を送る
```

- ブランチを指定するときは `make deploy BRANCH=xxx`。省略すると main。良ければ main にマージ、戻すときは `git revert`
- デプロイ後にアプリが落ちたら `make log`（journalctl の直近 100 行。`N=300` で行数変更）
- `make analyze` は `log/<unixtime>-{alp,slow,result}.tsv` に保存する。`SCORE` は必須（fail なら `SCORE=0`）
- ベンチだけ回し直すときは `make prep`（ログを空にする）
- **analyze する前に deploy / prep を叩くとそのベンチのログは消える**
- `make deploy-db` は my.cnf を変えたときだけ（MySQL 再起動は遅い）

## 前日まで

1. `cp perf/.env.example perf/.env` してパスワードを変える
2. `make perf-up` → 出た IP を `~/.ssh/config` の `Host perf` に書く（`ssh_config.example`）
3. `make perf-deploy` → `http://<perf>:3000/d/isucon` が開けることを確認
   - SG は `perf-up` を叩いた人の IP しか通していない。他メンバーは `make perf-allow-ip IP=<その人のIP>`（Grafana / ClickHouse / Pyroscope）
4. 過去問で一度 `deploy → analyze` を通しておく

## private-isu で練習するとき (1 台構成)

private-isu は 1 台なので、今の `mk/` がそのまま使える。`mk/vars.mk` を次のように書き換える。

```make
SERVICE := isu-go
EXEC    := /home/isucon/private_isu/webapp/golang/app
```

- 初期状態は `isu-ruby` が動いている: `ssh isu1 'sudo systemctl disable --now isu-ruby && sudo systemctl enable --now isu-go'`
- `~/private_isu` は git clone 済みで `.git` がある。`git add` する前に `rm -rf ~/private_isu/.git`（残すと submodule 扱いで中身が入らない）

## 当日 (最初の 30 分)

1. `~/.ssh/config` に isu1/isu2/isu3 を書く（本番は 3 台。1 台しかなければ全部 isu1 でよい）
2. 当日マニュアルの「参考実装の切り替え方法」から service 名を確認して、`mk/vars.mk` の `SERVICE` と `EXEC` を書き換える
   （`EXEC` は `ssh isu1 systemctl cat <service>` の `ExecStart` のパスをそのまま。`APP_DIR` `BIN` `WEBAPP` はそこから決まる）。**`.gitignore` の生成物の行（`/webapp/go/isuride`）も同じパスに直す**
3. `make keys` → 表示された公開鍵を GitHub の Deploy keys に登録
4. `make install-tools` （alp / pt-query-digest）
5. isu1 上で初回コミット:
   ```
   ssh isu1
   cd ~ && git init && git remote add origin <REPO_URL>
   # ローカルからこのリポジトリの Makefile, etc/, tools/, .gitignore を isu1 に置く (scp か git fetch)
   git add -A && git commit -m init && git push -u origin main
   ```
   もしくはローカルで `make webapp-pull etc-pull` → commit/push → `make bootstrap`
   （配布物のディレクトリ名が `webapp` でなければ `.gitignore` の `!/webapp/` を合わせる）
6. `etc/nginx/nginx.conf` の `access_log` を `ltsv` に（`sites-enabled/*` や `conf.d/*` に別の `access_log` があればそちらも）、MySQL の slow log は `etc/mysql/mysql.conf.d/zz-isucon.cnf` で ON → `make deploy deploy-db`
7. `make perf-allow perf-agent` （CPU を Grafana に出す。時間が無ければ飛ばしてよい）
8. 初回ベンチ → `make analyze SCORE=...`

## 3 台に分けるとき

- DB を isu3 へ: `env.sh` の DB ホストを isu3 の内部 IP に、isu3 側で `bind-address` とユーザー権限 → `make deploy deploy-db`
- 今の `mk/` は 1 台構成用で、各ターゲットは `HOST` の 1 台だけを操作する。分けるときは、deploy / bootstrap / keys などにホストごとの行を書き足す (元のスケルトンは `git log` の最初のコミットの Makefile にある)
- app を isu2 にも: 上に加えて、`etc/nginx` の upstream に isu2 を追加 → `make deploy`

## Pyroscope を使うなら (任意)

`go get github.com/grafana/pyroscope-go` して main に:

```go
if addr := os.Getenv("PYROSCOPE_ADDR"); addr != "" {
    pyroscope.Start(pyroscope.Config{
        ApplicationName: "isucon",
        ServerAddress:   addr, // http://<perf>:4040
        ProfileTypes:    []pyroscope.ProfileType{pyroscope.ProfileCPU},
    })
}
```

`env.sh` の `PYROSCOPE_ADDR` で ON/OFF。

## 最終 (終了 30 分前)

1. `etc/nginx/nginx.conf` → `access_log off;`、`etc/mysql/mysql.conf.d/zz-isucon.cnf` → `slow_query_log = 0`、`env.sh` の `PYROSCOPE_ADDR=` を空に
2. `make deploy deploy-db`
3. 計測用サーバを使ったなら `make perf-agent-off`
4. 使っていない他言語のサービスが `disabled` か、`ssh isu1 systemctl list-unit-files` で見る（`enabled` のままだと、再起動したときに同じポートを取り合う）
5. 余裕があれば 1 台再起動して動くか
6. 競技後: `make perf-down`（EIP + EC2 を消す。放置すると課金が続く）

## 注意

- `make deploy` は各サーバで `git checkout -f --detach origin/<branch>` する（ローカル変更は捨てられる、サーバ側は常に detached HEAD）。**サーバ上で直接編集しない**（したら即コミットして `git push origin HEAD:<branch>`）
- `make deploy` は push されたものだけをデプロイする。ローカルの未コミットの変更は含まれない (警告も出ない)
- `sudo rsync -rl etc/ /etc/` は `--delete` なし。etc/ から消したファイルは /etc に残る
- CGO を使うライブラリ (go-sqlite3 など) があるとローカルビルドは面倒なので、この構成はサーバ上でビルドする
- perf の SG は自分の IP と競技サーバの IP だけ。`perf/.env` のパスワードは必ず変える
- コンテナのバージョンは `perf/compose.yaml` で固定推奨 (grafana / pyroscope は `latest` にしてあるので一度動いたら pin する)
