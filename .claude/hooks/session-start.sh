#!/bin/bash
# クラウドセッションの開始時に Godot（CI と同じバージョン）を入れ、
# 初回だけプロジェクトをインポートしておく。ローカルでは何もしない。
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

tools/cloud/install_godot.sh

# インポート済みのキャッシュ（.godot/）が無ければ作る。スモークテストや MCP の前提になる
if [ ! -d .godot/imported ]; then
  "$HOME/godot/godot" --headless --path . --import >/dev/null 2>&1 || true
fi

# MCP サーバーを npx が毎回取りに行かないよう先に取得しておく
npm exec -y --package=@coding-solo/godot-mcp@0.1.1 -- true >/dev/null 2>&1 || true

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export PATH="$HOME/godot:$PATH"' >> "$CLAUDE_ENV_FILE"
fi
