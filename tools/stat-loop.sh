#!/bin/bash
# 1 秒ごとに、コアごとの CPU とプロセスごとの CPU を記録し続ける (top を取り続けるのと同じ)。isu-stat.service が動かす
# 起動するたびに DIR を空にする。make deploy / make prep は isu-stat を起動し直して空にし、
# make measure がベンチの時間帯だけを切り出してまとめる
# 出力は 1 行 1 件:
#   <unix 時刻> cpu  <コア> <busy%> <iowait%> <steal%>
#   <unix 時刻> proc <名前> <%CPU。100 = 1 コア。同じ名前は足す。終わった子プロセスの分は親に入る>
DIR=/tmp/isu-stat

rm -rf "${DIR:?}" && mkdir -p "$DIR"
while true; do
  echo "@ $(date +%s.%N)"
  grep '^cpu[0-9]' /proc/stat
  cat /proc/[0-9]*/stat 2>/dev/null
  sleep 1
done | awk -v hz="$(getconf CLK_TCK)" '
  # 1 秒分を読み終えたら、前の 1 秒との差を書き出す
  function flush(   k, d, dt, n) {
    if (pt == "") return
    dt = t - pt
    for (k in tot) if (k in ptot && tot[k] > ptot[k]) {
      d = tot[k] - ptot[k]
      printf "%d cpu %s %.1f %.1f %.1f\n", t, k, (d - (idl[k] - pidl[k]) - (iow[k] - piow[k])) * 100 / d, (iow[k] - piow[k]) * 100 / d, (stl[k] - pstl[k]) * 100 / d
    }
    split("", sum)
    for (k in tick) if (k in ptick && tick[k] > ptick[k]) sum[name[k]] += (tick[k] - ptick[k]) * 100 / hz / dt
    for (n in sum) if (sum[n] >= 0.1) printf "%d proc %s %.1f\n", t, n, sum[n]
    fflush()
  }
  function shift_(   k) {
    split("", ptot); split("", pidl); split("", piow); split("", pstl); split("", ptick)
    for (k in tot) { ptot[k] = tot[k]; pidl[k] = idl[k]; piow[k] = iow[k]; pstl[k] = stl[k] }
    for (k in tick) ptick[k] = tick[k]
    split("", tot); split("", idl); split("", iow); split("", stl); split("", tick)
    pt = t
  }
  $1 == "@" { flush(); if (t != "") shift_(); t = $2; next }
  $1 ~ /^cpu[0-9]/ { k = $1; tot[k] = $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9; idl[k] = $5; iow[k] = $6; stl[k] = $9; next }
  {
    # /proc/<pid>/stat: pid (名前) 状態 ... 14:utime 15:stime 16:cutime 17:cstime ... 22:starttime
    l = index($0, " ("); r = l; while ((i = index(substr($0, r + 1), ")")) > 0) r += i
    comm = substr($0, l + 2, r - l - 2)
    split(substr($0, r + 2), f, " ")
    k = $1 ":" f[20]
    tick[k] = f[12] + f[13] + f[14] + f[15]; name[k] = comm
  }
' >> "$DIR/stat.txt"
