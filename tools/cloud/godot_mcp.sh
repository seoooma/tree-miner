#!/bin/bash
# .mcp.json から起動する Godot MCP サーバー（@coding-solo/godot-mcp）。
# GODOT_PATH が設定済みならそれを使い（Mac など）、無ければクラウド用に
# Godot を入れて（入っていれば何もしない）仮想ディスプレイ付きラッパーを渡す。
# 標準出力は MCP の通信に使うので、ここでは何も出力しない。
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${GODOT_PATH:-}" ]; then
  "$here/install_godot.sh" >&2
  export GODOT_PATH="$here/godot_display.sh"
fi
exec npx -y @coding-solo/godot-mcp@0.1.1
