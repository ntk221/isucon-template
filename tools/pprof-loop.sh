#!/bin/bash
# CPU プロファイルを 10 秒ずつ取り続け、書き終えた時刻の名前で DIR に置く。isu-pprof.service が動かす
# アプリが net/http/pprof を localhost:6060 で開けている前提。空にするのは make deploy / make prep、合算するのは make measure
DIR=/tmp/pprof
URL='http://localhost:6060/debug/pprof/profile?seconds=10'

mkdir -p "$DIR"
while true; do
  # 失敗したら 1 秒待つ (アプリの再起動中、pprof の口がない、手で取ったプロファイルと重なった)。待たないと空回りする
  curl -sf -o "$DIR/.tmp" "$URL" && mv "$DIR/.tmp" "$DIR/$(date +%s).pprof" || sleep 1
done
