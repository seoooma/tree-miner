class_name LogLine
extends Node3D
## 遠くの丸太を製材所まで自動で運ぶ川流し。強化で開放し、レベルで流れが速くなる。
## - マップの左端に、奥から拠点まで1本流れている
## - 各エリアの岸にある枠に丸太を置くと、川を流れて拠点へ向かう
## - 拠点の端まで流れ着いた丸太は、いったん岸の集積所に積まれる
## - 集積所の丸太は、最初はプレイヤー（か運搬車）が枠に立って拾い、製材所まで運ぶ
## - 強化『集積所コンベア』を開放すると、ベルトコンベアで製材所の丸太置き場へ自動で運ばれる
##   （1秒あたりの本数は強化レベルで増える。丸太置き場がいっぱいならコンベアは止まり、集積所に溜まる）

const MAX_VISIBLE := 160
## 集積所に見た目で積む最大数
const YARD_VISIBLE := 60
## 集積所の枠の半径（ここに立つと丸太を拾う）
const YARD_RADIUS := 1.3

const UPGRADE_ID := "river"
const CONVEYOR_ID := "conveyor"
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
var _yard_zone: Zone
## 集積所の枠で拾う処理（受け渡し間隔の管理）
var _yard_station: Station
## 集積所 → 製材所の丸太置き場のコンベア（強化で開放）
var belt: Conveyor
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
	for id in GameState.stock_list("yard"):
		_yard.append({"tree": id, "z": near_z, "node": null, "from": null})
	_rebuild_yard()
	GameState.saving.connect(_save_stock)
	for i in area_ranges.size():
		var r := area_ranges[i]
		var p := LoadingPoint.new()
		p.line = self
		p.area_index = i
		p.position = Vector3(x + 3.3, 0, (r.x + r.y) * 0.5)
		add_child(p)
		_points.append(p)
	GameState.upgrade_changed.connect(func(id: String, _l: int) -> void:
		if id == UPGRADE_ID or id == CONVEYOR_ID:
			_refresh())
	GameState.area_unlocked.connect(func(_i: int) -> void: _refresh())
	_refresh()


func is_active() -> bool:
	return GameState.level(UPGRADE_ID) > 0


func speed() -> float:
	return GameState.value(UPGRADE_ID)


func conveyor_active() -> bool:
	return GameState.level(CONVEYOR_ID) > 0


func _refresh() -> void:
	visible = is_active()
	belt.set_active(is_active() and conveyor_active())
	for p in _points:
		p.refresh()


## 集積所・川・コンベアの丸太は、セーブでは集積所に積まれている扱いにする
func _save_stock() -> void:
	var ids: Array[String] = []
	for list in [_yard, _items]:
		for item in list:
			ids.append(str(item["tree"]))
	ids.append_array(belt.ids_in_flight())
	GameState.stock["yard"] = ids


## 枠に置かれた丸太を流す。
func launch(tree_id: String, from: LoadingPoint) -> void:
	var item := {"tree": tree_id, "z": from.global_position.z, "node": null, "from": from, "phase": randf() * TAU}
	if _visible_count() < MAX_VISIBLE:
		item["node"] = _make_item_visual(tree_id)
		_visual.add_child(item["node"])
	_items.append(item)


## このLoadingPoint から出て、まだ集積所から運び出されていない数（川・集積所の合計）
func in_transit_from(p: LoadingPoint) -> int:
	var n := 0
	for list in [_items, _yard]:
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


## 集積所の丸太を拾う枠の位置
func yard_pad_position() -> Vector3:
	return yard_position() + Vector3(0, 0, 2.0)


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
	_process_yard_pickup(delta)
	_update_yard_label()
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


## 集積所の丸太を1本取り出す（コンベア・手で拾う共通）。無ければ空文字
func take_from_yard() -> String:
	if _yard.is_empty():
		return ""
	var item: Dictionary = _yard.pop_back()
	_rebuild_yard()
	var from: LoadingPoint = item["from"]
	if is_instance_valid(from):
		from.refresh_text()
	return str(item["tree"])


## 集積所の枠に立ったプレイヤー・運搬車が丸太を拾う
func _process_yard_pickup(delta: float) -> void:
	if _yard.is_empty() or not visible:
		return
	for carrier in _yard_station.carriers_near(yard_pad_position(), YARD_RADIUS, "plank_carriers"):
		var stack: CarryStack = carrier.stack
		if not stack.is_full() and not _yard.is_empty() and _yard_station.tick(carrier, "yard", delta):
			var top := _yard_top()
			var id := take_from_yard()
			stack.add({"kind": "log", "tree": id})
			Fx.fly_item(self, LogDrop.make_log_mesh(id), top, (carrier as Node3D).global_position + Vector3(0, 1.0, 0), 0.2)


func _update_yard_label() -> void:
	if _yard_zone == null:
		return
	var sub := "丸太: %d" % _yard.size()
	if conveyor_active():
		_yard_zone.set_text("コンベアで搬送中" if not _yard.is_empty() else "集積所", sub)
	else:
		_yard_zone.set_text("丸太を拾う" if not _yard.is_empty() else "集積所", sub)


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
	# 丸太を拾う枠（集積所の手前、拠点側）
	_yard_zone = Zone.new(Vector2.ONE * YARD_RADIUS * 2.0, Color(0.95, 0.8, 0.3, 0.16))
	_yard_zone.position = yard_pad_position()
	_visual.add_child(_yard_zone)
	_yard_station = Station.new()
	add_child(_yard_station)
	var signboard := Props.signboard("川流し 集積所")
	signboard.position = Vector3(x - 1.6, 0, near_z + 3.2)
	signboard.rotation_degrees.y = 30.0
	signboard.scale = Vector3.ONE * 0.9
	_visual.add_child(signboard)


## 集積所から製材所の丸太置き場までのベルトコンベア（強化で開放するまでは隠しておく）
func _build_belt() -> void:
	var yp := yard_position()
	var goal := sawmill.input_pile_position()
	var start := yp + Vector3(1.0, 0, 0)
	var end := Vector3(goal.x - 0.9, 0, goal.z)
	var path: Array[Vector3] = [start]
	if absf(start.z - end.z) > 0.05:
		path.append(Vector3(start.x, 0, end.z))
	path.append(end)
	belt = Conveyor.new()
	belt.path = path
	belt.rate_source = func() -> float: return GameState.value(CONVEYOR_ID)
	belt.take_source = take_from_yard
	belt.room_source = func(n: int) -> bool: return sawmill.has_input_room(n)
	belt.deliver = func(id: String) -> void: sawmill.accept_log(id)
	add_child(belt)
	belt.set_active(false)


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
