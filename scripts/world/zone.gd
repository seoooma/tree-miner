class_name Zone
extends Node3D
## 地面に描く受け渡し場所の印（施設ごとの色の角丸プレート＋白い枠＋中の文字＋下の小さな文字）。
## 例: 「積み込み」「製材中」と、その下に「積載量: 3」。見た目だけで、判定は各 Station の半径で行う。

const OUTLINE := Color(1, 1, 1, 0.95)
const TEXT_OUTLINE := Color(0.08, 0.06, 0.04, 1.0)
const TITLE_PX := 0.0052
const SUB_PX := 0.0042

var size := Vector2(3.0, 3.0)
var fill := Color(1, 1, 1, 0.12)

var _title: Label3D
var _sub: Label3D
var _fill_mi: MeshInstance3D


func _init(p_size := Vector2(3.0, 3.0), p_fill := Color(1, 1, 1, 0.12)) -> void:
	size = p_size
	fill = p_fill


func _ready() -> void:
	_fill_mi = MeshInstance3D.new()
	_fill_mi.mesh = _rounded_rect_mesh(size, 0.45, 0.0)
	_fill_mi.material_override = Mats.ground_paint(_plate(fill))
	_fill_mi.position.y = 0.025
	_fill_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill_mi)
	var ring := MeshInstance3D.new()
	ring.mesh = _rounded_rect_mesh(size, 0.45, 0.13)
	ring.material_override = Mats.ground_paint(OUTLINE)
	ring.position.y = 0.03
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_title = _flat_label(Vector3(0, 0.05, 0), 96, TITLE_PX)
	_title.outline_modulate = Color(fill.r, fill.g, fill.b).darkened(0.6)
	add_child(_title)
	_sub = _flat_label(Vector3(0, 0.05, size.y * 0.5 + 0.42), 72, SUB_PX)
	add_child(_sub)


## 中の文字と下の文字を設定する。文字数が多いときは枠に収まるように小さくする。
func set_text(title: String, sub := "") -> void:
	if _title == null:
		return
	if _title.text != title:
		_title.text = title
		_title.pixel_size = _fit(title, 96, TITLE_PX, size.x * 0.86)
	if _sub.text != sub:
		_sub.text = sub
		_sub.pixel_size = _fit(sub, 72, SUB_PX, size.x * 1.6)


func set_fill(color: Color) -> void:
	if _fill_mi:
		_fill_mi.material_override = Mats.ground_paint(_plate(color))


## 呼び出し側の薄い塗り色を、はっきり色のわかるプレートの色にする（色は同じで、濃さだけ上げる）。
static func _plate(c: Color) -> Color:
	return Color(c.r, c.g, c.b, clampf(c.a * 3.2, 0.3, 0.62))


static func _fit(text: String, font_size: int, px: float, max_width: float) -> float:
	var longest := 0.0
	for line in text.split("\n"):
		var w := 0.0
		for ch in line:
			w += 0.55 if ch.unicode_at(0) < 0x2000 else 1.0
		longest = maxf(longest, w)
	if longest <= 0.0:
		return px
	return minf(px, max_width / (longest * font_size))


static func _flat_label(pos: Vector3, font_size: int, px: float) -> Label3D:
	var l := Label3D.new()
	l.position = pos
	l.rotation_degrees.x = -90.0
	l.font_size = font_size
	l.pixel_size = px
	l.outline_size = 16
	l.outline_modulate = TEXT_OUTLINE
	l.modulate = Color.WHITE
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	return l


## 角丸の四角（width > 0 なら太さ width の枠、0 なら塗りつぶし）を XZ 平面に作る。
static func _rounded_rect_mesh(sz: Vector2, radius: float, width: float) -> Mesh:
	return Fx._cached("zone/%s/%.2f/%.2f" % [sz, radius, width], func() -> Mesh:
		var path := PackedVector2Array()
		var hx := sz.x * 0.5 - radius
		var hz := sz.y * 0.5 - radius
		var corners := [Vector2(hx, hz), Vector2(-hx, hz), Vector2(-hx, -hz), Vector2(hx, -hz)]
		for c in 4:
			for k in 7:
				var a := (c * 90.0 + k * 15.0) * PI / 180.0
				path.append(corners[c] + Vector2(cos(a), sin(a)) * radius)
		var verts := PackedVector3Array()
		var n := path.size()
		if width <= 0.0:
			for i in n:
				var a := path[i]
				var b := path[(i + 1) % n]
				verts.append(Vector3(0, 0, 0))
				verts.append(Vector3(b.x, 0, b.y))
				verts.append(Vector3(a.x, 0, a.y))
		else:
			for i in n:
				var a := path[i]
				var b := path[(i + 1) % n]
				var na := _inset(path, i, width)
				var nb := _inset(path, (i + 1) % n, width)
				verts.append(Vector3(a.x, 0, a.y))
				verts.append(Vector3(nb.x, 0, nb.y))
				verts.append(Vector3(b.x, 0, b.y))
				verts.append(Vector3(a.x, 0, a.y))
				verts.append(Vector3(na.x, 0, na.y))
				verts.append(Vector3(nb.x, 0, nb.y))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		normals.fill(Vector3.UP)
		arr[Mesh.ARRAY_NORMAL] = normals
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m)


## 角丸の輪郭上の点を、内側に width だけずらした点。
static func _inset(path: PackedVector2Array, i: int, width: float) -> Vector2:
	var n := path.size()
	var prev := path[(i - 1 + n) % n]
	var next := path[(i + 1) % n]
	var tangent := (next - prev).normalized()
	var inward := Vector2(-tangent.y, tangent.x)
	# 時計回り／反時計回りに関係なく、中心側を向くようにする
	if inward.dot(-path[i]) < 0.0:
		inward = -inward
	return path[i] + inward * width
