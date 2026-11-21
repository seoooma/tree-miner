#!/bin/bash
# Linux 用の Godot 本体を ~/godot/godot に入れる（CI と同じ置き場所・同じバージョン）。
# 入っていれば何もしない。--web-templates を付けると Web 書き出し用テンプレートも入れる。
# バージョンは .github/workflows/web.yml の GODOT_VERSION に合わせる。
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
version="${GODOT_VERSION:-$(sed -n 's/^ *GODOT_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' "$repo/.github/workflows/web.yml" | head -1)}"
version="${version:-4.3}"
dir="$HOME/godot"
bin="$dir/godot"
base="https://github.com/godotengine/godot/releases/download/${version}-stable"

log() { echo "[install_godot] $*" >&2; }

if [ -x "$bin" ] && "$bin" --headless --version 2>/dev/null | grep -q "^${version}\.stable"; then
  log "Godot ${version} は入っています ($bin)"
else
  log "Godot ${version} をダウンロードします"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 4 -o "$tmp/godot.zip" "$base/Godot_v${version}-stable_linux.x86_64.zip"
  unzip -q "$tmp/godot.zip" -d "$tmp"
  mkdir -p "$dir"
  mv -f "$tmp/Godot_v${version}-stable_linux.x86_64" "$bin"
  chmod +x "$bin"
  log "入れました: $("$bin" --headless --version 2>/dev/null)"
fi

if [ "${1:-}" = "--web-templates" ]; then
  dest="$HOME/.local/share/godot/export_templates/${version}.stable"
  if [ -f "$dest/web_nothreads_release.zip" ]; then
    log "Web 書き出しテンプレートは入っています"
  else
    log "Web 書き出しテンプレートをダウンロードします（約1GB）"
    tmp2="$(mktemp -d)"
    curl -fsSL --retry 4 -o "$tmp2/templates.tpz" "$base/Godot_v${version}-stable_export_templates.tpz"
    mkdir -p "$dest"
    unzip -j -q -o "$tmp2/templates.tpz" templates/web_nothreads_release.zip templates/web_nothreads_debug.zip templates/version.txt -d "$dest"
    rm -rf "$tmp2"
  fi
fi
