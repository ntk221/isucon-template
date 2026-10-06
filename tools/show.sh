#!/bin/bash
# log/<日時>/ の結果を、列の意味つきで表示する。make show と make measure が呼ぶ
# 使い方: tools/show.sh log/<日時>
# 色は端末に出すときだけ付ける (パイプやファイルには付けない。NO_COLOR=1 でも付けない)
set -u
D=$1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  HEAD=$'\e[1;36m' BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' YEL=$'\e[33m' OFF=$'\e[0m'
else
  HEAD= BOLD= DIM= RED= YEL= OFF=
fi
# 1 回あたりに読んだ行数がこれ以上のクエリを赤にする
ROWS_WARN=1000

echo "${HEAD}== $D/${OFF} (commit $(cat "$D/commit.txt"))"

if [ -f "$D/host.txt" ]; then
  echo
  echo "${HEAD}== host: 台の CPU。ベンチの時間帯の、コアごとの使用率とプロセスごとの %CPU${OFF}"
  echo "${DIM}   どちらも全部のコアが埋まっていれば CPU が張り付いている。片方のコアだけ高いなら直列やロックの疑い。iowait が高いならディスク${OFF}"
  sed 's/^/   /' "$D/host.txt"
fi

echo
echo "${HEAD}== alp: エンドポイントごと。合計の大きい順に 15 行 (時間は秒)${OFF}"
echo "${DIM}   sum = 合計、avg = 平均、p90 = 9 割のリクエストがこれ以下、max = 最大。4xx は黄、5xx は赤${OFF}"
printf "${BOLD}%6s %5s %4s %4s %9s %7s %7s %7s  %-6s %s${OFF}\n" count 2xx 4xx 5xx sum avg p90 max method uri
head -15 "$D/alp.tsv" | awk -F'\t' -v red="$RED" -v yel="$YEL" -v off="$OFF" '{
  c4 = sprintf("%4d", $3); if ($3 > 0) c4 = yel c4 off
  c5 = sprintf("%4d", $4); if ($4 > 0) c5 = red c5 off
  printf "%6d %5d %s %s %9.2f %7.3f %7.3f %7.3f  %-6s %s\n", $1, $2, c4, c5, $7, $8, $9, $10, $5, $6
}'

echo
echo "${HEAD}== slow query: クエリの形ごと。合計の大きい順に 10 件 (時間は秒)${OFF}"
echo "${DIM}   rows/q = 1 回あたりに読んだ行数 (Rows_examined の合計 / count)。${ROWS_WARN} 以上は赤で、index が効いていない疑い${OFF}"
printf "${BOLD}%7s %9s %8s %9s  %s${OFF}\n" count sum avg rows/q query
head -10 "$D/slow.tsv" | awk -F'\t' -v red="$RED" -v off="$OFF" -v warn="$ROWS_WARN" '{
  rq = $2 ? $5 / $2 : 0
  r = sprintf("%9.0f", rq); if (rq >= warn) r = red r off
  printf "%7d %9.2f %8.4f %s  %s\n", $2, $3, $4, r, substr($1, 1, 100)
}'

if [ -f "$D/pprof.txt" ]; then
  echo
  echo "${HEAD}== cpu: アプリの関数 (main.)。呼び出し先も含めた CPU 時間 (cum) の大きい順に 5 個${OFF}"
  echo "${DIM}   cum% = CPU 時間の全体に占める割合${OFF}"
  printf "${BOLD}%9s %7s  %s${OFF}\n" cum cum% function
  awk '/^## main\. の関数/ {f = 1; next} /^## / {f = 0} f && $6 ~ /^main\./ {printf "%9s %7s  %s\n", $4, $5, $6}' "$D/pprof.txt" | head -5
fi
