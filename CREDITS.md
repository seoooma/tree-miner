# クレジット

このゲームで使っている外部素材と、その出典・ライセンスです。

## 3D モデル・効果音（Kenney / CC0）

[Kenney](https://kenney.nl) の Starter Kit から取り出しています。素材（3D モデル・テクスチャ・効果音）は
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)（パブリックドメイン相当）です。
各キットの README に「Assets included in this package ... are CC0 licensed」と明記されています。

| 素材 | 出典 | 使っている場所 |
|---|---|---|
| `assets/kenney/platformer/coin.glb` | 同上 | 売却時に飛び出すコイン |
| `assets/audio/coin.ogg`, `land.ogg`, `walking.ogg` | 同上 | 売却音・丸太を置く音・足音 |
| `assets/audio/engine.ogg`, `impact.ogg` | [Starter-Kit-Racing](https://github.com/KenneyNL/Starter-Kit-Racing) | エンジン音・乗車音 |
| `assets/audio/placement-a/b/c.ogg`, `toggle.ogg` | [Starter-Kit-City-Builder](https://github.com/KenneyNL/Starter-Kit-City-Builder) | 拾う・開放・購入・ボタン・給油の音 |

### OpenGameArt で Kenney が配布しているキット（CC0）

kenney.nl はこの開発環境からの自動ダウンロードを受け付けないため、Kenney 本人のアカウントが
[OpenGameArt](https://opengameart.org/users/kenney) で配布している同じキットから取得しています。各 zip の License.txt に CC0 と明記されています。

| 素材 | 出典 | 使っている場所 |
|---|---|---|
| `assets/kenney/car/tractor.glb`, `tractor-shovel.glb` | [Car Kit 3.1](https://opengameart.org/content/car-kit) | 伐採機（Mk1 / Mk2・Mk3。ショベルは隠してノコギリを付けている） |
| `assets/kenney/car/truck.glb`, `truck-flat.glb`, `delivery-flat.glb` | 同上 | 運搬車（Mk1 / Mk2 / Mk3）・出荷場に停めたトラック |
| `assets/kenney/survival/tool-axe.glb` | [Survival Kit](https://opengameart.org/content/survival-kit) | 人物が持つ斧・強化画面の斧 |
| `assets/kenney/nature/*.glb` | [Nature Kit 2.1](https://opengameart.org/content/nature-kit) | 木（種類ごとに色を塗り替え）・切り株・草・花・岩など。ライセンス文は `assets/kenney/nature/License.txt` |

## 人物モデル（Quaternius / CC0）

[Quaternius](https://quaternius.com) の [Ultimate Animated Character Pack](https://quaternius.com/packs/ultimatedanimatedcharacter.html)（2019年11月版）から
作業員の男女 2 体を使っています。ライセンスは [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)（配布ページに明記）。
配布元の Google ドライブにはこの開発環境から接続できないため、同じパックの glTF をそのまま収録している GitHub 上の公開リポジトリから取得し、
glTF → GLB に変換だけしています（形状・アニメーションは無加工）。服の色はゲーム内で作業着の配色に塗り替えています（`scripts/world/character_rig.gd`）。

| 素材 | 元のファイル | 使っている場所 |
|---|---|---|
| `assets/quaternius/worker_male.glb` | `Worker_Male.gltf` | プレイヤー・伐採員（偶数番目） |
| `assets/quaternius/worker_female.glb` | `Worker_Female.gltf` | 伐採員（奇数番目） |

## 自作素材

| 素材 | 作り方 |
|---|---|
| `assets/audio/bgm_forest.ogg`（BGM） | `tools/make_bgm.py` で合成（numpy + ffmpeg）。このリポジトリのライセンスに従う |
| `assets/audio/chop.ogg`, `tree_fall.ogg` | 同上 |
| 施設・丸太・看板などのモデル | コード内でプリミティブを組み合わせて生成（`scripts/world/`） |
| `assets/textures/leaf_noise.png`（地面のまだら・水面のノイズ）など | `tools/make_textures.py` でノイズから生成（numpy + Pillow） |
| `assets/ui/*.png`（アイコン・ボタン・カード・見出しの下地） | 同上 |
| パーティクル演出（木くず・葉・土ぼこり・おがくず・火花・煙・水しぶき・きらめき）のテクスチャとメッシュ | `scripts/vfx.gd` がゲーム起動時にコードで生成（外部素材なし） |
| 木・草の風の揺れ、川の水面、地面のまだら | `scripts/world/mats.gd`・`scripts/world/log_line.gd` のシェーダー |
| 作業着の配色（キャラクターの塗り替え） | `scripts/world/character_rig.gd` と `scripts/world/mats.gd` で Quaternius のモデルの色を置き換え |


## フォント

| 素材 | ライセンス |
|---|---|
| `fonts/DelaGothicOne-subset.ttf`（[Dela Gothic One](https://fonts.google.com/specimen/Dela+Gothic+One) のサブセット。見出し・数字） | [SIL Open Font License 1.1](fonts/OFL-DelaGothicOne.txt) |
| `fonts/MPLUSRounded1c-Black-subset.ttf`（[M PLUS Rounded 1c](https://fonts.google.com/specimen/M+PLUS+Rounded+1c) Black のサブセット。本文） | [SIL Open Font License 1.1](fonts/OFL-MPLUSRounded1c.txt) |

フォントは [google/fonts](https://github.com/google/fonts) から取得し、`tools/subset_font.py` でゲームに出てくる文字だけに絞っています。

## エンジン

[Godot Engine](https://godotengine.org)（MIT License）
