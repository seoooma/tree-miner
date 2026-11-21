class_name LogLine
extends Node3D
## 遠くの丸太を製材所まで自動で運ぶ川流し。強化で開放し、レベルで流れが速くなる。
## - マップの左端に、奥から拠点まで1本流れている
## - 各エリアの岸にある枠に丸太を置くと、川を流れて拠点へ向かう
## - 拠点の端まで流れ着いた丸太は、いったん岸の集積所に積まれる
## - 集積所の丸太はベルトコンベアで1本ずつ製材所の丸太置き場へ運ばれる（製材ライン未開放ならそこで売れる）

const MAX_VISIBLE := 160
## 集積所に見た目で積む最大数
const YARD_VISIBLE := 40
## 集積所からコンベアに1本載せる間隔（秒）とコンベアの速さ（m/秒）
const DISPATCH_INTERVAL := 0.3
const BELT_SPEED := 3.0

const UPGRADE_ID := "river"
var x := -16.5
var near_z := 3.0
var far_z := -100.0
var sawmill: Sawmill
var area_ranges: Array[Vector2] = []

## 運搬中の丸太 {"tree": id, "z": 現在位置, "node": 見た目 or null, "from": 積み込んだ LoadingPoint}
var _items: Array[Dictionary] = []
## 集積所で待っている丸太（_items と同じ辞書）
var _yard: Array[Dictionary] = []
var _yard_pile: Node3D
var _dispatch_timer := 0.0
## コンベアに載っている丸太 {"tree", "d": 進んだ距離, "node", "from"}
var _belt: Array[Dictionary] = []
## コンベアの経路（集積所 → 製材所の丸太置き場）
var _belt_path: Array[Vector3] = []
var _belt_length := 0.0
## コンベアで製材所に渡した丸太の累計
var delivered := 0
var _visual: Node3D
var _points: Array[LoadingPoint] = []
var _time := 0.0
var _water_mat: ShaderMaterial


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_build_river()
	_build_end()
	_build_belt()
	for i in area_ranges.size():
		var r := area_ranges[i]
		var p := LoadingPoint.new()
		p.line = self
		p.area_index = i
		p.position = Vector3(x + 3.3, 0, (r.x + r.y) * 0.5)
		add_child(p)
		_points.append(p)
	GameState.upgrade_changed.connect(func(id: String, _l: int) -> void:
		if id == UPGRADE_ID:
			_refresh())
	GameState.area_unlocked.connect(func(_i: int) -> void: _refresh())
	_refresh()


func is_active() -> bool:
	return GameState.level(UPGRADE_ID) > 0


func speed() -> float:
	return GameState.value(UPGRADE_ID)


func _refresh() -> void:
	visible = is_active()
	for p in _points:
		p.refresh()


## 枠に置かれた丸太を流す。
func launch(tree_id: String, from: LoadingPoint) -> void:
	var item := {"tree": tree_id, "z": from.global_position.z, "node": null, "from": from, "phase": randf() * TAU}
	if _visible_count() < MAX_VISIBLE:
		item["node"] = _make_item_visual(tree_id)
		_visual.add_child(item["node"])
	_items.append(item)


## このLoadingPoint から出て、まだ製材所に届いていない数（川・集積所・コンベアの合計）
func in_transit_from(p: LoadingPoint) -> int:
	var n := 0
	for list in [_items, _yard, _belt]:
		for item in list:
			if item["from"] == p:
				n += 1
	return n


## 集積所に積まれている丸太の数
func yard_count() -> int:
	return _yard.size()


## 集積所の位置（丸太の山の中心）
func yard_position() -> Vector3:
	return Vector3(x + 1.1, 0, near_z + 2.4)


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
	_process_belt(delta)
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
			var ph: float = item["phase"]
			node.position = Vector3(x + sin(z * 0.6 + ph) * 0.35, -0.02 + sin(_time * 3.0 + ph) * 0.03, z)
			node.rotation.y = PI * 0.5 + sin(z * 0.4 + ph) * 0.4
		if float(item["z"]) >= near_z:
			_items.remove_at(i)
			_land_in_yard(item)
			continue
		i += 1


## 流れ着いた丸太を岸の集積所に引き上げる
func _land_in_yard(item: Dictionary) -> void:
	var node: Node3D = item["node"]
	if node:
		node.queue_free()
		Fx.fly_item(self, LogDrop.make_log_mesh(item["tree"]), Vector3(x, 0.1, near_z), _yard_top(), 0.3)
	item["node"] = null
	_yard.append(item)
	_rebuild_yard()


func _yard_top() -> Vector3:
	return yard_position() + Vector3(0, 0.15 + floori(mini(_yard.size(), YARD_VISIBLE) / 4.0) * 0.2, 0)


## 集積所の丸太を1本ずつコンベアに載せ、端まで運んだら製材所に渡す
func _process_belt(delta: float) -> void:
	if not _yard.is_empty():
		_dispatch_timer -= delta
		if _dispatch_timer <= 0.0:
			_dispatch_timer = DISPATCH_INTERVAL
			var item: Dictionary = _yard.pop_back()
			item["d"] = 0.0
			item["node"] = LogDrop.make_log_mesh(item["tree"])
			_visual.add_child(item["node"])
			_belt.append(item)
			_rebuild_yard()
	else:
		_dispatch_timer = 0.0
	var i := 0
	while i < _belt.size():
		var item := _belt[i]
		item["d"] = float(item["d"]) + BELT_SPEED * delta
		var node: Node3D = item["node"]
		if float(item["d"]) >= _belt_length:
			node.queue_free()
			_belt.remove_at(i)
			sawmill.accept_log(item["tree"])
			delivered += 1
			var from: LoadingPoint = item["from"]
			if is_instance_valid(from):
				from.refresh_text()
			continue
		var t := _belt_point(float(item["d"]))
		node.position = t[0] + Vector3(0, 0.44, 0)
		node.rotation.y = t[1]
		i += 1


## コンベア上の距離 d の位置と向き（丸太が進行方向に直角になる角度）
func _belt_point(d: float) -> Array:
	for k in range(1, _belt_path.size()):
		var a := _belt_path[k - 1]
		var b := _belt_path[k]
		var seg := a.distance_to(b)
		if d <= seg or k == _belt_path.size() - 1:
			var dir := (b - a).normalized()
			return [a.lerp(b, clampf(d / seg, 0.0, 1.0)), atan2(dir.x, dir.z)]
		d -= seg
	return [_belt_path[-1], 0.0]


## 集積所の丸太の山（4本ずつ積む）。数は待っている丸太と同じ
func _rebuild_yard() -> void:
	for c in _yard_pile.get_children():
		c.queue_free()
	for i in mini(_yard.size(), YARD_VISIBLE):
		var col := i % 4
		var row := floori(i / 4.0)
		var log_mesh := LogDrop.make_log_mesh(_yard[i]["tree"], 0.0)
		log_mesh.scale = Vector3(1.5, 1.0, 1.0)
		log_mesh.position = Vector3(0, 0.12 + row * 0.2, (col - 1.5) * 0.23 + (0.11 if row % 2 == 1 else 0.0))
		_yard_pile.add_child(log_mesh)


func _make_item_visual(tree_id: String) -> Node3D:
	var log_mesh := LogDrop.make_log_mesh(tree_id)
	log_mesh.scale = Vector3(1.6, 1.4, 1.4)
	return log_mesh


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


## 拠点側の終点（水門）と、流れ着いた丸太を積む集積所・看板
func _build_end() -> void:
	for side in [-1.5, 1.5]:
		_visual.add_child(Fx.box(Vector3(0.3, 1.4, 0.3), Color("#7a5a3a"), Vector3(x + side, 0.7, near_z + 0.4), "wood"))
	_visual.add_child(Fx.box(Vector3(3.3, 0.25, 0.3), Color("#7a5a3a"), Vector3(x, 1.35, near_z + 0.4), "wood"))
	# 集積所の床（丸太の山の下の板敷き）
	var yp := yard_position()
	_visual.add_child(Fx.box(Vector3(1.9, 0.08, 1.6), Color("#8a6a45"), yp + Vector3(0, 0.04, 0), "wood"))
	_yard_pile = Node3D.new()
	_yard_pile.position = yp
	_visual.add_child(_yard_pile)
	var sign := Props.signboard("川流し 集積所")
	sign.position = Vector3(x - 1.6, 0, near_z + 3.2)
	sign.rotation_degrees.y = 30.0
	sign.scale = Vector3.ONE * 0.9
	_visual.add_child(sign)


## 集積所から製材所の丸太置き場までのベルトコンベア
func _build_belt() -> void:
	var yp := yard_position()
	var goal := sawmill.input_pile_position()
	var start := yp + Vector3(1.0, 0, 0)
	var end := Vector3(goal.x - 0.9, 0, goal.z)
	_belt_path = [start]
	if absf(start.z - end.z) > 0.05:
		_belt_path.append(Vector3(start.x, 0, end.z))
	_belt_path.append(end)
	_belt_length = 0.0
	for k in range(1, _belt_path.size()):
		var a := _belt_path[k - 1]
		var b := _belt_path[k]
		_belt_length += a.distance_to(b)
		var mid := (a + b) * 0.5
		var seg_len := a.distance_to(b) + 0.8
		var along_x := absf(b.x - a.x) > absf(b.z - a.z)
		var belt_size := Vector3(seg_len, 0.05, 0.62) if along_x else Vector3(0.62, 0.05, seg_len)
		var frame_size := Vector3(seg_len, 0.1, 0.74) if along_x else Vector3(0.74, 0.1, seg_len)
		_visual.add_child(Fx.box(frame_size, Color("#8c939a"), mid + Vector3(0, 0.25, 0), "metal"))
		_visual.add_child(Fx.box(belt_size, Color("#3d4247"), mid + Vector3(0, 0.31, 0), "metal"))
		# 脚
		var steps := maxi(1, floori(seg_len / 1.6))
		for j in steps + 1:
			var p := (a - (b - a).normalized() * 0.3).lerp(b + (b - a).normalized() * 0.3, j / float(steps))
			for side in [-0.38, 0.38]:
				var off := Vector3(0, 0, side * 0.8) if along_x else Vector3(side * 0.8, 0, 0)
				_visual.add_child(Fx.box(Vector3(0.07, 0.22, 0.07), Color("#5b6168"), p + off + Vector3(0, 0.11, 0), "metal"))


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
