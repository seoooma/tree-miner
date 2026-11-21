class_name UiKit
## HUD 用の部品（フォント・縁取り文字・ボタンの下地・アイコン）。
## 見出しと数字は Dela Gothic One、本文は M PLUS Rounded 1c (Black)。どちらも SIL Open Font License。
## 主要な文字は白＋濃い縁取り＋小さな影。「次の値」の数字は黄色＋こげ茶の縁取り。

const TITLE_FONT := "res://fonts/DelaGothicOne-subset.ttf"
const BODY_FONT := "res://fonts/MPLUSRounded1c-Black-subset.ttf"
const UI_DIR := "res://assets/ui/"

const WHITE := Color.WHITE
const OUTLINE_DARK := Color(0.09, 0.07, 0.05)
const NEXT_YELLOW := Color("#FFD23F")
const NEXT_OUTLINE := Color("#4a2a0c")
const PRICE_RED := Color("#E23B2E")

static var _fonts: Dictionary = {}


static func font(title := false) -> Font:
	var path := TITLE_FONT if title else BODY_FONT
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]


static func icon(name: String) -> Texture2D:
	return load(UI_DIR + name + ".png") as Texture2D


## 縁取り付きのラベル。outline は縁の太さ（px）。
static func label(text: String, size: int, title := false, color := WHITE, outline := 10, outline_color := OUTLINE_DARK, shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_label(l, size, title, color, outline, outline_color, shadow)
	return l


static func style_label(l: Label, size: int, title := false, color := WHITE, outline := 10, outline_color := OUTLINE_DARK, shadow := true) -> void:
	l.add_theme_font_override("font", font(title))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", outline_color)
	if shadow and outline > 0:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 3)
		l.add_theme_constant_override("shadow_outline_size", outline)
	else:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))


## 9-slice の画像の下地。margin は伸ばさない縁の幅。
static func tex_box(name: String, margin := 18, content := 12) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = icon(name)
	s.set_texture_margin_all(margin)
	s.set_content_margin_all(content)
	return s


static func flat_box(color: Color, radius := 18, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.anti_aliasing = true
	return s


## Button の見た目を下地画像で揃える。pressed が無ければ normal を少し暗くして使う。
static func skin_button(b: Button, normal: String, pressed := "", margin := 18, content := 12) -> void:
	var n := tex_box(normal, margin, content)
	var p := tex_box(pressed if pressed != "" else normal, margin, content)
	if pressed == "":
		p.modulate_color = Color(0.85, 0.85, 0.85)
	# 押すと中身が 3px 沈む
	p.content_margin_top = content + 6
	p.content_margin_bottom = maxf(0.0, content - 6)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## 四角いタイル型ボタン（濃い灰色・明るい縁・内側の面取り・アイコン＋小さな縁取り文字）。押すと 3px 沈む。
static func tile_button(icon_name: String, text: String, size := Vector2(140, 140)) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	skin_button(b, "tile", "tile_pressed", 20, 10)
	b.focus_mode = Control.FOCUS_NONE
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var ic := TextureRect.new()
	ic.texture = icon(icon_name)
	ic.custom_minimum_size = Vector2(size.x * 0.55, size.y * 0.5)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var l := label(text, 26, false, WHITE, 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.name = "Text"
	box.add_child(l)
	# 押している間は中身ごと 3px 沈める
	b.button_down.connect(func() -> void: box.position.y = 6)
	b.button_up.connect(func() -> void: box.position.y = 0)
	return b


static func set_tile_text(b: Button, text: String) -> void:
	var l := b.find_child("Text", true, false) as Label
	if l:
		l.text = text


## 丸いアイコンだけのボタン（設定ギア・閉じる）。
static func icon_button(icon_name: String, size := 88) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = icon(icon_name)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.pivot_offset = Vector2(size, size) * 0.5
	b.button_down.connect(func() -> void: b.scale = Vector2.ONE * 0.92)
	b.button_up.connect(func() -> void: b.scale = Vector2.ONE)
	return b


## 横長のゲージ（暗いトラック＋色の付いた中身）。fill は 0..1。
class Bar:
	extends Control
	var fill := 0.0:
		set(v):
			fill = clampf(v, 0.0, 1.0)
			queue_redraw()
	var color := Color("#F2C230")
	var track := Color(0.08, 0.08, 0.08, 0.82)
	var radius := 8

	func _init(p_color := Color("#F2C230"), p_size := Vector2(200, 30)) -> void:
		color = p_color
		custom_minimum_size = p_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiKit.flat_box(track, radius, 2, Color(0, 0, 0, 0.6)), r)
		if fill > 0.0:
			var inner := Rect2(Vector2(3, 3), Vector2((size.x - 6) * fill, size.y - 6))
			draw_style_box(UiKit.flat_box(color, radius - 2), inner)
			draw_rect(Rect2(inner.position + Vector2(2, 1), Vector2(maxf(0.0, inner.size.x - 4), inner.size.y * 0.35)), Color(1, 1, 1, 0.22))
