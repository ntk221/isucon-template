#!/bin/bash
# log/<日時>/ の結果を、列の意味つきで表示する。make show と make measure が呼ぶ
# 使い方: tools/show.sh log/<日時>
set -u
D=$1

echo "== $D/ (commit $(cat "$D/commit.txt"))"

echo
echo "== alp: エンドポイントごと。合計の大きい順に 15 行 (時間は秒)"
echo "   sum = 合計、avg = 平均、p90 = 9 割のリクエストがこれ以下、max = 最大"
printf '%6s %5s %4s %4s %9s %7s %7s %7s  %-6s %s\n' count 2xx 4xx 5xx sum avg p90 max method uri
head -15 "$D/alp.tsv" | awk -F'\t' '{printf "%6d %5d %4d %4d %9.2f %7.3f %7.3f %7.3f  %-6s %s\n", $1, $2, $3, $4, $7, $8, $9, $10, $5, $6}'

echo
echo "== slow query: クエリの形ごと。合計の大きい順に 10 件 (時間は秒)"
echo "   rows/q = 1 回あたりに読んだ行数 (Rows_examined の合計 / count)。大きいものは index が効いていない疑い"
printf '%7s %9s %8s %9s  %s\n' count sum avg rows/q query
head -10 "$D/slow.tsv" | awk -F'\t' '{printf "%7d %9.2f %8.4f %9.0f  %s\n", $2, $3, $4, ($2 ? $5 / $2 : 0), substr($1, 1, 100)}'

if [ -f "$D/pprof.txt" ]; then
  echo
  echo "== cpu: アプリの関数 (main.)。呼び出し先も含めた CPU 時間 (cum) の大きい順に 5 個"
  echo "   cum% = CPU 時間の全体に占める割合"
  printf '%9s %7s  %s\n' cum cum% function
  awk '/^## main\. の関数/ {f = 1; next} /^## / {f = 0} f && $6 ~ /^main\./ {printf "%9s %7s  %s\n", $4, $5, $6}' "$D/pprof.txt" | head -5
fi
