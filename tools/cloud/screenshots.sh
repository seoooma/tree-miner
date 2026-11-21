#!/bin/bash
# 見た目の確認用スクリーンショットを撮る（home / chop / felled / saw / sell / river）。
# 使い方: tools/cloud/screenshots.sh <出力フォルダ（絶対パス）> [幅x高さ] [撮る場面（例: chop,felled）]
# 仮想ディスプレイ上で実際に描画する（CPU の OpenGL なので 1 分ほどかかる）。
set -euo pipefail
out="${1:?出力フォルダを指定してください}"
res="${2:-720x1280}"
cd "$(dirname "$0")/../.."
mkdir -p "$out"
export DISPLAY="${DISPLAY:-:98}"
if ! [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]; then
  nohup Xvfb "$DISPLAY" -screen 0 1600x1600x24 -nolisten tcp >/dev/null 2>&1 &
  for _ in $(seq 1 50); do [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ] && break; sleep 0.1; done
fi
exec "${GODOT_BIN:-$HOME/godot/godot}" --audio-driver Dummy --resolution "$res" --path . res://tools/cloud/shots.tscn -- "$out" "${3:-}"
