"""地面・樹皮・木材のテクスチャと、UI の画像（アイコン・ボタン・カード）を手続き的に生成する。

外部素材を使わずに質感を出すためのスクリプト。生成物はリポジトリに含めてあるので、
見た目を調整したいときだけ実行し直せばよい。

  pip install numpy pillow
  python tools/make_textures.py

出力:
  assets/textures/*.png  … 金属・塗装のムラ、葉のノイズ（512px 以下、継ぎ目なしでタイル可能）
                           地面・樹皮・板材は tools/import_polyhaven.py で Poly Haven から取り込む
  assets/ui/*.png        … HUD・強化画面のアイコンやボタンの下地
"""
import math
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEX = ROOT / "assets" / "textures"
UI = ROOT / "assets" / "ui"
RNG = np.random.default_rng(20261120)


# ---------------------------------------------------------------- ノイズ

def fbm(size: int, beta: float = 2.0, low_cut: float = 1.0, aniso=(1.0, 1.0)) -> np.ndarray:
    """周波数領域でフィルタしたホワイトノイズ（＝継ぎ目なしでタイルできる fBm）。0..1 に正規化。"""
    white = RNG.standard_normal((size, size))
    fx = np.fft.fftfreq(size)[None, :] * size / aniso[0]
    fy = np.fft.fftfreq(size)[:, None] * size / aniso[1]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = 1.0 / np.power(np.maximum(f, low_cut), beta / 2.0)
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    out -= out.min()
    return out / max(out.max(), 1e-6)


def blobs(size: int, count: int, rmin: float, rmax: float, seed_shift=0) -> tuple[np.ndarray, np.ndarray]:
    """小石: 高さ（丸いこぶ）と、石がある場所のマスク。タイルできるよう端で折り返す。"""
    h = np.zeros((size, size))
    yy, xx = np.mgrid[0:size, 0:size]
    for _ in range(count):
        cx, cy = RNG.uniform(0, size, 2)
        r = RNG.uniform(rmin, rmax)
        sx = RNG.uniform(0.7, 1.3)
        dx = (xx - cx + size / 2) % size - size / 2
        dy = (yy - cy + size / 2) % size - size / 2
        d = np.sqrt((dx * sx) ** 2 + (dy / sx) ** 2) / r
        bump = np.clip(1.0 - d * d, 0.0, 1.0) ** 0.6
        h = np.maximum(h, bump * RNG.uniform(0.6, 1.0))
    return h, (h > 0.05).astype(float)


def normal_map(height: np.ndarray, strength: float) -> np.ndarray:
    """高さから法線マップ（OpenGL 形式, Y+）を作る。"""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    n = np.stack([-dx, dy, np.ones_like(height)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def lerp_colors(t: np.ndarray, stops: list) -> np.ndarray:
    """t (0..1) をカラーストップでグラデーションにする。"""
    pos = np.array([s[0] for s in stops])
    cols = np.array([[int(s[1][i:i + 2], 16) for i in (1, 3, 5)] for s in stops], dtype=float)
    out = np.zeros(t.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(t, pos, cols[:, c])
    return out


def save_rgb(arr: np.ndarray, name: str) -> None:
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").save(TEX / name, optimize=True)


# ---------------------------------------------------------------- 金属・葉
# 地面・樹皮・板材は Poly Haven の写真素材に置き換えた（tools/import_polyhaven.py）

def metal() -> None:
    """塗装された金属の細かい傷とムラ（R=明るさ, G=ラフネス）"""
    s = 256
    brushed = fbm(s, 0.8, 30.0, aniso=(1.0, 0.05))
    blotch = fbm(s, 2.4, 2.0)
    scratches = np.zeros((s, s))
    img = Image.fromarray(np.zeros((s, s), np.uint8))
    d = ImageDraw.Draw(img)
    for _ in range(70):
        x, y = RNG.uniform(0, s, 2)
        a = RNG.uniform(0, math.pi)
        ln = RNG.uniform(6, 30)
        d.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=int(RNG.uniform(90, 200)), width=1)
    scratches = np.array(img) / 255.0
    v = 0.86 + brushed * 0.1 + blotch * 0.08 + scratches * 0.15
    rough = 0.35 + blotch * 0.35 + scratches * 0.25
    out = np.stack([v * 255, rough * 255, v * 255], axis=-1)
    save_rgb(out, "metal_detail.png")
    # 塗装面のムラ（グレースケール。albedo に掛ける）
    p = np.clip(0.9 + blotch * 0.08 + brushed * 0.04 + scratches * 0.06, 0, 1)
    save_rgb(np.stack([p * 255] * 3, axis=-1), "paint_detail.png")


def leaf_noise() -> None:
    s = 256
    n = fbm(s, 1.6, 6.0) * 0.6 + fbm(s, 0.6, 30.0) * 0.4
    save_rgb(np.stack([n * 255] * 3, axis=-1), "leaf_noise.png")


# ---------------------------------------------------------------- UI

def _ss(size, scale=4):
    """スーパーサンプリング用の大きいキャンバス"""
    return Image.new("RGBA", (size[0] * scale, size[1] * scale), (0, 0, 0, 0)), scale


def _down(img: Image.Image, size) -> Image.Image:
    return img.resize(size, Image.LANCZOS)


def _rounded(draw, box, r, fill, outline=None, width=0):
    draw.rounded_rectangle(box, r, fill=fill, outline=outline, width=width)


def gradient_box(name, size, top, bottom, border, radius, bottom_edge=None, border_w=3, scratches=False, inner_hi=True):
    """縦グラデーション＋縁取り＋下辺の濃い帯（立体感）の 9-slice 用画像"""
    img, k = _ss(size)
    w, h = img.size
    t = np.linspace(0, 1, h)[:, None]
    c0 = np.array([int(top[i:i + 2], 16) for i in (1, 3, 5)])
    c1 = np.array([int(bottom[i:i + 2], 16) for i in (1, 3, 5)])
    grad = (c0 * (1 - t) + c1 * t)[:, None, :].repeat(w, 1)
    grad = grad[:, :, :] * np.ones((h, w, 1))
    if scratches:
        n = fbm(256, 1.0, 20.0, aniso=(1.0, 0.1))
        n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h))) / 255.0
        grad *= (0.9 + 0.14 * n)[..., None]
        sc = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(sc)
        for _ in range(120):
            x, y = RNG.uniform(0, w), RNG.uniform(0, h)
            a = RNG.uniform(-0.4, 0.4)
            ln = RNG.uniform(10, 60) * k
            d.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=int(RNG.uniform(60, 160)), width=k)
        grad = grad * (1 - np.array(sc)[..., None] / 255.0 * 0.25)
    fill = Image.fromarray(np.clip(grad, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, w - 1, h - 1), radius * k, fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(fill, (0, 0), mask)
    d = ImageDraw.Draw(out)
    if bottom_edge:
        # 下辺の濃い帯
        edge = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ed = ImageDraw.Draw(edge)
        ed.rounded_rectangle((0, 0, w - 1, h - 1), radius * k, fill=bottom_edge)
        em = Image.new("L", (w, h), 0)
        ImageDraw.Draw(em).rectangle((0, h - 7 * k, w, h), fill=255)
        em = Image.composite(em, Image.new("L", (w, h), 0), mask)
        out.paste(edge, (0, 0), em)
    if inner_hi:
        d.rounded_rectangle((border_w * k + k, border_w * k + k, w - border_w * k - k - 1, h // 2), max(1, (radius - 2) * k),
                            outline=(255, 255, 255, 70), width=2 * k)
    if border:
        d.rounded_rectangle((0, 0, w - 1, h - 1), radius * k, outline=border, width=border_w * k)
    _down(out, size).save(UI / name)


def icon_canvas(px=128):
    return _ss((px, px))


def save_icon(img, name, px=128):
    _down(img, (px, px)).save(UI / name)


def icon_gear():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    c = 64 * k
    pts = []
    teeth = 8
    for i in range(teeth * 4):
        a = i / (teeth * 4) * math.tau
        r = (54 if (i % 4) in (1, 2) else 40) * k
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pts, fill=(255, 255, 255, 255), outline=(30, 30, 30, 255), width=5 * k)
    d.ellipse((c - 18 * k, c - 18 * k, c + 18 * k, c + 18 * k), fill=(40, 40, 40, 255))
    save_icon(img, "icon_gear.png")


def icon_money():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    for i, off in enumerate([(14, 46), (8, 36), (2, 26)]):
        x, y = off[0] * k, off[1] * k
        d.rounded_rectangle((x + 8 * k, y + 8 * k, x + 112 * k, y + 64 * k), 8 * k, fill=(40, 90, 30, 255))
        d.rounded_rectangle((x + 8 * k, y + 8 * k, x + 112 * k, y + 58 * k), 8 * k, fill=(126, 200, 80, 255), outline=(30, 70, 20, 255), width=4 * k)
        d.ellipse((x + 46 * k, y + 18 * k, x + 74 * k, y + 48 * k), fill=(90, 160, 60, 255), outline=(30, 70, 20, 255), width=3 * k)
    save_icon(img, "icon_money.png")


def icon_home():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    d.polygon([(64 * k, 14 * k), (116 * k, 62 * k), (100 * k, 62 * k), (100 * k, 112 * k), (28 * k, 112 * k), (28 * k, 62 * k), (12 * k, 62 * k)],
              fill=(255, 255, 255, 255), outline=(30, 30, 30, 255), width=6 * k)
    d.rectangle((54 * k, 78 * k, 74 * k, 112 * k), fill=(60, 60, 60, 255))
    save_icon(img, "icon_home.png")


def icon_tree():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    d.rectangle((56 * k, 80 * k, 72 * k, 118 * k), fill=(140, 96, 60, 255), outline=(40, 25, 10, 255), width=4 * k)
    d.polygon([(64 * k, 8 * k), (110 * k, 88 * k), (18 * k, 88 * k)], fill=(96, 180, 70, 255), outline=(25, 60, 20, 255), width=5 * k)
    save_icon(img, "icon_tree.png")


def icon_arrow():
    """方向矢印（右向き）"""
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    d.polygon([(20 * k, 20 * k), (112 * k, 64 * k), (20 * k, 108 * k), (42 * k, 64 * k)], fill=(255, 255, 255, 255), outline=(30, 30, 30, 255), width=6 * k)
    save_icon(img, "icon_arrow.png")


def icon_axe():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    d.line([(30 * k, 112 * k), (92 * k, 22 * k)], fill=(40, 25, 10, 255), width=18 * k)
    d.line([(30 * k, 112 * k), (92 * k, 22 * k)], fill=(176, 120, 70, 255), width=10 * k)
    d.polygon([(70 * k, 14 * k), (120 * k, 30 * k), (110 * k, 72 * k), (84 * k, 44 * k)], fill=(214, 220, 226, 255), outline=(40, 40, 46, 255), width=5 * k)
    save_icon(img, "icon_axe.png")


def icon_truck():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((8 * k, 40 * k, 78 * k, 92 * k), 6 * k, fill=(242, 178, 50, 255), outline=(40, 30, 10, 255), width=5 * k)
    d.rounded_rectangle((74 * k, 54 * k, 120 * k, 92 * k), 8 * k, fill=(242, 178, 50, 255), outline=(40, 30, 10, 255), width=5 * k)
    d.rectangle((86 * k, 60 * k, 110 * k, 74 * k), fill=(150, 200, 230, 255))
    for x in (32, 96):
        d.ellipse(((x - 15) * k, 80 * k, (x + 15) * k, 110 * k), fill=(40, 40, 44, 255))
        d.ellipse(((x - 6) * k, 89 * k, (x + 6) * k, 101 * k), fill=(170, 170, 176, 255))
    save_icon(img, "icon_truck.png")


def icon_wrench():
    """強化ボタン用（上向き矢印＋歯車）"""
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    d.polygon([(64 * k, 8 * k), (112 * k, 60 * k), (84 * k, 60 * k), (84 * k, 116 * k), (44 * k, 116 * k), (44 * k, 60 * k), (16 * k, 60 * k)],
              fill=(123, 211, 79, 255), outline=(25, 70, 20, 255), width=7 * k)
    save_icon(img, "icon_upgrade.png")


def icon_close():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    d.ellipse((4 * k, 4 * k, 124 * k, 124 * k), fill=(255, 255, 255, 255))
    d.ellipse((12 * k, 12 * k, 116 * k, 116 * k), fill=(229, 52, 47, 255))
    d.ellipse((20 * k, 16 * k, 108 * k, 60 * k), fill=(255, 255, 255, 50))
    for a, b in [((42, 42), (86, 86)), ((86, 42), (42, 86))]:
        d.line([(a[0] * k, a[1] * k), (b[0] * k, b[1] * k)], fill=(255, 255, 255, 255), width=14 * k)
    save_icon(img, "icon_close.png")


def badge(name, color, symbol):
    img, k = icon_canvas(96)
    d = ImageDraw.Draw(img)
    d.ellipse((2 * k, 2 * k, 94 * k, 94 * k), fill=(255, 255, 255, 255))
    d.ellipse((8 * k, 8 * k, 88 * k, 88 * k), fill=color)
    w = (255, 255, 255, 255)
    if symbol == "ff":
        for x0 in (22, 46):
            d.polygon([(x0 * k, 28 * k), ((x0 + 26) * k, 48 * k), (x0 * k, 68 * k)], fill=w)
    elif symbol == "up":
        d.polygon([(48 * k, 18 * k), (74 * k, 46 * k), (58 * k, 46 * k), (58 * k, 76 * k), (38 * k, 76 * k), (38 * k, 46 * k), (22 * k, 46 * k)], fill=w)
    elif symbol == "box":
        d.rounded_rectangle((24 * k, 34 * k, 72 * k, 72 * k), 6 * k, fill=w)
        d.rectangle((40 * k, 24 * k, 56 * k, 36 * k), outline=w, width=5 * k)
        d.rectangle((26 * k, 48 * k, 70 * k, 52 * k), fill=color)
    save_icon(img, name, 96)


def icon_fuel():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((22 * k, 26 * k, 106 * k, 118 * k), 10 * k, fill=(229, 90, 46, 255), outline=(60, 20, 10, 255), width=6 * k)
    d.rectangle((70 * k, 10 * k, 96 * k, 30 * k), fill=(60, 60, 60, 255))
    d.line([(40 * k, 50 * k), (88 * k, 98 * k)], fill=(255, 220, 180, 255), width=7 * k)
    save_icon(img, "icon_fuel.png")


def icon_log():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    for i, y in enumerate((70, 40)):
        x = 14 + i * 10
        d.rounded_rectangle((x * k, y * k, (x + 90) * k, (y + 34) * k), 16 * k, fill=(140, 92, 54, 255), outline=(50, 30, 15, 255), width=5 * k)
        d.ellipse(((x + 70) * k, y * k, (x + 104) * k, (y + 34) * k), fill=(232, 201, 154, 255), outline=(50, 30, 15, 255), width=5 * k)
    save_icon(img, "icon_log.png")


def icon_worker():
    img, k = icon_canvas()
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((34 * k, 64 * k, 94 * k, 122 * k), 14 * k, fill=(58, 98, 168, 255), outline=(20, 30, 60, 255), width=5 * k)
    d.ellipse((38 * k, 26 * k, 90 * k, 78 * k), fill=(242, 196, 155, 255), outline=(60, 40, 20, 255), width=5 * k)
    d.chord((32 * k, 14 * k, 96 * k, 74 * k), 180, 360, fill=(242, 194, 48, 255), outline=(70, 50, 10, 255), width=5 * k)
    save_icon(img, "icon_worker.png")


def main() -> None:
    TEX.mkdir(parents=True, exist_ok=True)
    UI.mkdir(parents=True, exist_ok=True)
    metal()
    leaf_noise()
    # 9-slice の下地（Godot の StyleBoxTexture で伸ばして使う）
    gradient_box("btn_green.png", (96, 96), "#7BD34F", "#3E9E2E", "#2a6a1e", 16, bottom_edge=(30, 90, 22, 255))
    gradient_box("btn_green_pressed.png", (96, 96), "#5fb83a", "#357f26", "#2a6a1e", 16)
    gradient_box("btn_gray.png", (96, 96), "#E0E0E0", "#A8A8A8", "#6e6e6e", 16, bottom_edge=(110, 110, 110, 255))
    gradient_box("card_metal.png", (96, 96), "#EDEDED", "#CFCFCF", "#8f8f8f", 10, border_w=2, inner_hi=False)
    gradient_box("header_bar.png", (256, 96), "#F2B33D", "#E0952A", "#9a5d14", 4, border_w=3, scratches=True, inner_hi=False)
    gradient_box("tile.png", (96, 96), "#3a3d40", "#26282a", "#6b7075", 14, bottom_edge=(15, 15, 16, 255))
    gradient_box("tile_pressed.png", (96, 96), "#2e3133", "#202224", "#6b7075", 14)
    icon_gear()
    icon_money()
    icon_home()
    icon_tree()
    icon_arrow()
    icon_axe()
    icon_truck()
    icon_wrench()
    icon_close()
    icon_fuel()
    icon_log()
    icon_worker()
    badge("badge_speed.png", (60, 170, 60, 255), "ff")
    badge("badge_power.png", (226, 64, 56, 255), "up")
    badge("badge_capacity.png", (232, 172, 40, 255), "box")


if __name__ == "__main__":
    main()
