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

## フォント

| 素材 | ライセンス |
|---|---|
| `fonts/NotoSansJP-Bold-subset.ttf`（Noto Sans JP のサブセット） | [SIL Open Font License 1.1](fonts/OFL.txt) |

## エンジン

[Godot Engine](https://godotengine.org)（MIT License）
