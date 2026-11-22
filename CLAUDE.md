# Tree Miner 開発メモ（Claude 向け）

Godot 4.3 製（CI の `.github/workflows/web.yml` の `GODOT_VERSION` が正）。開発はクラウドのセッションで行う。

## クラウドでの Godot

- セッション開始時に `.claude/hooks/session-start.sh` が Godot（Linux 版、CI と同じバージョン）を `~/godot/godot` に入れ、初回は `--import` まで済ませる。入っていれば一瞬で終わる
- 手で入れ直すとき: `tools/cloud/install_godot.sh`（Web 書き出しもするなら `--web-templates`。約1GB）

## テスト

```bash
~/godot/godot --headless --path . --import   # アセットを変えたとき
~/godot/godot --headless --fixed-fps 60 --path . res://tests/smoke_test.tscn 2>&1 | grep -E "ok|FAIL|SMOKE"
```

最後に `SMOKE TEST: PASS` が出れば CI と同じ判定で合格。

## 見た目の確認（スクリーンショット）

```bash
tools/cloud/screenshots.sh /tmp/shots              # home / chop / felled / saw / sell / river を撮る（1 分ほど）
tools/cloud/screenshots.sh /tmp/shots 720x1280 chop,felled   # 場面を絞る
```

仮想ディスプレイ上で実際に描画する（セーブデータは書き換えない）。Web 版と同じ Compatibility レンダラーなので、
グロー・色調補正（Environment の glow / adjustment）は画面が白っぽく色あせる。使わず、光る演出は加算合成のスプライト（`scripts/vfx.gd`）で出す。

## 重さの確認

```bash
tools/cloud/probe.sh   # 後半の状態で 30 秒動かし、描画の呼び出し数・ノード数・施設ごとのメッシュ数を出す
```

Web 版（スマホの WebGL）は `rendering/driver/depth_prepass/enable=false` にしている。ブラウザ越しだと GPU の種類が分からず、
Godot が Android の GPU 向けに深度プリパスを切る判定が効かない。深度プリパスが効いたままだと、3D が描かれず空の色だけの画面がちらつくことがある（2026-11 にスマホで発生）。

## Godot MCP（.mcp.json の `godot`）

`tools/cloud/godot_mcp.sh` が `@coding-solo/godot-mcp` を起動する。画面が無い環境なので、`GODOT_PATH` には
`tools/cloud/godot_display.sh`（DISPLAY が無ければ仮想ディスプレイ Xvfb :99 を立ててから Godot を実行）を渡している。描画は CPU の OpenGL（llvmpipe）。

- 使える: `get_godot_version` / `get_project_info` / `list_projects` / `run_project` → `get_debug_output` → `stop_project`（実際に描画しながらゲームを動かし、GDScript の警告やエラーを取れる。描画が遅いので数十秒待ってから出力を読む）/ `create_scene` / `add_node` / `load_sprite` / `save_scene` / `export_mesh_library`
- 使えない: `get_uid` / `update_project_uids`（Godot 4.4 以上が必要）
- 使わない: `launch_editor`（見えない画面でエディタが立ち上がるだけで、`project.godot` を書き直してしまう）
- `get_debug_output` の `ERROR: '...'` の多くは GDScript の警告（変数名の重複など）で、ゲームは止まらない
