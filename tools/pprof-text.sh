#!/bin/bash
# log/<bench>/cpu.pprof を、AI が読めるテキストにする。make measure が手元のリポジトリのルートで呼ぶ
# 使い方: tools/pprof-text.sh <LOG_DIR> <bench> <REPO>
set -eu
LOG=$1 BENCH=$2 REPO=$3
CUR=$LOG/$BENCH/cpu.pprof
# 直前のベンチ (CPU プロファイルがあるもののうち、今回の 1 つ前)
PREV=$(ls "$LOG"/*/cpu.pprof | sort | grep -vxF "$CUR" | tail -1 || true)
PB=$(basename "$(dirname "${PREV:-none/none}")")
# ソースはサーバのパス (REPO の下) で記録されているので、手元のリポジトリ (.) に読み替える
PPROF="go tool pprof -symbolize=none -trim_path=$REPO -source_path=."
LIST_N=3

commit() { cat "$LOG/$1/commit.txt" 2>/dev/null || echo '?'; }
reqs()   { awk -F'\t' '{s += $1} END {print s + 0}' "$LOG/$1/alp.tsv" 2>/dev/null || echo '?'; }

echo "# bench $BENCH  commit $(commit "$BENCH")  requests $(reqs "$BENCH") (alp の回数の合計)"
if [ -n "$PREV" ]; then echo "# prev  $PB  commit $(commit "$PB")  requests $(reqs "$PB")"; fi
echo "# Duration は make deploy / make prep から make measure までの時間で、ベンチの長さではない。負荷のない時間はサンプルが 0 なので、中身には混ざらない"

echo; echo '## top (flat): その関数自身が使った CPU 時間'
$PPROF -top -nodecount=30 "$CUR"

echo; echo '## top (cum): 呼び出し先も含めた CPU 時間'
$PPROF -top -cum -nodecount=30 "$CUR"

echo; echo "## diff (vs $PB): 直前のベンチからの増減。マイナスは減った。リクエスト数が増えると全体に増える"
if [ -n "$PREV" ]; then $PPROF -top -nodecount=30 -diff_base="$PREV" "$CUR"; else echo '(直前のベンチがない)'; fi

echo; echo "## list: main. の関数のうち、cum の上位 $LIST_N 個のソース (行ごとの CPU 時間)"
for f in $($PPROF -top -cum -nodecount=200 "$CUR" | awk '$6 ~ /^main\./ && $6 !~ /^main\.main(\.|$)/ {print $6}' | head -$LIST_N); do
  $PPROF -list "^$(printf '%s' "$f" | sed 's/[][()*.+?^$|{}\\]/\\&/g')\$" "$CUR"
done
