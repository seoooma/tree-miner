"""Noto Sans JP からゲームで使う文字だけを抜き出した軽量フォントを作る。

Web 版はブラウザに日本語フォントが無いと文字化けするため、フォントを同梱している。
フル版 (約9MB) は重いので、次の文字だけに絞る:
  - ASCII / Latin-1 / 矢印・記号
  - ひらがな・カタカナ・全角記号
  - JIS 第1水準漢字 (約3,000字)
  - リポジトリ内の .gd / .json / .tscn / .cfg / .godot に出てくる全文字（第2水準の漢字なども拾う）

使い方（新しい文字を UI に足して表示されないとき）:
  pip install fonttools
  python tools/subset_font.py path/to/NotoSansJP[wght].ttf
  python tools/subset_font.py path/to/MPLUSRounded1c-Black.ttf MPLUSRounded1c-Black-subset.ttf
  python tools/subset_font.py path/to/DelaGothicOne-Regular.ttf DelaGothicOne-subset.ttf --repo-only
元フォント（いずれも SIL Open Font License 1.1）:
  https://github.com/google/fonts/tree/main/ofl/notosansjp
  https://github.com/google/fonts/tree/main/ofl/mplusrounded1c
  https://github.com/google/fonts/tree/main/ofl/delagothicone
--repo-only を付けると第1水準漢字を入れず、リポジトリ内に出てくる文字だけにする（見出し・数字用の軽量版）。
"""
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "fonts" / "MPLUSRounded1c-Black-subset.ttf"
WEIGHT = 700


def jis_level1() -> str:
    chars = []
    for hi in range(0xB0, 0xD0):
        for lo in range(0xA1, 0xFF):
            try:
                chars.append(bytes([hi, lo]).decode("euc_jp"))
            except UnicodeDecodeError:
                pass
    return "".join(chars)


def repo_chars() -> str:
    text = []
    for ext in ("*.gd", "*.json", "*.tscn", "*.cfg", "*.godot"):
        for p in ROOT.rglob(ext):
            if ".godot" in p.parts:
                continue
            text.append(p.read_text(encoding="utf-8"))
    return "".join(text)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    src = args[0]
    out = ROOT / "fonts" / args[1] if len(args) > 1 else OUT
    chars = set(repo_chars())
    if "--repo-only" not in sys.argv:
        chars |= set(jis_level1())
    ranges = [(0x20, 0x7E), (0xA0, 0xFF), (0x2010, 0x206F), (0x2190, 0x21FF), (0x2460, 0x24FF),
              (0x25A0, 0x25FF), (0x2600, 0x26FF), (0x3000, 0x30FF), (0xFF00, 0xFFEF)]
    for a, b in ranges:
        chars.update(chr(c) for c in range(a, b + 1))

    font = TTFont(src)
    if "fvar" in font:
        font = instancer.instantiateVariableFont(font, {"wght": WEIGHT})
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    sub = subset.Subsetter(options)
    sub.populate(text="".join(chars))
    sub.subset(font)
    out.parent.mkdir(exist_ok=True)
    font.save(out)
    print(f"{out} ({out.stat().st_size // 1024} KB, {len(chars)} chars)")


if __name__ == "__main__":
    main()
