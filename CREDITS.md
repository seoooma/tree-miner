# クレジット

このゲームで使っている外部素材と、その出典・ライセンスです。

## 3D モデル・効果音（Kenney / CC0）

[Kenney](https://kenney.nl) の Starter Kit から取り出しています。素材（3D モデル・テクスチャ・効果音）は
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)（パブリックドメイン相当）です。
各キットの README に「Assets included in this package ... are CC0 licensed」と明記されています。

| 素材 | 出典 | 使っている場所 |
|---|---|---|
| `assets/kenney/platformer/character.glb` | [Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer) | プレイヤー・伐採員 |
| `assets/kenney/platformer/coin.glb` | 同上 | 売却時に飛び出すコイン |
| `assets/kenney/platformer/grass-small.glb` | 同上 | 地面の草 |
| `assets/audio/coin.ogg`, `land.ogg`, `walking.ogg` | 同上 | 売却音・丸太を置く音・足音 |
| `assets/kenney/racing/vehicle-truck-*.glb` | [Starter-Kit-Racing](https://github.com/KenneyNL/Starter-Kit-Racing) | 伐採機・運搬車 |
| `assets/audio/engine.ogg`, `impact.ogg` | 同上 | エンジン音・乗車音 |
| `assets/audio/placement-a/b/c.ogg`, `toggle.ogg` | [Starter-Kit-City-Builder](https://github.com/KenneyNL/Starter-Kit-City-Builder) | 拾う・開放・購入・ボタン・給油の音 |

## 自作素材

| 素材 | 作り方 |
|---|---|
| `assets/audio/bgm_forest.ogg`（BGM） | `tools/make_bgm.py` で合成（numpy + ffmpeg）。このリポジトリのライセンスに従う |
| `assets/audio/chop.ogg`, `tree_fall.ogg` | 同上 |
| 木・施設・丸太・看板などのモデル | コード内でプリミティブを組み合わせて生成（`scripts/world/`） |
| `assets/textures/*.png`（草地・作業場・道・樹皮・木目・金属のテクスチャと法線マップ） | `tools/make_textures.py` でノイズから生成（numpy + Pillow） |
| `assets/ui/*.png`（アイコン・ボタン・カード・見出しの下地） | 同上 |
| 作業着の配色（キャラクターの塗り替え） | `scripts/world/mats.gd` のシェーダーで Kenney のモデルの色を置き換え |

Poly Haven / ambientCG / Quaternius の素材は、この開発環境からダウンロードできなかったため使っていません（すべて手続き生成で代替）。

## フォント

| 素材 | ライセンス |
|---|---|
| `fonts/DelaGothicOne-subset.ttf`（[Dela Gothic One](https://fonts.google.com/specimen/Dela+Gothic+One) のサブセット。見出し・数字） | [SIL Open Font License 1.1](fonts/OFL-DelaGothicOne.txt) |
| `fonts/MPLUSRounded1c-Black-subset.ttf`（[M PLUS Rounded 1c](https://fonts.google.com/specimen/M+PLUS+Rounded+1c) Black のサブセット。本文） | [SIL Open Font License 1.1](fonts/OFL-MPLUSRounded1c.txt) |

フォントは [google/fonts](https://github.com/google/fonts) から取得し、`tools/subset_font.py` でゲームに出てくる文字だけに絞っています。

## エンジン

[Godot Engine](https://godotengine.org)（MIT License）
