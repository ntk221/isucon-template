#!/bin/bash
# アクセスログから、ベンチの時間帯 (開始と終了の unix 時刻) を出す。make measure が nginx の台で呼ぶ
# 開始: 最後の initialize のリクエストが来た時刻。ログの時刻はリクエストの終わりなので reqtime を引く (initialize がなければ最初の行)
# 終了: そこから続くリクエストが 10 秒以上途切れる直前。ベンチの後のブラウザのアクセスなどを入れないため
# 使い方: tools/bench-window.sh /var/log/nginx/access.log
set -eu
GAP=10

read -r off_s off_e base < <(sudo cat "$1" | awk -F'\t' -v gap="$GAP" '
  # 06/Oct/2026:05:47:33 +0000 を、比べられる秒にする (月をまたいでも順番が崩れないように、月は 31 日で数える)
  function sec(t,   a) {
    split(t, a, /[\/: ]/)
    return ((index("JanFebMarAprMayJunJulAugSepOctNovDec", a[2]) + 2) / 3 * 31 + a[1]) * 86400 + a[4] * 3600 + a[5] * 60 + a[6]
  }
  {
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^time:/) t = substr($i, 6)
      else if ($i ~ /^uri:/) u = substr($i, 5)
      else if ($i ~ /^reqtime:/) rt = substr($i, 9)
    }
    k[NR] = sec(t); tt[NR] = t
    if (u ~ /\/initialize/) { si = NR; srt = rt }
  }
  END {
    if (NR == 0) exit
    if (!si) { si = 1; srt = 0 }
    e = k[si]
    for (i = si + 1; i <= NR; i++) { if (k[i] - e > gap) break; e = k[i] }
    printf "%d %d %s\n", -int(srt) - 1, e - k[si], tt[si]
  }')
[ -n "${base:-}" ] || exit 0
b=$(date -d "$(echo "$base" | sed -E 's#^([0-9]+)/([A-Za-z]+)/([0-9]+):#\1 \2 \3 #')" +%s)
echo "$((b + off_s)) $((b + off_e))"
