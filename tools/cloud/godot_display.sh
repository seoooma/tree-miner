#!/bin/bash
# Godot MCP の GODOT_PATH に渡すラッパー。
# 画面のないクラウド環境では、ゲームの実行（run_project）やエディタ起動に X ディスプレイが要るので、
# DISPLAY が無ければ仮想ディスプレイ Xvfb（:99）を立ち上げてから ~/godot/godot を実行する。
# 描画はソフトウェア（Mesa llvmpipe の OpenGL）なので遅いが、エラー出力の確認には十分。
set -euo pipefail

bin="${GODOT_BIN:-$HOME/godot/godot}"

needs_display=yes
for a in "$@"; do
  case "$a" in --headless | --version | -h | --help) needs_display= ;; esac
done

if [ -n "$needs_display" ] && [ -z "${DISPLAY:-}" ] && command -v Xvfb >/dev/null; then
  export DISPLAY=:99
  if ! [ -S /tmp/.X11-unix/X99 ]; then
    nohup Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/dev/null 2>&1 &
    for _ in $(seq 1 50); do [ -S /tmp/.X11-unix/X99 ] && break; sleep 0.1; done
  fi
fi

# 音声デバイスも無いので、ALSA のエラーで出力が埋まらないようダミーにする
if [ -n "$needs_display" ]; then
  set -- --audio-driver Dummy "$@"
fi

exec "$bin" "$@"
