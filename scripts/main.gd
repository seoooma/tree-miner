extends Node3D
## ゲーム全体の組み立て。マップ・施設・木・プレイヤー・カメラ・UIを data/balance.json から生成する。
##
## マップ構成（上から見て、画面上方向が -Z）:
##   z > 0         : 拠点（製材所・出荷場）
##   z = 0 .. -20  : エリア0（最初から開放）
##   z = -20 .. -40: エリア1（柵の手前のパッドで支払うと開放）... 以降も同様
## 拠点に近いエリアほど柔らかい木が多く、遠いほど硬い木が多い（重みは JSON で設定）。

const SAWMILL_POS := Vector3(-5, 0, 9)
const DOCK_POS := Vector3(5.5, 0, 9)
const PLAYER_SPAWN := Vector3(1, 0, 4)
const FUEL_POS := Vector3(0, 0, 14)
## 機械の出現位置（伐採機は、川の集積所から製材所へのコンベアを避けて少し手前）
const MACHINE_SPAWN := {"harvester": Vector3(-12, 0, 12), "hauler": Vector3(12, 0, 11)}
## 川流し（左端）の通る位置。木はこの帯と積み込み枠のまわりには生やさない
const LINE_X := {"river": -16.5}
const LINE_CLEAR_X := 14.6
## 川岸の積み込み枠の位置（川の中心からの x）
const LOADING_POINT_DX := 3.3
## 拠点の土の作業場: Vector4(中心x, 中心z, 半幅x, 半幅z)。製材所・出荷場・給油所の広場、森への道、
## 左（川の集積所と伐採機の出現位置）と右（運搬車の出現位置）、出荷場の奥から拠点の外（右端）へ抜ける販売のトラックの道
const SAND_RECTS: Array[Vector4] = [
	Vector4(14.5, 4.6, 7.0, 1.5),
	Vector4(-0.5, 10.0, 9.5, 5.6),
	Vector4(0.0, 2.0, 1.9, 3.2),
	Vector4(-13.0, 8.6, 4.6, 4.8),
	Vector4(11.5, 9.8, 3.0, 3.4),
]

var player: Player
var camera: FollowCamera
var sawmill: Sawmill
var dock: ShipDock
var guide: GuideArrows
var lines: Dictionary = {}  # "river" -> LogLine
var hud: Hud
var lumberjacks: Array[Lumberjack] = []
var machines: Dictionary = {}  # kind -> Machine

var _area_ranges: Array[Vector2] = []  # 各エリアの (near_z, far_z)


func _ready() -> void:
	_compute_area_ranges()
	_build_environment()
	_build_ground()
	# 川の上（水面と土手）には草・花・石を置かない
	Decor.clear_bands.clear()
	for kind in LINE_X:
		Decor.clear_bands.append(Vector2(LINE_X[kind], 2.4))
	# 地面の枠（川の積み込み枠・エリア開放の支払い枠）の上にも置かない
	Decor.clear_rects.clear()
	for i in _area_ranges.size():
		var cz := (_area_ranges[i].x + _area_ranges[i].y) * 0.5
		for kind in LINE_X:
			Decor.clear_rects.append(Vector4(LINE_X[kind] + LOADING_POINT_DX, cz, 1.9, 1.9))
		if i > 0:
			Decor.clear_rects.append(Vector4(0.0, _area_ranges[i].x + AreaGate.PAD_OFFSET.z, 2.1, 1.8))
	Decor.build(self, _area_ranges, _width(), float(GameData.world.get("base_depth", 18)), int(GameData.world.get("seed", 1)))
	_build_bounds()
	_build_facilities()
	_build_gates()
	_build_lines()
	_spawn_trees()
	_spawn_player()
	_build_camera()
	guide = GuideArrows.new()
	guide.player = player
	guide.sawmill = sawmill
	guide.dock = dock
	guide.river = lines.get("river")
	add_child(guide)
	hud = Hud.new()
	hud.guide = guide
	add_child(hud)
	hud.bind_player(player)
	_sync_lumberjacks()
	GameState.upgrade_changed.connect(func(id: String, _l: int) -> void:
		if id == "lumberjack":
			_sync_lumberjacks())
	GameState.lumberjack_role_changed.connect(func(i: int, role: String) -> void:
		if i < lumberjacks.size():
			lumberjacks[i].set_role(role))
	for kind in GameData.machines:
		if kind.begins_with("_"):
			continue
		if GameState.machine_rank(kind) > 0:
			_spawn_machine(kind)
	GameState.machine_changed.connect(_on_machine_changed)


func _unhandled_input(event: InputEvent) -> void:
	# デバッグ用ショートカット（リリース時は削除してよい）
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F9:
				GameState.add_money(1000)
			KEY_F10:
				GameState.reset_game()
				get_tree().reload_current_scene()


# ---- マップ ----

func _width() -> float:
	return float(GameData.world.get("width", 40))


func _compute_area_ranges() -> void:
	var z := 0.0
	for area in GameData.areas:
		var depth := float(area.get("depth", 20))
		_area_ranges.append(Vector2(z, z - depth))
		z -= depth


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#6fb4ef")
	sky_mat.sky_horizon_color = Color("#cfe8f7")
	sky_mat.ground_horizon_color = Color("#cfe8f7")
	sky_mat.ground_bottom_color = Color("#9cc7e6")
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# 影の部分は黒ではなく、空の青紫がかった色になるようにする（環境光を単色で強めに入れる）。
	# 写実ではなくフラットカラーのローポリなので、トーンマップは色をそのまま出す Linear にする
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8e9ccf")
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	# 遠くがうっすら空色に霞む（奥行きが出る）
	env.fog_enabled = true
	env.fog_light_color = Color("#cfe6f2")
	env.fog_light_energy = 1.0
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	# グロー・色調補正は Web 版（Compatibility レンダラー）だと画面全体が白っぽく色あせるので使わない。
	# 光る演出は加算合成のスプライト（Vfx）で出している
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# 暖色の太陽をカメラ側の左上から当てる（見えている面が明るく、影は画面の奥・右へ落ちる）。
	# 影は濃すぎないようにして、環境光の青紫を残す
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_color = Color("#fff0d6")
	sun.light_energy = 0.45
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.78
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# 影の範囲をカメラに映る範囲に合わせて、2048px の影マップをくっきり使う
	sun.directional_shadow_max_distance = 26.0
	add_child(sun)
	_build_vignette()


## 画面の四隅をほんのり暗くして、中央（プレイヤーのまわり）に目が行くようにする。
## ポストエフェクトではなく半透明の画像を1枚重ねるだけなので、スマホでも軽い。
func _build_vignette() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.08, 0.06, 0.04, 0.0), Color(0.08, 0.06, 0.04, 0.0), Color(0.08, 0.06, 0.04, 0.32)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.08, 0.5)
	tex.width = 128
	tex.height = 128
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 0
	layer.add_child(rect)
	add_child(layer)


func _build_ground() -> void:
	var width := _width()
	var base_depth := float(GameData.world.get("base_depth", 18))
	# 拠点は草地の中に、施設のまわりと通り道だけ土を敷く（何もない土の広場にしない）
	Mats.sand_rects = SAND_RECTS
	_add_ground_tile(width, base_depth, base_depth * 0.5, "grass", Color.WHITE)
	for i in GameData.areas.size():
		var r := _area_ranges[i]
		# 奥のエリアほどわずかに深い緑（どこまで来たかが色でわかる程度）
		var tint := Color.WHITE.lerp(Color("#d6e6cf"), minf(1.0, i * 0.25))
		_add_ground_tile(width, r.x - r.y, (r.x + r.y) * 0.5, "grass", tint)


func _add_ground_tile(width: float, depth: float, center_z: float, kind: String, tint: Color) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(width, depth)
	mesh.material = Mats.ground(kind, tint)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0, 0, center_z)
	add_child(mi)


## プレイヤーがマップ外に出ないための見えない壁。
func _build_bounds() -> void:
	var width := _width()
	var near := float(GameData.world.get("base_depth", 18))
	var far: float = _area_ranges[-1].y if not _area_ranges.is_empty() else 0.0
	var length := near - far
	var center_z := (near + far) * 0.5
	_add_wall(Vector3(1, 4, length), Vector3(-width * 0.5 - 0.5, 2, center_z))
	_add_wall(Vector3(1, 4, length), Vector3(width * 0.5 + 0.5, 2, center_z))
	_add_wall(Vector3(width, 4, 1), Vector3(0, 2, near + 0.5))
	_add_wall(Vector3(width, 4, 1), Vector3(0, 2, far - 0.5))


func _add_wall(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _build_facilities() -> void:
	sawmill = Sawmill.new()
	sawmill.position = SAWMILL_POS
	add_child(sawmill)
	dock = ShipDock.new()
	dock.sawmill = sawmill
	dock.position = DOCK_POS
	add_child(dock)
	var fuel := FuelStation.new()
	fuel.position = FUEL_POS
	add_child(fuel)


func _build_lines() -> void:
	for kind in LINE_X:
		var line := LogLine.new()
		line.x = LINE_X[kind]
		line.far_z = _area_ranges[-1].y + 1.0
		line.near_z = 3.0
		line.sawmill = sawmill
		line.area_ranges = _area_ranges
		add_child(line)
		lines[kind] = line


func _build_gates() -> void:
	for i in range(1, GameData.areas.size()):
		if GameState.is_area_unlocked(i):
			continue
		var gate := AreaGate.new()
		gate.area_index = i
		gate.width = _width()
		gate.position = Vector3(0, 0, _area_ranges[i].x)
		add_child(gate)


func _spawn_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameData.world.get("seed", 1))
	var spacing := float(GameData.world.get("tree_min_spacing", 2.3))
	var half := _width() * 0.5 - 2.0
	var placed: Array[Vector3] = []
	var field := TreeField.new()
	field.name = "TreeField"
	add_child(field)
	for i in GameData.areas.size():
		var area: Dictionary = GameData.areas[i]
		var r := _area_ranges[i]
		var count := int(area.get("tree_count", 15))
		var attempts := 0
		var spawned := 0
		while spawned < count and attempts < count * 40:
			attempts += 1
			var pos := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(r.y + 1.5, r.x - 2.0))
			if not _is_free_spot(pos, placed, spacing):
				continue
			var tree := ChoppableTree.new()
			tree.field = field
			tree.setup(GameData.tree_def(GameData.pick_tree_for_area(i, rng)), i, rng.randi() % ChoppableTree.VARIANTS)
			tree.position = pos
			tree.rotation.y = rng.randf() * TAU
			add_child(tree)
			placed.append(pos)
			spawned += 1
	field.build()


func _is_free_spot(pos: Vector3, placed: Array[Vector3], spacing: float) -> bool:
	# 中央の道は空けておく（機械が走りやすいように）
	# 左右の端も空けておく（左は川。右は配置を変えないよう従来どおり空ける）
	if absf(pos.x) < 1.8 or absf(pos.x) > LINE_CLEAR_X:
		return false
	# 川岸の積み込み枠のまわり（左右対称）
	for i in _area_ranges.size():
		var cz := (_area_ranges[i].x + _area_ranges[i].y) * 0.5
		# 枠（2.8m 四方）に木の幹だけでなく枝葉もかからないように、枠の外側 1.4m まで空ける
		if absf(absf(pos.x) - 13.2) < 2.8 and absf(pos.z - cz) < 2.8:
			return false
	for p in placed:
		if Fx.xz_distance(p, pos) < spacing:
			return false
	# 柵の支払いパッドの周りは空けておく
	for i in range(1, _area_ranges.size()):
		if Fx.xz_distance(pos, Vector3(0, 0, _area_ranges[i].x + AreaGate.PAD_OFFSET.z)) < 3.5:
			return false
	return true


func _spawn_player() -> void:
	player = Player.new()
	player.position = PLAYER_SPAWN
	add_child(player)


func _build_camera() -> void:
	camera = FollowCamera.new()
	camera.target = player
	add_child(camera)
	camera.snap()


func _sync_lumberjacks() -> void:
	var wanted := roundi(GameState.value("lumberjack"))
	while lumberjacks.size() < wanted:
		var lj := Lumberjack.new()
		lj.index = lumberjacks.size()
		lj.role = GameState.lumberjack_role(lj.index)
		lj.sawmill = sawmill
		lj.position = sawmill.input_position() + Vector3(lumberjacks.size() * 0.8 - 1.0, 0, -1.0)
		add_child(lj)
		lumberjacks.append(lj)


# ---- 機械 ----

func _on_machine_changed(kind: String, rank: int) -> void:
	if machines.has(kind):
		(machines[kind] as Machine).set_rank(rank)
	else:
		_spawn_machine(kind, true)


func _spawn_machine(kind: String, fresh := false) -> void:
	var m := Machine.new()
	m.kind = kind
	m.rank = GameState.machine_rank(kind)
	var saved: Dictionary = GameState.machine_state.get(kind, {})
	if fresh or saved.is_empty():
		# 最初の燃料は満タン
		m.position = MACHINE_SPAWN[kind]
		m.fuel = float(GameData.machine_rank(kind, m.rank).get("fuel_max", 60))
	else:
		m.position = Vector3(float(saved.get("x", 0)), 0, float(saved.get("z", 0)))
		m.rotation.y = float(saved.get("ry", 0))
		m.fuel = float(saved.get("fuel", 0))
	add_child(m)
	machines[kind] = m
	if fresh:
		Fx.popup(m, m.global_position, "%s 登場！" % m.display_name(), Color("#ffe14d"))
