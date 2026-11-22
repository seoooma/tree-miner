#!/bin/bash
# 重さの確認: 後半の状態（全エリア開放・施設すべて）で 30 秒動かし、描画の統計を出す。セーブデータは書き換えない。
set -euo pipefail
cd "$(dirname "$0")/../.."
export DISPLAY="${DISPLAY:-:98}"
if ! [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]; then
  nohup Xvfb "$DISPLAY" -screen 0 1600x1600x24 -nolisten tcp >/dev/null 2>&1 &
  for _ in $(seq 1 50); do [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ] && break; sleep 0.1; done
fi
exec "${GODOT_BIN:-$HOME/godot/godot}" --audio-driver Dummy --resolution "${1:-720x1280}" --path . res://tools/cloud/probe.tscn 2>&1 | grep -E "^t=|^\{|SCRIPT"
