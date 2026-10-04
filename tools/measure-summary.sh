#!/bin/bash
# make measure の最後に、今回の集計を、直前のベンチとの差つきで表示する。全体は log/ のファイルにある
# 使い方: tools/measure-summary.sh <LOG_DIR> <bench>
set -u
LOG=$1 BENCH=$2
ALP_N=15 SLOW_N=10 CPU_N=10

# 直前のベンチ (make measure を叩いた 1 つ前)。なければ差は "-" になる
PB=$(ls "$LOG"/*-commit.txt 2>/dev/null | sort | grep -vxF "$LOG/$BENCH-commit.txt" | tail -1)
PB=$(basename "${PB:-none}" -commit.txt)
cur()  { echo "$LOG/$BENCH-$1"; }
prev() { if [ -f "$LOG/$PB-$1" ]; then echo "$LOG/$PB-$1"; else echo /dev/null; fi; }
HP=$([ -f "$LOG/$PB-commit.txt" ] && echo 1 || echo 0)

# CPU プロファイルから、main. の関数の cum (秒) と cum% を取り出す
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cpu_main() {
  if [ -f "$1" ] && command -v go >/dev/null; then
    go tool pprof -symbolize=none -top -cum -unit=s -nodecount=300 "$1" 2>/dev/null | awk '$6 ~ /^main\./ {sub(/s$/, "", $4); print $4 "\t" $5 "\t" $6}'
  fi
}
cpu_total() {
  if [ -f "$1" ] && command -v go >/dev/null; then
    go tool pprof -symbolize=none -top -unit=s -nodecount=1 "$1" 2>/dev/null | sed -n 's/.*Total samples = \([0-9.]*\)s.*/\1/p'
  fi
}
cpu_main "$(cur cpu.pprof)" > "$TMP/cur.cpu"; cpu_main "$(prev cpu.pprof)" > "$TMP/prev.cpu"

# 見出し: リクエスト数、alp の合計、5xx、CPU 時間の合計
total() { awk -F'\t' -v c="$2" '{s += $c} END {print s + 0}' "$1"; }
show() {  # 名前 今回 直前 書式
  if [ "$HP" = 1 ] && [ -n "$3" ]; then awk -v n="$1" -v c="$2" -v p="$3" -v f="$4" 'BEGIN {printf "   %s " f " (%+" substr(f, 2) ")", n, c, c - p}'
  else awk -v n="$1" -v c="$2" -v f="$4" 'BEGIN {printf "   %s " f, n, c}'; fi
}
echo "== bench $BENCH (commit $(cat "$(cur commit.txt)"))$([ "$HP" = 1 ] && echo "  直前 $PB (commit $(cat "$(prev commit.txt)"))")"
show requests "$(total "$(cur alp.tsv)" 1)" "$([ "$HP" = 1 ] && total "$(prev alp.tsv)" 1)" '%d'
show 5xx "$(total "$(cur alp.tsv)" 4)" "$([ "$HP" = 1 ] && total "$(prev alp.tsv)" 4)" '%d'
show 'alp sum' "$(total "$(cur alp.tsv)" 7)" "$([ "$HP" = 1 ] && total "$(prev alp.tsv)" 7)" '%.1fs'
C=$(cpu_total "$(cur cpu.pprof)"); P=$(cpu_total "$(prev cpu.pprof)")
if [ -n "$C" ]; then show cpu "$C" "$P" '%.1fs'; fi
echo

# 差の書式: 直前のベンチがなければ出さない。直前になかった行は "new"
# (awk は s[k] と書いただけで k を作るので、先に k in s を見る)
D='function d(arr, k, c, f) { if (!hp) return ""; if (!(k in arr)) return sprintf("(%9s)", "new"); return sprintf("(" f ")", c - arr[k]) }
   function h() { return hp ? sprintf("%11s", "") : "" }'

DIFF=$([ "$HP" = 1 ] && echo "。括弧は直前との差")
echo "== alp (合計の大きい順に $ALP_N 行${DIFF})"
awk -F'\t' -v P="$(prev alp.tsv)" -v hp="$HP" -v N="$ALP_N" "$D"'
  BEGIN {printf "%6s %5s  %9s %s  %7s %s  %-6s %s\n", "count", "5xx", "sum", h(), "avg", h(), "method", "uri"}
  FILENAME == P {s[$5" "$6] = $7; a[$5" "$6] = $8; next}
  ++n > N {exit}
  {k = $5" "$6; printf "%6d %5d  %9.2f %s  %7.3f %s  %-6s %s\n", $1, $4, $7, d(s, k, $7, "%+9.2f"), $8, d(a, k, $8, "%+9.3f"), $5, $6}
' "$(prev alp.tsv)" "$(cur alp.tsv)"

echo "== slow query (合計の大きい順に $SLOW_N 件${DIFF}。rows/q は 1 回あたりに読んだ行数)"
awk -F'\t' -v P="$(prev slow.tsv)" -v hp="$HP" -v N="$SLOW_N" "$D"'
  BEGIN {printf "%6s  %9s %s  %7s %s  %8s  %s\n", "count", "sum", h(), "avg", h(), "rows/q", "query"}
  FILENAME == P {s[$1] = $3; a[$1] = $4; next}
  ++n > N {exit}
  {printf "%6d  %9.2f %s  %7.4f %s  %8.0f  %s\n", $2, $3, d(s, $1, $3, "%+9.2f"), $4, d(a, $1, $4, "%+9.4f"), ($2 ? $5 / $2 : 0), substr($1, 1, 100)}
' "$(prev slow.tsv)" "$(cur slow.tsv)"

if [ -s "$TMP/cur.cpu" ]; then
  [ -s "$TMP/prev.cpu" ] && CHP=1 || CHP=0
  echo "== cpu (main. の関数、cum の大きい順に $CPU_N 個$([ "$CHP" = 1 ] && echo "。括弧は直前との差")。単位は CPU 秒)"
  awk -F'\t' -v P="$TMP/prev.cpu" -v hp="$CHP" -v N="$CPU_N" "$D"'
    BEGIN {printf "%8s %s  %7s  %s\n", "cum", h(), "cum%", "function"}
    FILENAME == P {s[$3] = $1; next}
    ++n > N {exit}
    {printf "%8.2f %s  %7s  %s\n", $1, d(s, $3, $1, "%+9.2f"), $2, $3}
  ' "$TMP/prev.cpu" "$TMP/cur.cpu"
fi
