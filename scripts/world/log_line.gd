class_name LogLine
extends Node3D
## 遠くの丸太を製材所まで自動で運ぶ仕組み（川流し／トロッコ）。強化で開放し、レベルで速くなる。
## - マップの端（川は左、トロッコは右）に、奥から拠点まで1本通っている
## - 各エリアの岸（駅）にある枠に丸太を置くと、川なら流れて、トロッコなら台車に乗って拠点へ向かう
## - 拠点の端まで届いた丸太は製材所が受け取る（製材ライン未開放ならその場で売れる）

const MAX_VISIBLE := 160

var kind := "river"  # "river" / "trolley"
var x := -16.5
var near_z := 3.0
var far_z := -100.0
var sawmill: Sawmill
var area_ranges: Array[Vector2] = []

## 運搬中の丸太 {"tree": id, "z": 現在位置, "node": 見た目 or null, "from": 積み込んだ LoadingPoint}
var _items: Array[Dictionary] = []
var _visual: Node3D
var _points: Array[LoadingPoint] = []
var _time := 0.0
var _water_mat: ShaderMaterial


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	if kind == "river":
		_build_river()
	else:
		_build_rails()
	_build_end()
	for i in area_ranges.size():
		var r := area_ranges[i]
		var p := LoadingPoint.new()
		p.line = self
		p.area_index = i
		var inward := 1.0 if x < 0.0 else -1.0
		p.position = Vector3(x + inward * 3.3, 0, (r.x + r.y) * 0.5)
		add_child(p)
		_points.append(p)
	GameState.upgrade_changed.connect(func(id: String, _l: int) -> void:
		if id == kind:
			_refresh())
	GameState.area_unlocked.connect(func(_i: int) -> void: _refresh())
	_refresh()


func is_active() -> bool:
	return GameState.level(kind) > 0


func speed() -> float:
	return GameState.value(kind)


func _refresh() -> void:
	visible = is_active()
	for p in _points:
		p.refresh()


## 枠に置かれた丸太を流す／台車に乗せる。
func launch(tree_id: String, from: LoadingPoint) -> void:
	var item := {"tree": tree_id, "z": from.global_position.z, "node": null, "from": from, "phase": randf() * TAU}
	if _visible_count() < MAX_VISIBLE:
		item["node"] = _make_item_visual(tree_id)
		_visual.add_child(item["node"])
	_items.append(item)


## このLoadingPoint から出て、まだ届いていない数
func in_transit_from(p: LoadingPoint) -> int:
	var n := 0
	for item in _items:
		if item["from"] == p:
			n += 1
	return n


func _visible_count() -> int:
	var n := 0
	for item in _items:
		if item["node"] != null:
			n += 1
	return n


func _process(delta: float) -> void:
	_time += delta
	if _water_mat:
		_water_mat.set_shader_parameter("flow", _time * speed() * 0.25)
	if _items.is_empty():
		return
	var v := speed() * delta
	var i := 0
	while i < _items.size():
		var item := _items[i]
		item["z"] = float(item["z"]) + v
		var node: Node3D = item["node"]
		if node:
			var z: float = item["z"]
			if kind == "river":
				var ph: float = item["phase"]
				node.position = Vector3(x + sin(z * 0.6 + ph) * 0.35, -0.02 + sin(_time * 3.0 + ph) * 0.03, z)
				node.rotation.y = PI * 0.5 + sin(z * 0.4 + ph) * 0.4
			else:
				node.position = Vector3(x, 0.0, z)
		if float(item["z"]) >= near_z:
			if node:
				node.queue_free()
			_items.remove_at(i)
			sawmill.accept_log(item["tree"])
			var from: LoadingPoint = item["from"]
			if is_instance_valid(from):
				from.refresh_text()
			continue
		i += 1


func _make_item_visual(tree_id: String) -> Node3D:
	if kind == "river":
		var log_mesh := LogDrop.make_log_mesh(tree_id)
		log_mesh.scale = Vector3(1.6, 1.4, 1.4)
		return log_mesh
	var cart := Node3D.new()
	cart.add_child(trolley_cart())
	var log_mesh := LogDrop.make_log_mesh(tree_id, 0.0)
	log_mesh.position = Vector3(0, 0.62, 0)
	log_mesh.rotation_degrees.y = 90.0
	log_mesh.scale = Vector3(1.0, 1.3, 1.3)
	cart.add_child(log_mesh)
	return cart


# ---- 見た目 ----

func _build_river() -> void:
	var length := near_z + 2.0 - far_z
	var center := (near_z + 2.0 + far_z) * 0.5
	# 土手（少し暗い土の帯）と水面
	var bank := PlaneMesh.new()
	bank.size = Vector2(4.2, length)
	bank.material = Mats.strip("road", 0)
	var bank_mi := MeshInstance3D.new()
	bank_mi.mesh = bank
	bank_mi.position = Vector3(x, 0.01, center)
	bank_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(bank_mi)
	var water := PlaneMesh.new()
	water.size = Vector2(2.6, length)
	_water_mat = water_material()
	water.material = _water_mat
	var water_mi := MeshInstance3D.new()
	water_mi.mesh = water
	water_mi.position = Vector3(x, 0.03, center)
	water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(water_mi)
	# 岸の石
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var z := far_z
	while z < near_z:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.55:
				var r := Fx.sphere(rng.randf_range(0.12, 0.22), Color("#8d877c"), Vector3(x + side * rng.randf_range(1.3, 1.6), 0.05, z), 6, 3, true)
				r.scale.y = 0.6
				_visual.add_child(r)
		z += 1.3


func _build_rails() -> void:
	var length := near_z + 1.0 - far_z
	var center := (near_z + 1.0 + far_z) * 0.5
	# 砂利の道床
	var bed := PlaneMesh.new()
	bed.size = Vector2(2.6, length)
	bed.material = Mats.strip("yard", 0)
	var bed_mi := MeshInstance3D.new()
	bed_mi.mesh = bed
	bed_mi.position = Vector3(x, 0.01, center)
	bed_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(bed_mi)
	# レール2本と枕木（MultiMesh でまとめる）
	for side in [-0.45, 0.45]:
		var rail := Fx.box(Vector3(0.08, 0.1, length), Color("#7c8288"), Vector3(x + side, 0.12, center), "metal")
		_visual.add_child(rail)
	var sleeper := BoxMesh.new()
	sleeper.size = Vector3(1.4, 0.08, 0.24)
	sleeper.material = Mats.surface(Color("#6e5238"), "wood")
	var xforms: Array[Transform3D] = []
	var z := far_z
	while z < near_z + 1.0:
		xforms.append(Transform3D(Basis(), Vector3(x, 0.05, z)))
		z += 0.75
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sleeper
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_visual.add_child(mmi)


## 拠点側の終点（川は水門、トロッコは車止め）と看板
func _build_end() -> void:
	if kind == "river":
		for side in [-1.5, 1.5]:
			_visual.add_child(Fx.box(Vector3(0.3, 1.4, 0.3), Color("#7a5a3a"), Vector3(x + side, 0.7, near_z + 0.4), "wood"))
		_visual.add_child(Fx.box(Vector3(3.3, 0.25, 0.3), Color("#7a5a3a"), Vector3(x, 1.35, near_z + 0.4), "wood"))
	else:
		_visual.add_child(Fx.box(Vector3(1.4, 0.5, 0.3), Color("#c43a2e"), Vector3(x, 0.3, near_z + 1.0), "metal"))
	var sign := Props.signboard("川流し 集積所" if kind == "river" else "トロッコ 終点")
	sign.position = Vector3(x + (2.4 if x < 0.0 else -2.4), 0, near_z + 0.8)
	sign.scale = Vector3.ONE * 0.9
	_visual.add_child(sign)


static func water_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float flow = 0.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz * 0.35;
	float n1 = texture(noise_tex, uv + vec2(0.0, -flow)).r;
	float n2 = texture(noise_tex, uv * 1.7 + vec2(0.31, -flow * 1.4)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	vec3 deep = vec3(0.12, 0.3, 0.33);
	vec3 shallow = vec3(0.28, 0.5, 0.5);
	float edge = smoothstep(0.0, 0.18, min(UV.x, 1.0 - UV.x));
	ALBEDO = mix(shallow, deep, edge) * (0.85 + 0.3 * n);
	ROUGHNESS = 0.12 + 0.2 * n;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	NORMAL_MAP = normalize(vec3((n1 - 0.5) * 0.8, (n2 - 0.5) * 0.8, 1.0)) * 0.5 + 0.5;
	ALPHA = 0.88 * edge + 0.1;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", Mats.tex("leaf_noise.png"))
	return m


## トロッコの台車（強化画面のサムネイルでも使う）
static func trolley_cart() -> Node3D:
	var root := Node3D.new()
	root.add_child(Fx.box(Vector3(0.9, 0.36, 1.1), Color("#5b6168"), Vector3(0, 0.42, 0), "metal"))
	root.add_child(Fx.box(Vector3(0.96, 0.06, 1.16), Color("#3c4046"), Vector3(0, 0.62, 0), "metal"))
	for sx in [-0.45, 0.45]:
		for sz in [-0.35, 0.35]:
			var w := Fx.cylinder(0.13, 0.08, Color("#2d3035"), Vector3(sx, 0.2, sz), -1.0, 10, false, "metal")
			w.rotation_degrees.z = 90.0
			root.add_child(w)
	return root
