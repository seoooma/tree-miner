# クレジット

このゲームで使っている外部素材と、その出典・ライセンスです。

## 3D モデル・効果音（Kenney / CC0）

[Kenney](https://kenney.nl) の Starter Kit から取り出しています。素材（3D モデル・テクスチャ・効果音）は
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)（パブリックドメイン相当）です。
各キットの README に「Assets included in this package ... are CC0 licensed」と明記されています。

| 素材 | 出典 | 使っている場所 |
|---|---|---|
| `assets/kenney/platformer/coin.glb` | 同上 | 売却時に飛び出すコイン |
| `assets/kenney/platformer/grass-small.glb` | 同上 | 地面の草 |
| `assets/audio/coin.ogg`, `land.ogg`, `walking.ogg` | 同上 | 売却音・丸太を置く音・足音 |
| `assets/kenney/racing/vehicle-truck-*.glb` | [Starter-Kit-Racing](https://github.com/KenneyNL/Starter-Kit-Racing) | 伐採機・運搬車 |
| `assets/audio/engine.ogg`, `impact.ogg` | 同上 | エンジン音・乗車音 |
| `assets/audio/placement-a/b/c.ogg`, `toggle.ogg` | [Starter-Kit-City-Builder](https://github.com/KenneyNL/Starter-Kit-City-Builder) | 拾う・開放・購入・ボタン・給油の音 |

## 人物モデル（Quaternius / CC0）

[Quaternius](https://quaternius.com) の [Ultimate Animated Character Pack](https://quaternius.com/packs/ultimatedanimatedcharacter.html)（2019年11月版）から
作業員の男女 2 体を使っています。ライセンスは [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)（配布ページに明記）。
配布元の Google ドライブにはこの開発環境から接続できないため、同じパックの glTF をそのまま収録している GitHub 上の公開リポジトリから取得し、
glTF → GLB に変換だけしています（形状・アニメーションは無加工）。服の色はゲーム内で作業着の配色に塗り替えています（`scripts/world/character_rig.gd`）。

| 素材 | 元のファイル | 使っている場所 |
|---|---|---|
| `assets/quaternius/worker_male.glb` | `Worker_Male.gltf` | プレイヤー・伐採員（偶数番目） |
| `assets/quaternius/worker_female.glb` | `Worker_Female.gltf` | 伐採員（奇数番目） |

## テクスチャ（Poly Haven / CC0）

[Poly Haven](https://polyhaven.com) のテクスチャです。ライセンスは [CC0 1.0](https://polyhaven.com/license)。
`tools/import_polyhaven.py` で 1k の JPG を取得して 512px に縮小しています（樹皮・板材・波板は色をほぼ抜いて明るさの模様にし、色はコード側で付けています）。

| 素材 | 元のテクスチャ（作者） | 使っている場所 |
|---|---|---|
| `assets/textures/grass_*.png` | [Leafy Grass](https://polyhaven.com/a/leafy_grass)（Charlotte Baglioni） | 森の草地 |
| `assets/textures/forest_*.png` | [Forest Ground 01](https://polyhaven.com/a/forrest_ground_01)（Rob Tuytel） | 草地に混ぜる林床のパッチ |
| `assets/textures/yard_*.png` | [Rocky Trail](https://polyhaven.com/a/rocky_trail)（Amal Kumar） | 拠点の作業場 |
| `assets/textures/road_*.png` | [Dirt](https://polyhaven.com/a/dirt)（Charlotte Baglioni） | 土の道 |
| `assets/textures/bark_*.png` | [Bark Brown 02](https://polyhaven.com/a/bark_brown_02)（Rob Tuytel） | 木の幹 |
| `assets/textures/wood_*.png` | [Weathered Brown Planks](https://polyhaven.com/a/weathered_brown_planks)（Dimitrios Savva, Rico Cilliers） | 建物・柵・木箱などの板材 |
| `assets/textures/roof_albedo.png` | [Corrugated Iron](https://polyhaven.com/a/corrugated_iron)（Dimitrios Savva, Jenelle van Heerden） | 製材所などの波板の屋根 |

## 自作素材

| 素材 | 作り方 |
|---|---|
| `assets/audio/bgm_forest.ogg`（BGM） | `tools/make_bgm.py` で合成（numpy + ffmpeg）。このリポジトリのライセンスに従う |
| `assets/audio/chop.ogg`, `tree_fall.ogg` | 同上 |
| 木・施設・丸太・看板などのモデル | コード内でプリミティブを組み合わせて生成（`scripts/world/`） |
| `assets/textures/metal_detail.png`, `paint_detail.png`, `leaf_noise.png`（金属・塗装のムラ、葉のノイズ） | `tools/make_textures.py` でノイズから生成（numpy + Pillow） |
| `assets/ui/*.png`（アイコン・ボタン・カード・見出しの下地） | 同上 |
| 作業着の配色（キャラクターの塗り替え） | `scripts/world/character_rig.gd` と `scripts/world/mats.gd` で Quaternius のモデルの色を置き換え |


## フォント

| 素材 | ライセンス |
|---|---|
| `fonts/DelaGothicOne-subset.ttf`（[Dela Gothic One](https://fonts.google.com/specimen/Dela+Gothic+One) のサブセット。見出し・数字） | [SIL Open Font License 1.1](fonts/OFL-DelaGothicOne.txt) |
| `fonts/MPLUSRounded1c-Black-subset.ttf`（[M PLUS Rounded 1c](https://fonts.google.com/specimen/M+PLUS+Rounded+1c) Black のサブセット。本文） | [SIL Open Font License 1.1](fonts/OFL-MPLUSRounded1c.txt) |

フォントは [google/fonts](https://github.com/google/fonts) から取得し、`tools/subset_font.py` でゲームに出てくる文字だけに絞っています。

## エンジン

[Godot Engine](https://godotengine.org)（MIT License）
