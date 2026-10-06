#!/bin/bash
# CPU プロファイルを 10 秒ずつ取り続け、書き終えた時刻の名前で DIR に置く。isu-pprof.service が動かす
# 起動するたびに DIR を空にする。make deploy / make prep は isu-pprof を起動し直して空にし、make measure が DIR を合算する
# アプリが net/http/pprof を localhost:6060 で開けていなければ、取れずに待つだけ (止めるときは main.go から口を外す)
DIR=/tmp/pprof
URL='http://localhost:6060/debug/pprof/profile?seconds=10'

rm -rf "${DIR:?}" && mkdir -p "$DIR"
while true; do
  # 失敗したら 10 秒待つ (pprof の口がない、アプリの再起動中、手で取ったプロファイルと重なった)。待たないと空回りする
  curl -sf -o "$DIR/.tmp" "$URL" && mv "$DIR/.tmp" "$DIR/$(date +%s).pprof" || sleep 10
done
