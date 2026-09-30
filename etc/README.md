# etc/

サーバの `/etc` をパスそのままで写す場所。`make deploy` で `sudo rsync -rl etc/ /etc/` される。

- 初回は `make etc-pull` で isu1 (nginx, systemd unit) と isu3 (mysql) から取り込んでコミット
- ここで用意してあるもの
  - `nginx/conf.d/ltsv.conf` … alp 用の `log_format ltsv`。**nginx.conf の `access_log` 行を `access_log /var/log/nginx/access.log ltsv;` に書き換える**。配布物は `sites-enabled/*` や `conf.d/*` 側にも `access_log` を持っていることが多いので `grep -rn access_log etc/nginx/` で全部確認
  - `mysql/mysql.conf.d/zz-isucon.cnf` … slow log ON。MariaDB の場合は `mysql/mariadb.conf.d/` に置く
- 最終前: `access_log off;` と `slow_query_log = 0` にして `make deploy deploy-db`（`make final` が `/etc/nginx` `/etc/mysql` 以下を再帰 grep して残りを表示する）
