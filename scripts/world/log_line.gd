class_name LogLine
extends Node3D
## 遠くの丸太を製材所まで自動で運ぶ川流し。強化「川の流れ」のレベルで流れが速くなる。
## - マップの左端に、奥から拠点まで1本流れている（川そのものは最初から見えている）
## - 各エリアの岸にある川の積み場は、その場で支払って開放する（1つ開放すると集積所も使えるようになる）
## - 開放した積み場の枠に丸太を置くと、川を流れて拠点へ向かう
## - 拠点の端まで流れ着いた丸太は、いったん岸の集積所に積まれる
## - 集積所の丸太は、最初はプレイヤー（か運搬車）が枠に立って拾い、製材所まで運ぶ
## - 強化『集積所コンベア』を開放すると、ベルトコンベアで製材所の丸太置き場へ自動で運ばれる
##   （1秒あたりの本数は強化レベルで増える）

const MAX_VISIBLE := 160
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
var _yard_pile: ItemPile
var _yard_zone: Zone
## 集積所の枠で拾う処理（受け渡し間隔の管理）
var _yard_station: Station
## 集積所 → 製材所の丸太置き場のコンベア（強化で開放）
var belt: Conveyor
var _visual: Node3D
var _points: Array[LoadingPoint] = []
var _time := 0.0
var _water_mat: ShaderMaterial
## 水門の白い水しぶき
var _gate_splash: CPUParticles3D


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
		p.position = Vector3(x + 3.3, 0, (r.x + r.y) * 0.5)  # main.gd の LOADING_POINT_DX と同じ
		add_child(p)
		_points.append(p)
	GameState.upgrade_changed.connect(func(id: String, _l: int) -> void:
		if id == UPGRADE_ID or id == CONVEYOR_ID:
			_refresh())
	GameState.area_unlocked.connect(func(_i: int) -> void: _refresh())
	GameState.river_point_unlocked.connect(func(_i: int) -> void: _refresh())
	_refresh()


## 川岸の積み場（エリアごとに1つ）
func points() -> Array[LoadingPoint]:
	return _points


## 川の積み場を1つでも開放していれば流れる
func is_active() -> bool:
	return GameState.is_river_open()


func speed() -> float:
	return GameState.value(UPGRADE_ID)


func conveyor_active() -> bool:
	return GameState.level(CONVEYOR_ID) > 0


func _refresh() -> void:
	# 川は最初から見せておき（積み場の支払い枠の場所がわかるように）、集積所の枠は開放してから出す
	if _gate_splash:
		_gate_splash.emitting = is_active()
	if _yard_zone:
		_yard_zone.visible = is_active()
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
	Vfx.splash(self, Vector3(x, 0.1, from.global_position.z))


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
	return _yard_pile.top_global()


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
	if _yard.is_empty() or not is_active():
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


## 集積所の丸太の山。数は待っている丸太と同じ
func _rebuild_yard() -> void:
	var ids: Array[String] = []
	for item in _yard:
		ids.append(str(item["tree"]))
	_yard_pile.show_items(ids)


func _make_item_visual(tree_id: String) -> Node3D:
	var log_mesh := LogDrop.make_log_mesh(tree_id)
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
	# 土手・水面は大きな半透明の板。並べ替えで水面が土手の下に隠れたり、積み込み枠の上に重なったりしないよう、描く順を固定する
	bank_mi.sorting_offset = -100.0
	_visual.add_child(bank_mi)
	var water := PlaneMesh.new()
	water.size = Vector2(2.6, length)
	_water_mat = water_material()
	water.material = _water_mat
	var water_mi := MeshInstance3D.new()
	water_mi.mesh = water
	water_mi.position = Vector3(x, 0.03, center)
	water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mi.sorting_offset = -90.0
	_visual.add_child(water_mi)
	# 岸の石
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var z := far_z
	while z < near_z:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.55:
				var r := Fx.sphere(rng.randf_range(0.12, 0.22), Color("#a9b0b8"), Vector3(x + side * rng.randf_range(1.3, 1.6), 0.05, z), 6, 3, true)
				r.scale.y = 0.6
				_visual.add_child(r)
		z += 1.3


## 拠点側の終点（水門）と、流れ着いた丸太を積む集積所・看板
func _build_end() -> void:
	for side in [-1.5, 1.5]:
		_visual.add_child(Fx.box(Vector3(0.3, 1.4, 0.3), Color("#7a5a3a"), Vector3(x + side, 0.7, near_z + 0.4), "wood"))
	_visual.add_child(Fx.box(Vector3(3.3, 0.25, 0.3), Color("#7a5a3a"), Vector3(x, 1.35, near_z + 0.4), "wood"))
	_gate_splash = Vfx.make_splash(2.4)
	_gate_splash.position = Vector3(x, 0.08, near_z + 0.2)
	_visual.add_child(_gate_splash)
	# 集積所の床（丸太の山の下の板敷き）
	var yp := yard_position()
	_visual.add_child(Fx.box(Vector3(1.9, 0.08, 1.8), Color("#8a6a45"), yp + Vector3(0, 0.04, 0), "wood"))
	# 丸太を左右に向けて奥行きに6本（1段6本。上の段は半分ずらす）。数は待っている丸太と同じ
	_yard_pile = ItemPile.new(func(id: String) -> MeshInstance3D:
		var log_mesh := LogDrop.make_log_mesh(id, 0.0) as MeshInstance3D
		return log_mesh)
	_yard_pile.cols = 1
	_yard_pile.rows = 6
	_yard_pile.step = Vector3(0, 0, 0.23)
	_yard_pile.stagger = Vector3(0, 0, 0.115)
	_yard_pile.position = yp
	_visual.add_child(_yard_pile)
	# 丸太を拾う枠（集積所の手前、拠点側）
	_yard_zone = Zone.new(Vector2.ONE * YARD_RADIUS * 2.0, Color(0.95, 0.8, 0.3, 0.16))
	_yard_zone.position = yard_pad_position()
	_visual.add_child(_yard_zone)
	_yard_station = Station.new()
	add_child(_yard_station)
	var signboard := Props.signboard("川流し 集積所", Color("#2bb0c2"))
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
	// 流れに沿って伸びる筋
	float streak = texture(noise_tex, vec2(wpos.x * 0.9, wpos.z * 0.08 - flow * 0.7)).r;
	// フラットな画風に合わせて、明るい水色の単色＋くっきりした白い泡の筋だけにする
	vec3 deep = vec3(0.03, 0.34, 0.62);
	vec3 shallow = vec3(0.16, 0.65, 0.75);
	float d = min(UV.x, 1.0 - UV.x);
	float edge = smoothstep(0.0, 0.22, d);
	vec3 col = mix(shallow, deep, edge);
	float foam = 1.0 - step(0.06, d + (n2 - 0.5) * 0.06);
	foam += step(0.8, streak * 0.7 + n1 * 0.3) * 0.85;
	col = mix(col, vec3(0.92, 0.97, 1.0), clamp(foam, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.35;
	METALLIC = 0.0;
	SPECULAR = 0.4;
	ALPHA = max(0.9 * edge + 0.08, clamp(foam, 0.0, 1.0));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", Mats.tex("leaf_noise.png"))
	return m
