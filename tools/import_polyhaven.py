"""Poly Haven（CC0）のテクスチャを取り込み、ゲーム用に 512px へ縮小して assets/textures に書き出す。

  pip install numpy pillow
  python tools/import_polyhaven.py

Poly Haven の API（https://api.polyhaven.com）から 1k の JPG を取ってきて、
カラー（albedo）と OpenGL 形式の法線マップ（nor_gl。Godot と同じ向き）を 512px の PNG にする。
素材の出典とライセンスは CREDITS.md に書いてある（すべて CC0）。
"""
import io
import json
import pathlib
import urllib.request

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEX = ROOT / "assets" / "textures"
SIZE = 512

# ゲーム内の名前: (Poly Haven のアセット ID, カラーを明るさの模様にする場合の平均の明るさ)
# 樹皮と板材は、木の種類や小物ごとの色をコード側で掛けるので、色をほぼ抜いて平均の明るさをそろえる。
ASSETS = {
	"grass": ("leafy_grass", None),             # 森の草地
	"forest": ("forrest_ground_01", None),      # 草と土が混じった林床（草地に混ぜるパッチ）
	"yard": ("rocky_trail", None),              # 踏み固めた作業場（小石まじりの土）
	"road": ("dirt", None),                     # 土の道
	"bark": ("bark_brown_02", 0.62),            # 樹皮
	"wood": ("weathered_brown_planks", 0.85),   # 建物・小物の板材
	"roof": ("corrugated_iron", 0.8),           # 製材所などの波板の屋根
}


def detail(img: Image.Image, target: float) -> Image.Image:
	"""色を 3 割だけ残して明るさの模様にし、平均の明るさを target にそろえる。"""
	a = np.asarray(img, dtype=np.float32) / 255.0
	lum = a.mean(axis=2, keepdims=True)
	mix = 0.3 * a / a.reshape(-1, 3).mean(axis=0) + 0.7 * lum / lum.mean()
	return Image.fromarray(np.clip(mix * target * 255.0, 0, 255).astype(np.uint8), "RGB")


def fetch(url: str) -> bytes:
	req = urllib.request.Request(url, headers={"User-Agent": "tree-miner-asset-import"})
	with urllib.request.urlopen(req, timeout=60) as r:
		return r.read()


def shade(albedo_path: pathlib.Path, normal: Image.Image) -> None:
	"""法線マップの左右の傾き（R）から陰影を作り、カラーに掛ける。"""
	a = np.asarray(Image.open(albedo_path).convert("RGB"), dtype=np.float32)
	n = np.asarray(normal, dtype=np.float32)[:, :, :1] / 255.0
	a *= np.clip(1.0 + (n - 0.5) * 1.3, 0.6, 1.3)
	Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB").save(albedo_path, optimize=True)


def main() -> None:
	TEX.mkdir(parents=True, exist_ok=True)
	for name, (asset, detail_target) in ASSETS.items():
		# 屋根の法線マップはカラーに焼き込むだけで、ファイルには書き出さない
		files = json.loads(fetch(f"https://api.polyhaven.com/files/{asset}"))
		for suffix, key in (("albedo", "Diffuse"), ("normal", "nor_gl")):
			url = files[key]["1k"]["jpg"]["url"]
			img = Image.open(io.BytesIO(fetch(url))).convert("RGB")
			img = img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
			if suffix == "albedo" and detail_target is not None:
				img = detail(img, detail_target)
			if name == "roof" and suffix == "normal":
				# 波板の凹凸は小物のメッシュでは法線マップが効きにくいので、カラーにも陰影として焼き込む
				shade(TEX / "roof_albedo.png", img)
				continue
			out = TEX / f"{name}_{suffix}.png"
			img.save(out, optimize=True)
			print(f"{asset} {key} -> {out.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
