class_name ChoppableTree
extends StaticBody3D
## 切れる木。硬さ(hardness)ぶんダメージを受けると倒れて丸太を数本落とし、一定時間で再生する。
## 見た目は幹（樹皮テクスチャ）と葉を1メッシュにまとめ、描画は TreeField が MultiMesh でまとめて行う。
## このノードは見た目の Transform（揺れ・倒れる・生え直す）を計算して TreeField に書き込む。

signal felled(tree: ChoppableTree)

## 見た目のバリエーション数（色と形を少しずつ変える）
const VARIANTS := 3
const FALL_SEC := 0.55

var tree_id := ""
var area_index := 0
var max_hp := 1.0
var hp := 1.0
var alive := true
var radius := 0.35
## 伐採員が同じ木に群がらないための予約
var claimed_by: Node = null

var _def: Dictionary = {}
var _respawn_sec := 8.0
var _scale := 1.0
var _visual: Node3D
## 切り株は倒れている間だけ表示する（生きている間は幹に隠れるので描画を省く）
var _stump: MeshInstance3D
var _shape: CollisionShape3D
var _bar_root: Node3D
var _bar_fill: MeshInstance3D
var _bar_timer := 0.0
var _shake_tween: Tween
## 描画をまとめる TreeField（main が設定する）
var field: TreeField
var _variant := 0
var _mm: MultiMesh
var _mm_index := -1
## 見た目が動いている残り時間（この間だけ MultiMesh を更新する）
var _anim_left := 0.0


func setup(def: Dictionary, p_area_index: int, variant := 0) -> void:
	_def = def
	tree_id = str(def["id"])
	area_index = p_area_index
	max_hp = float(def.get("hardness", 1))
	hp = max_hp
	_respawn_sec = float(def.get("respawn_sec", 8.0))
	_scale = float(def.get("scale", 1.0)) * (0.9 + 0.1 * variant)
	radius = 0.28 * _scale
	collision_layer = 1
	collision_mask = 0
	add_to_group("trees")

	# 切り株（倒れても残る）
	_stump = MeshInstance3D.new()
	_stump.mesh = _build_stump(def, variant)
	_stump.visible = false
	add_child(_stump)

	_stump.material_override = Mats.tree(false)
	_variant = variant
	_visual = Node3D.new()
	add_child(_visual)

	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 2.0
	_shape.shape = cyl
	_shape.position.y = 1.0
	add_child(_shape)

	_build_hp_bar()


func _ready() -> void:
	if field:
		field.register(self, _build_mesh(_def, _variant), "%s/%d" % [tree_id, _variant])


## TreeField が MultiMesh を作ったときに呼ぶ。
func bind_instance(mm: MultiMesh, index: int) -> void:
	_mm = mm
	_mm_index = index
	_push_visual()


func _push_visual() -> void:
	if _mm == null:
		return
	var xf := global_transform * _visual.transform
	if not _visual.visible:
		xf = Transform3D(Basis().scaled(Vector3.ZERO), global_position)
	_mm.set_instance_transform(_mm_index, xf)


func _animate(sec: float) -> void:
	_anim_left = maxf(_anim_left, sec + 0.05)


## 切り株と切り口。種類とバリエーションごとにキャッシュする。
static func _build_stump(def: Dictionary, variant: int) -> Mesh:
	var r := 0.28 * float(def.get("scale", 1.0)) * (0.9 + 0.1 * variant)
	var base := CylinderMesh.new()
	base.bottom_radius = r * 1.15
	base.top_radius = r
	base.height = 0.22
	base.radial_segments = 7
	base.rings = 1
	var face := CylinderMesh.new()
	face.bottom_radius = r * 0.95
	face.top_radius = r * 0.95
	face.height = 0.02
	face.radial_segments = 7
	face.rings = 1
	return Fx.merged("stump/%s/%d" % [def["id"], variant], [
		[base, Transform3D(Basis(), Vector3(0, 0.11, 0)), bark_color(def).darkened(0.1)],
		[face, Transform3D(Basis(), Vector3(0, 0.225, 0)), Color(0.85, 0.72, 0.52, 0.5)],
	])


## 種類とバリエーションごとにメッシュを作ってキャッシュする。
static func _build_mesh(def: Dictionary, variant: int) -> Mesh:
	var id := str(def["id"])
	var s := float(def.get("scale", 1.0)) * (0.9 + 0.1 * variant)
	var trunk_color := bark_color(def)
	var leaf := leaf_color(def)
	leaf = leaf.lightened(0.05 * (variant - 1)) if variant != 1 else leaf
	var parts := []
	var trunk_h := 1.2 * s
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18 * s
	trunk.bottom_radius = 0.28 * s
	trunk.height = trunk_h
	trunk.radial_segments = 6
	trunk.rings = 1
	parts.append([trunk, Transform3D(Basis(), Vector3(0, trunk_h * 0.5, 0)), trunk_color])

	if def.get("shape", "sphere") == "cone":
		# 針葉樹: 円錐を3段重ねる
		var y := trunk_h * 0.55
		for i in 3:
			var cone := CylinderMesh.new()
			var r := (1.05 - i * 0.25) * s
			var h := (1.3 - i * 0.18) * s
			cone.bottom_radius = r
			cone.top_radius = 0.0
			cone.height = h
			cone.radial_segments = 7
			cone.rings = 1
			var rot := Basis(Vector3.UP, 0.4 * i + variant)
			parts.append([cone, Transform3D(rot, Vector3(0, y + h * 0.5, 0)), leaf.darkened(0.08 * (2 - i))])
			y += h * 0.45
	else:
		# 広葉樹: 角ばった球を3つ寄せる
		var blobs := [
			[Vector3(0, trunk_h + 0.45 * s, 0), 0.85],
			[Vector3(0.45 * s, trunk_h + 0.2 * s, 0.15 * s), 0.55],
			[Vector3(-0.35 * s, trunk_h + 0.25 * s, -0.3 * s), 0.6],
		]
		for i in blobs.size():
			var b: Array = blobs[i]
			var sph := SphereMesh.new()
			sph.radius = b[1] * s
			sph.height = b[1] * s * 2.0
			sph.radial_segments = 7
			sph.rings = 4
			var rot := Basis(Vector3.UP, 0.7 * i + variant * 1.3)
			parts.append([sph, Transform3D(rot, rot * b[0] if variant == 2 else b[0]), leaf.darkened(0.06 * i)])
	return Fx.merged("tree/%s/%d" % [id, variant], parts)


## 樹皮の色（頂点カラーの a = 0 は「樹皮テクスチャを貼る」の印）。元の色より少し彩度を落とす。
static func bark_color(def: Dictionary) -> Color:
	var c := Color(def.get("trunk_color", "#8a5a33"))
	c.s *= 0.8
	return Color(c.r, c.g, c.b, 0.0)


## 葉の色（a = 1 は「葉」の印）。おもちゃっぽく見えないよう、彩度と明るさを落とした自然な色にする。
static func leaf_color(def: Dictionary) -> Color:
	var c := Color(def.get("leaf_color", "#4f9f4f"))
	c.s *= 0.78
	c.v *= 0.8
	return Color(c.r, c.g, c.b, 1.0)


func _build_hp_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.position = Vector3(0, 2.6 * _scale + 0.4, 0)
	_bar_root.visible = false
	add_child(_bar_root)
	var bg := MeshInstance3D.new()
	bg.mesh = _bar_quad(Vector2(0.9, 0.13), Color(0.1, 0.08, 0.05, 0.85))
	_bar_root.add_child(bg)
	_bar_fill = MeshInstance3D.new()
	_bar_fill.mesh = _bar_quad(Vector2(0.84, 0.08), Color("#7fe05a"))
	_bar_fill.position.z = 0.001
	_bar_root.add_child(_bar_fill)


static func _bar_quad(size: Vector2, color: Color) -> Mesh:
	return Fx._cached("bar%s%s" % [size, color.to_html()], func() -> Mesh:
		var q := QuadMesh.new()
		q.size = size
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.no_depth_test = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.render_priority = 1 if color.a >= 1.0 else 0
		q.material = m
		return q)


func _process(delta: float) -> void:
	if _anim_left > 0.0:
		_anim_left -= delta
		_push_visual()
	if _bar_timer > 0.0:
		_bar_timer -= delta
		if _bar_timer <= 0.0:
			_bar_root.visible = false


## ダメージを与える。倒れたら true。
func hit(damage: float, from := Vector3.INF) -> bool:
	if not alive:
		return false
	hp -= damage
	_shake()
	var trunk_color := Color(_def.get("trunk_color", "#8a5a33"))
	# 木くず（明るい木口の色と樹皮の色）
	Fx.burst(self, global_position + Vector3(0, 0.7, 0), [trunk_color.lightened(0.35), Color("#e8c99a"), trunk_color.darkened(0.2)], 12, 3.2, 0.07, 0.55)
	Audio.play("chop", -4.0)
	if hp <= 0.0:
		_fell(from)
		return true
	_bar_root.visible = true
	_bar_timer = 2.5
	_bar_fill.scale.x = clampf(hp / max_hp, 0.02, 1.0)
	return false


func _shake() -> void:
	if _shake_tween:
		_shake_tween.kill()
	var tween := create_tween()
	_shake_tween = tween
	tween.tween_property(_visual, "rotation_degrees:z", 5.0, 0.05)
	tween.tween_property(_visual, "rotation_degrees:z", -3.0, 0.07)
	tween.tween_property(_visual, "rotation_degrees:z", 0.0, 0.06)
	_animate(0.2)


func _fell(from: Vector3) -> void:
	alive = false
	claimed_by = null
	if _shake_tween:
		_shake_tween.kill()
	_bar_root.visible = false
	_stump.visible = true
	_shape.set_deferred("disabled", true)
	felled.emit(self)
	# 切った人と反対側へ倒す
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	if from != Vector3.INF:
		dir = Vector3(global_position.x - from.x, 0, global_position.z - from.z)
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var axis := Vector3.UP.cross(dir).normalized()
	_visual.rotation = Vector3.ZERO
	var start := _visual.transform
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		_visual.transform = Transform3D(Basis(axis, t * PI * 0.5), Vector3.ZERO) * start, 0.0, 1.0, FALL_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _on_landed(dir))
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.3).set_delay(0.15)
	tween.tween_callback(func() -> void:
		_visual.visible = false
		_push_visual())
	_animate(FALL_SEC + 0.5)
	Audio.play("tree_fall", -3.0)


func _on_landed(dir: Vector3) -> void:
	var leaf := Color(_def.get("leaf_color", "#4f9f4f"))
	var land := global_position + dir * 1.6 * _scale
	Fx.burst(self, land + Vector3(0, 0.4, 0), [leaf, leaf.lightened(0.2)], 16, 3.5, 0.12, 0.8)
	Fx.burst(self, global_position + Vector3(0, 0.1, 0), [Color("#cbb48a")], 8, 1.5, 0.15, 0.6, -2.0)
	Fx.shake(self, 0.08)
	LogDrop.spawn_from_tree(self, tree_id, dir)
	get_tree().create_timer(_respawn_sec).timeout.connect(_respawn)


func _respawn() -> void:
	hp = max_hp
	alive = true
	_visual.transform = Transform3D()
	_visual.visible = true
	_stump.visible = false
	_visual.scale = Vector3.ONE * 0.05
	_shape.set_deferred("disabled", false)
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_animate(0.5)
