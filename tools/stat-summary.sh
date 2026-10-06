#!/bin/bash
# isu-stat の記録 (log/<日時>/stat-<台>.txt) から、ベンチの時間帯だけを切り出してまとめる。make measure が手元で呼ぶ
# 使い方: tools/stat-summary.sh <開始の unix 時刻> <終了の unix 時刻> log/<日時>/stat-<台>.txt ...
set -u
S=$1 E=$2; shift 2

echo "ベンチの時間帯 $(date -r "$S" +%H:%M:%S)〜$(date -r "$E" +%H:%M:%S) ($((E - S)) 秒)。100% = 1 コア"
for f in "$@"; do
  h=$(basename "$f" .txt); h=${h#stat-}
  awk -v s="$S" -v e="$E" '
    $1 < s || $1 > e { next }
    $2 == "cpu"  { n[$3]++; b[$3] += $4; if ($4 > bm[$3]) bm[$3] = $4; w[$3] += $5; st[$3] += $6; sec[$1] = 1; next }
    $2 == "proc" { p[$3] += $4; if ($4 > pm[$3]) pm[$3] = $4 }
    END {
      ns = 0; for (t in sec) ns++
      if (ns == 0) exit
      # 並べ替えのために、先頭に「節の番号」と「並び順のキー」を付けて出し、外の sort に任せる
      for (k in n) printf "1 %s %-12s %6.0f%% %6.0f%% %7.1f%% %6.1f%%\n", k, k, b[k] / n[k], bm[k], w[k] / n[k], st[k] / n[k]
      for (k in p) if (p[k] / ns >= 0.5) printf "2 %08d %-12s %6.0f%% %6.0f%%\n", 10000000 - p[k] / ns * 1000, k, p[k] / ns, pm[k]
    }' "$f" | sort | awk -v h="$h" '
    BEGIN { printf "%s\n  %-12s %7s %7s %8s %7s\n", h, "core", "avg", "max", "iowait", "steal" }
    $1 == 1 { sub(/^1 [^ ]+ /, ""); print "  " $0; next }
    $1 == 2 && !hd { printf "  %-12s %7s %7s\n", "process", "avg", "max"; hd = 1 }
    $1 == 2 { sub(/^2 [0-9]+ /, ""); if (++c <= 8) print "  " $0 }'
done
