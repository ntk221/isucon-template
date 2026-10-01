---
name: isucon-setup
description: ISUCON の競技サーバ (練習の過去問でも本番でも) に入り、このリポジトリの Makefile で make deploy が通る状態まで持っていく初期セットアップ。サーバの IP を渡されて「セットアップして」「deploy できるようにして」「新しいサーバが来た」と言われたら使う。当日マニュアルを読む → サーバ調査 → Makefile / .gitignore / ssh config の書き換え → GitHub リポジトリと Deploy key → 取り込み → bootstrap → 初回 deploy まで。
---

# ISUCON 初期セットアップ

ゴール: ローカルで `make deploy` を叩くと、pull → build → restart → smoke が通る。
前提:
- リポジトリのルートは、サーバ上の `REPO` (`mk/vars.mk` の変数。既定値は `/home/isucon`) に置く。`EXEC` がその下に無いと make は止まる。そのときの決め方は手順 3 に書く
- Makefile は `~/.ssh/config` の Host 名 (isu1/isu2/isu3) しか知らない。`make -n <ターゲット>` で、実際に走るコマンドを実行せずに見られる

各ステップで確認を取り、失敗したら先へ進まない。サーバ側で直接ファイルを編集しない (すべてリポジトリ経由)。

## 0. 当日マニュアルを読む (サーバに触る前に)

サービス名、ディレクトリ、ポートなどは推測せずに、まずマニュアルから取る。ユーザーにマニュアルの URL かファイルを聞く。過去問なら `https://github.com/isucon/isucon<N>-<qualify|final>` の `docs/manual.md` にあることが多い。GitHub のファイルは `raw.githubusercontent.com` から curl で原文を読む (要約させない)。

マニュアルに期待する項目と、書いていないときの調べ方は [manual-checklist.md](manual-checklist.md) にある。このチェックリストの全項目について、マニュアルの記載を探す。

結果は次の 3 つに分けて、表でユーザーに見せる。

- **記載あり**: 値を控える。手順 2 でサーバの実物と突き合わせる
- **記載なし・サーバで調べられる**: チェックリストの「無いときの調べ方」を手順 2 でまとめて実行する
- **記載なし・サーバでは分からない**: ルールに関わる項目。ここでユーザーに確認する。確認できない項目は、チェックリストにある安全側の前提を置いて明記する

**練習環境はマニュアルどおりとは限らない。** 過去問の再現環境は、ユーザー名やインストール済みの言語が本番と違うことがある。マニュアルの値は仮説として扱い、手順 2 で必ずサーバ上の実物と突き合わせる。食い違いは notes に残す。

## 1. SSH で入れるようにする

1. 渡された IP ごとに `~/.ssh/config` に `Host isu1` (2 台目以降 isu2, isu3) を追記する。既にあれば HostName だけ直す。
   ```
   Host isu1
     HostName <IP>
     User <マニュアルのユーザー。練習環境では isucon のことも多い>
     IdentityFile <鍵>
     IdentitiesOnly yes
     ServerAliveInterval 30
     ControlMaster auto
     ControlPath ~/.ssh/cm-%r@%h:%p
     ControlPersist 10m
   ```

2. `ssh -o BatchMode=yes isu1 hostname` で確認。`Permission denied (publickey)` なら:
   - `ssh -v` で提示した鍵を確認する。**`gh` のログインは HTTPS トークンで、SSH の鍵にはならない**
   - 練習環境はたいてい構築時に `github.com/<user>.keys` を取り込む。`curl -s https://github.com/<user>.keys | ssh-keygen -lf -` と手元の鍵の指紋を比べる
   - 手元に対応する秘密鍵が無ければ、新しい鍵を作って `gh ssh-key add` (権限不足なら `gh auth refresh -h github.com -s admin:public_key` をユーザーに `!` 付きで実行してもらう)。取り込み直しにはサーバの再構築か、入れる人に authorized_keys への追加を頼む必要がある

## 2. サーバを調べる (読み取りのみ)

手順 0 の「記載あり」の値がサーバで本当にそうなっているかを、全台で確かめる。「記載なし・サーバで調べられる」の項目も、ここでチェックリストの調べ方を実行する。`PAT` はマニュアルのサービス名から作る (例: `isucari`)。マニュアルに記載が無いときだけ `isu` のような広いパターンで探す。結果は手順 0 の表に「サーバ上の実物」列を足して見せる。

```sh
ssh isu1 PAT=isucari 'bash -s' <<'SH'
uname -m; grep PRETTY /etc/os-release; nproc; free -h | head -2
sudo -n true && echo "sudo OK"
ls -la ~
systemctl list-unit-files --no-legend | grep -iE "$PAT|nginx|mysql|mariadb"
systemctl list-units --type=service --state=running --no-legend | grep -iE "$PAT|nginx|mysql|mariadb"
for s in $(systemctl list-unit-files --no-legend | awk -v p="$PAT" '$0 ~ p {print $1}'); do echo "-- $s"; systemctl cat $s | grep -E 'ExecStart|WorkingDirectory|EnvironmentFile'; done
export PATH=$HOME/local/golang/bin:/usr/local/go/bin:$PATH; go version
sudo ss -ltnp | grep -E ':(80|443|3306|[0-9]{4}) '
sudo grep -rn -E 'access_log|include' /etc/nginx/nginx.conf /etc/nginx/sites-enabled/ /etc/nginx/conf.d/
ls /etc/mysql/mysql.conf.d/ /etc/mysql/mariadb.conf.d/ 2>&1
cat ~/env.sh
find ~ -maxdepth 4 -size +10M -not -path '*/.cache/*' -not -path '*/local/*' -exec ls -lh {} \; | awk '{print $5, $9}'
du -sh ~/*/webapp/* 2>/dev/null | sort -h | tail -5
SH
```

見るべき点 (マニュアルとの差分を中心に):
- **動いている実装のサービス名** (例: `isucari.golang`) と、その `ExecStart` のパス。手順 3 で `SERVICE` と `EXEC` にそのまま入れる
- **`ExecStart` が `REPO` (既定は `/home/isucon`) の下にあるか**。無ければ手順 3 で `REPO` を決め直す
- **`ExecStart` のディレクトリに go.mod があるか**。無ければ手順 3 で `APP_DIR` を手で書く
- **nginx の listen ポートと `server_name`**。smoke の URL を決めるのに使う
- **巨大ファイル** (画像、初期データの SQL)。git にも rsync にも入れない
- MySQL か MariaDB か (slow log の conf の置き場所が変わる)

## 3. リポジトリ側を書き換える

1. **`mk/vars.mk` の変数**
   - Makefile は入口で、ターゲット名を見て `mk/deploy.mk` `mk/setup.mk` `mk/analyze.mk` `mk/perf.mk` に振り分けるだけ
   - 問題ごとに変わる値は `mk/vars.mk` にまとめてあり、各ファイルが先頭で読み込む。書き換えるのはこのファイルの上半分だけ。必須の値が空のままだと、make は案内を出して止まる
   - 書く値 (手順 0 と 2 の結果を写す)
     - `HOST`: 操作するサーバの Host 名。今の `mk/` は 1 台構成用で、全ファイルが同じ 1 台を操作する。2 台以上に分けるなら、ターゲットの中身をホストごとに書き足す
     - `SERVICE`: 動いている参照実装のサービス名 (例: `isucari.golang`)
     - `EXEC`: `systemctl cat <SERVICE>` の `ExecStart` のパス。引数が付いていればパスだけ (例: `/home/isucon/isucari/webapp/go/isucari`)
     - `SMOKE_URL`: deploy の最後にサーバ上から curl する URL。nginx が 80 なら `http://localhost/`、443 だけなら `https://localhost/`。`server_name` で名前を絞っていて localhost では返らないなら、マニュアルのホスト名にする。`ssh isu1 'curl -sk -o /dev/null -w "%{http_code}\n" <URL>'` が 200 になることを確かめる
     - `DB_SERVICE`: MySQL なら `mysql`、MariaDB なら `mariadb`
     - `EXCLUDE`: 取り込まない巨大ファイル。絶対パスか、配布物のディレクトリ (`WEBAPP`) からの相対 (例: `/webapp/public/upload`) で書く。`/public/upload` のように途中から書くと効かず、GB 単位で落ちてくる。ビルド済みのバイナリ (`EXEC`) は自動で除外される
     - `REPO_URL` と `GITHUB_USER`: GitHub のリポジトリと、GitHub のユーザー名
   - 自動で決まる値 (`EXEC` から計算する。`make -n deploy` と `make -n webapp-pull` で確かめる)
     - `APP_DIR`: `EXEC` のディレクトリ。ここで `go build` する
     - `BIN`: `EXEC` のファイル名
     - `WEBAPP`: `REPO` の直下にある配布物のディレクトリ (例: `isucari`)
     - ビルドしたバイナリがソースと別のディレクトリに置かれる問題では、`APP_DIR` の行を手で書き換える
   - `REPO`: サーバ上でリポジトリのルートにするディレクトリ。既定値は `/home/isucon` で、普段は変えない
     - 配布物を動かさずに git 管理できるように、`ExecStart` を含む場所にしている。`EXEC` が `REPO` の下に無いと、make はエラーで止まる
     - そのときは `REPO` を変えるか、アプリの配置と systemd の設定を変える。どちらにするかはユーザーと決める
   - ビルドは Go 前提 (`deploy.mk` の `go build` の行)。他の言語で戦うなら、その行を書き換える
2. **`.gitignore`**: 先頭の `/*` で `REPO` 直下は全部無視なので、配布物のディレクトリを `!/<WEBAPP>/` で許可する。巨大ファイル、ビルド生成物 (`EXEC` を `REPO` からのパスにしたもの。例: `/isucari/webapp/go/isucari`)、`node_modules`、`/etc/nginx/ssl/` (TLS 秘密鍵) を除外する
3. 除外の効き方は、仮のリポジトリにダミーファイルを置いて `git add -A && git status -s` で確認できる

## 4. GitHub とサーバの git

```sh
gh repo create <owner>/<repo> --template ntk221/isucon-template --private --clone   # 前日に済ませていなければ
make install-tools  # alp / pt-query-digest
make keys         # 表示された公開鍵を Deploy key に登録する
gh repo deploy-key add <pubkey file> -R <owner>/<repo> --title isu1
ssh isu1 'ssh -T git@github.com'   # "Hi <owner>/<repo>!" なら OK
```

## 5. 取り込み → 初回 push → bootstrap

```sh
make webapp-pull etc-pull
du -sh <WEBAPP>   # 数 MB 程度であること。大きければ `mk/vars.mk` の EXCLUDE を直して消してやり直す
```

- **nginx の access_log を ltsv に**: `log_format ltsv` は `etc/nginx/conf.d/ltsv.conf` にあり `include conf.d/*.conf;` で読まれる。**`access_log ... ltsv;` はその include より後ろに置く** (前だと unknown log format で nginx が落ちる)。`sites-enabled/` 側の `access_log` も確認
- 反映前にサーバで `nginx -t` を通す (一時ディレクトリに etc/nginx を送り、パスを差し替えた conf で `sudo nginx -t -c` を実行)
- `git ls-files | grep -iE 'pem|ssl|\.env$'` で秘密が入っていないことを確認してから commit / push

```sh
git add -A && git commit -m "配布物と設定を取り込む" && git push   # テンプレートから clone したリポジトリなので git init は要らない
make bootstrap    # サーバ側 git status が空であること
```

## 6. 初回 deploy と確認

```sh
make deploy       # 最後に "deployed main@<sha>" が出る
make deploy-db    # slow log を有効にする (MySQL 再起動)
```

確認項目:
- サーバのバイナリの更新時刻とサービスの `ActiveEnterTimestamp` が deploy 時刻になっている
- `sudo tail -1 /var/log/nginx/access.log` が ltsv 形式
- `sudo mysql -N -e 'SELECT @@slow_query_log'` が 1
- 何回か curl してから `make analyze SCORE=0 NOTE="動作確認"` で alp と slow query が集計される

最後に、結果と Makefile から変えた点を `notes/<日付>-*.md` に残して commit する。
