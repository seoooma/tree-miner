class_name ChoppableTree
extends StaticBody3D
## 切れる木。硬さ(hardness)ぶんダメージを受けると倒れて丸太を数本落とし、一定時間で再生する。
## 見た目は幹（樹皮テクスチャ）と葉を1メッシュにまとめ、描画は TreeField が MultiMesh でまとめて行う。
## このノードは見た目の Transform（揺れ・倒れる・生え直す）を計算して TreeField に書き込む。

signal felled(tree: ChoppableTree)

## 見た目のバリエーション数（色と形を少しずつ変える）
const VARIANTS := 3
## 倒れ始めの「メキッ」と傾く時間。これと FALL_SEC を足した時間で着地する（以前の 0.55 秒と同じ）
const CREAK_SEC := 0.1
const FALL_SEC := 0.45

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
## 幹は根元が広がり、広葉樹は枝の先にでこぼこした葉のかたまりを5つ、針葉樹は枝先が垂れた段を4つ重ねる。
## 木は数百本あるので、1本あたり三角形 400 枚ほどに抑えている（MultiMesh でまとめて描く）。
static func _build_mesh(def: Dictionary, variant: int) -> Mesh:
	var id := str(def["id"])
	var s := float(def.get("scale", 1.0)) * (0.9 + 0.1 * variant)
	var trunk_color := bark_color(def)
	var leaf := leaf_color(def)
	leaf = leaf.lightened(0.05 * (variant - 1)) if variant != 1 else leaf
	var seed_value := float(variant) * 2.3 + float(id.hash() % 97) * 0.1
	var parts := []
	var trunk_h := 1.2 * s
	var cone: bool = def.get("shape", "sphere") == "cone"
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15 * s if cone else 0.17 * s
	trunk.bottom_radius = 0.26 * s
	trunk.height = trunk_h
	trunk.radial_segments = 7
	trunk.rings = 2
	parts.append([Fx.lumpy(trunk, 0.08, seed_value), Transform3D(Basis(), Vector3(0, trunk_h * 0.5, 0)), trunk_color])
	# 根元の張り出し
	var flare := CylinderMesh.new()
	flare.top_radius = 0.24 * s
	flare.bottom_radius = 0.38 * s
	flare.height = 0.22 * s
	flare.radial_segments = 7
	flare.rings = 1
	parts.append([Fx.lumpy(flare, 0.18, seed_value + 1.0), Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 0.11 * s, 0)), trunk_color])

	if cone:
		# 針葉樹: 枝先が垂れた段を4つ重ね、てっぺんに細い先端
		var y := trunk_h * 0.42
		for i in 4:
			var tier := CylinderMesh.new()
			var r := (1.1 - i * 0.22) * s
			var h := (1.05 - i * 0.12) * s
			tier.bottom_radius = r
			tier.top_radius = 0.0
			tier.height = h
			tier.radial_segments = 9
			tier.rings = 2
			var rot := Basis(Vector3.UP, 0.5 * i + variant)
			var shade := 0.1 * (3 - i) / 3.0
			parts.append([Fx.lumpy(tier, 0.12, seed_value + i * 1.9, 0.16), Transform3D(rot, Vector3(0, y + h * 0.5, 0)), leaf.darkened(shade)])
			y += h * 0.5
		var tip := CylinderMesh.new()
		tip.bottom_radius = 0.22 * s
		tip.top_radius = 0.0
		tip.height = 0.55 * s
		tip.radial_segments = 6
		tip.rings = 1
		parts.append([tip, Transform3D(Basis(), Vector3(0, y + 0.22 * s, 0)), leaf.lightened(0.04)])
	else:
		# 広葉樹: 幹から2本の枝を出し、その先と上に葉のかたまり
		for k in 2:
			var br := CylinderMesh.new()
			br.top_radius = 0.05 * s
			br.bottom_radius = 0.09 * s
			br.height = 0.75 * s
			br.radial_segments = 5
			br.rings = 1
			var yaw := 0.9 + k * PI + variant * 0.7
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, 0.75)
			parts.append([br, Transform3D(basis, Vector3(0, trunk_h * 0.85, 0) + basis.y * 0.3 * s), trunk_color])
		var blobs := [
			[Vector3(0, trunk_h + 0.55 * s, 0), 0.78],
			[Vector3(0.5 * s, trunk_h + 0.25 * s, 0.2 * s), 0.55],
			[Vector3(-0.45 * s, trunk_h + 0.3 * s, -0.25 * s), 0.58],
			[Vector3(0.05 * s, trunk_h + 0.2 * s, -0.5 * s), 0.5],
			[Vector3(-0.2 * s, trunk_h + 0.95 * s, 0.15 * s), 0.45],
		]
		for i in blobs.size():
			var b: Array = blobs[i]
			var sph := SphereMesh.new()
			sph.radius = b[1] * s
			sph.height = b[1] * s * 2.0
			sph.radial_segments = 8
			sph.rings = 5
			var rot := Basis(Vector3.UP, 0.7 * i + variant * 1.3)
			var at: Vector3 = Basis(Vector3.UP, variant * 2.1) * b[0]
			# 上のかたまりほど明るく（日が当たる）
			var tone := leaf.darkened(0.08) if at.y < trunk_h + 0.4 * s else leaf.lightened(0.03)
			parts.append([Fx.lumpy(sph, 0.16, seed_value + i * 2.7), Transform3D(rot.scaled(Vector3(1.0, 0.86, 1.0)), at), tone])
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
	var away := _away_from(from)
	_shake(away)
	var trunk_color := Color(_def.get("trunk_color", "#8a5a33"))
	# 木くずは切っている側（切った人の方）へ飛ぶ。明るい木口の色と樹皮の色
	var cut := global_position + Vector3(0, 0.55, 0) - away * radius
	Vfx.wood_chips(self, cut, -away + away.cross(Vector3.UP) * randf_range(-0.6, 0.6), [Color("#f0d9a8"), Color("#e2bd85"), trunk_color.lightened(0.15), trunk_color.darkened(0.2)], 9)
	Vfx.dust(self, cut, Color("#efe2c4"), 2, 0.35, 0.8)
	# 揺れた拍子に葉が数枚落ちる
	Vfx.leaves(self, global_position + Vector3(0, _canopy_height(), 0), _leaf_tint(), 3, 0.6 * _scale, 0.6)
	Audio.play("chop", -4.0)
	if hp <= 0.0:
		_fell(away)
		return true
	_bar_root.visible = true
	_bar_timer = 2.5
	_bar_fill.scale.x = clampf(hp / max_hp, 0.02, 1.0)
	return false


## 切った人から見て木の向こう側（水平・正規化）。わからなければランダム
func _away_from(from: Vector3) -> Vector3:
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	if from != Vector3.INF:
		dir = Vector3(global_position.x - from.x, 0, global_position.z - from.z)
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	return dir.normalized()


func _canopy_height() -> float:
	return 1.75 * _scale


func _leaf_tint() -> Color:
	var c := Color(_def.get("leaf_color", "#4f9f4f"))
	c.s *= 0.85
	c.v *= 0.9
	return c


## 斧が当たった向きに少し傾いて、しなって戻る
func _shake(away: Vector3) -> void:
	if _shake_tween:
		_shake_tween.kill()
	var axis := Vector3.UP.cross(away).normalized()
	var tween := create_tween()
	_shake_tween = tween
	tween.tween_method(func(a: float) -> void:
		_visual.transform = Transform3D(Basis(axis, deg_to_rad(a)), Vector3.ZERO), 0.0, 6.0, 0.05).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(a: float) -> void:
		_visual.transform = Transform3D(Basis(axis, deg_to_rad(a)), Vector3.ZERO), 6.0, -2.5, 0.12).set_trans(Tween.TRANS_SINE)
	tween.tween_method(func(a: float) -> void:
		_visual.transform = Transform3D(Basis(axis, deg_to_rad(a)), Vector3.ZERO), -2.5, 0.0, 0.1).set_trans(Tween.TRANS_SINE)
	_animate(0.3)


## 切った人と反対側へ倒す。根元を軸に、ゆっくり傾き始めてから加速し、地面で小さく跳ねる。
func _fell(dir: Vector3) -> void:
	alive = false
	claimed_by = null
	if _shake_tween:
		_shake_tween.kill()
	_bar_root.visible = false
	_stump.visible = true
	_shape.set_deferred("disabled", true)
	felled.emit(self)
	var axis := Vector3.UP.cross(dir).normalized()
	var rot := func(deg: float) -> void:
		_visual.transform = Transform3D(Basis(axis, deg_to_rad(deg)), Vector3.ZERO)
	_visual.scale = Vector3.ONE
	var tween := create_tween()
	# メキッと少し傾く → 倒れる（重力のように加速）→ 着地で跳ね返る
	tween.tween_method(rot, 0.0, 7.0, CREAK_SEC).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_method(rot, 7.0, 90.0, FALL_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _on_landed(dir))
	tween.tween_method(rot, 90.0, 82.0, 0.09).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(rot, 82.0, 90.0, 0.11).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 土ぼこりの中で小さくなって消える（丸太に変わる）
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.32).set_delay(0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void:
		_visual.visible = false
		_push_visual())
	_animate(CREAK_SEC + FALL_SEC + 0.2 + 0.5)
	# 倒れ始めに葉がこぼれる
	Vfx.leaves(self, global_position + Vector3(0, _canopy_height(), 0), _leaf_tint(), 5, 0.7 * _scale, 0.5)
	Audio.play("tree_fall", -3.0)


func _on_landed(dir: Vector3) -> void:
	var leaf := _leaf_tint()
	var reach := _canopy_height()
	var crown := global_position + dir * reach
	# 樹冠が地面に打ちつけられて葉が舞い、幹に沿って土ぼこりが立つ
	Vfx.leaves(self, crown + Vector3(0, 0.4, 0), leaf, 14, 0.8 * _scale, 2.2)
	Vfx.dust(self, crown + Vector3(0, 0.15, 0), Color("#d9cdb0"), 7, 0.9 * _scale, 2.4, true, 1.0)
	Vfx.dust(self, global_position + dir * reach * 0.45 + Vector3(0, 0.1, 0), Color("#d9cdb0"), 4, 0.7 * _scale, 1.6, true, 0.9)
	Vfx.wood_chips(self, global_position + Vector3(0, 0.25, 0), -dir, [Color("#f0d9a8"), Color("#e2bd85")], 6)
	Fx.shake(self, 0.1)
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
